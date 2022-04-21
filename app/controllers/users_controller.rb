class UsersController < ApplicationController
  include PaginatableHelpers
  include ::RansackableHelpers

  before_action :admin_required, except: [ :show, :update, :privacy_policy ]
  before_action :clean_params, only: [ :create, :update ], :if => proc { |c| c.admin? or c.normal_user? or c.account_manager? }

  skip_before_action :check_account_manager, :only => [:companies_list]
  skip_before_action :check_privacy_policy_accepted, :only => [:privacy_policy, :companies_list]

  layout 'login_old', only: [:companies_list, :privacy_policy]

  # users/:id
  def show
    @user = policy_scope(User).find(params[:id])
    respond_to do |format|
      format.json{ render json: @user, serializer: UserSerializer }
    end
  end

  def me
    respond_to do |format|
      format.json{ render json: current_user, serializer: UserSerializer }
    end
  end

  # POST users
  def create
    params.require(:user).permit!
    @user = User.new(params[:user].except(:deleted, :type, :company_id))

    # secured this in before filter named clean_params
    @user.company_id = params[:company_id]
    @user.type = params[:type]

    respond_to do |format|
      if @user.save
        format.json { render :json => @user }
      else
        format.json { render :json => { :errors => @user.errors }, :status => :unprocessable_entity }
      end
    end
  end

  # POST users/:id
  def update
    params.require(:user).permit!
    @user = policy_scope(User).find(params[:id])
    # secured this in before filter named clean_params
    @user.type = params[:type]

    @user.company_id = params[:company_id] if @user.company_id.nil?

    # leave password blank if you want it to stay the same
    if params[:user][:password].blank?
      params[:user].delete :password
      params[:user].delete :password_confirmation
    end

    @user.avatar = parse_image_data(params.delete(:avatar)) if params[:avatar]

    respond_to do |format|
      if @user.update_attributes(params[:user].except(:deleted, :type, :company_id))
        format.json { render :json => @user }
      else
        format.json { render :json => { :errors => @user.errors }, :status => :unprocessable_entity }
      end
    end
  ensure
    remove_temp_avatar
  end

  # GET /users
  def index
    respond_to do |format|
      format.html { render action: :index }
      format.json do
        users = ransackable(users_relation).includes(:user_group, :devices, company: :subscription)

        if page && per_page
          render json: users, each_serializer: UserSerializer, root: :users,
                 meta: { paging: paging_data(users) }
        else
          render json: users, each_serializer: UserSerializer
        end
      end
    end
  end

  # POST /users/lock
  def lock
    lock_form = BulkUsersProcessingForm.new(current_user, params[:ids]).lock
    respond_to do |format|
      format.html { redirect_to users_path }
      format.json { render json: { errors: lock_form.errors }, status: :ok }
    end
  end

  # DELETE /users/delete
  def delete
    delete_form = BulkUsersProcessingForm.new(current_user, params[:ids]).delete
    respond_to do |format|
      format.html { redirect_to users_path }
      format.json { render json: { errors: delete_form.errors }, status: :ok }
    end
  end

  def companies_list
    redirect_to root_path unless current_user.account_manager?
  end

  def privacy_policy
    if current_user.try(:accepted_privacy_policy?)
      redirect_to root_path and return
    end
    if request.post?
      if params[:user].has_key?(:accepted_privacy_policy) && params[:user][:accepted_privacy_policy] == '1'
        current_user.update_column('accepted_privacy_policy', true)
        flash[:alert] = nil # to clear error if it was shown on previous step
        redirect_to root_path and return
      else
        flash[:alert] = t('users.errors.privacy_policy_not_accepted')
      end
    end
  end

  def test
    user = nil
    [:id, :email].each do |param_key|
      if params[param_key].present?
        user = current_company.users.find_by(param_key => params[param_key])
        break
      end
    end
    if user.present?
      render json: user, status: :ok
    else
      render json: { errors: ['User not found'] }, status: :not_found
    end
  end

  def recover
    recover_form = BulkUsersProcessingForm.new(current_user, params[:ids]).recover

    respond_to do |format|
      format.html { redirect_to users_path }
      format.json { render json: { errors: recover_form.errors }, status: :ok }
    end
  end

  protected

  # remove any params that could have security threats
  def clean_params
    # make sure admin can't change users of another company
    params[:company_id] = current_company.id if admin? or account_manager?
    if params[:user]
      params[:user][:password] = params[:password] if params.has_key?(:password)
      params[:user][:password_confirmation] = params[:password_confirmation] if params.has_key?(:password_confirmation)
    end
  end

  def parse_image_data(data)
    filename = "avatar-#{params[:id]}"
    ext = data['content_type'].split('/').last
    @temp_avatar = Tempfile.new([filename, ".#{ext}"])
    @temp_avatar.binmode
    @temp_avatar.write Base64.decode64(data['file_data']["data:#{data['content_type']};base64,".length .. -1]) # pass non-image data
    @temp_avatar.rewind

    ActionDispatch::Http::UploadedFile.new(
      tempfile: @temp_avatar,
      type: data['content_type'],
      filename: "#{filename}.#{ext}",
    )
  end

  def remove_temp_avatar
    if @temp_avatar
      @temp_avatar.close
      @temp_avatar.unlink
    end
  end

  private

  def users_relation
    policy_scope(User)
      .select(users_select_statement)
      .left_outer_joins(:devices)
      .group('`users`.`id`')
      .distinct
  end

  def users_select_statement
    '`users`.*, sum(case when `devices`.`virtual` is true THEN 0 ELSE 1 END) as devices_amount'
  end

  def permitted_search_keys
    [:name_or_first_name_cont, :email_cont, :company_name_cont, :locked_by_admin_true,
     :name_or_first_name_or_email_or_company_name_cont, :name_or_first_name_or_email_cont, :deleted_is,
     :login_cont]
  end
end

class CompaniesController < ApplicationController
  before_action :fetch_company_by_hashed_id, only: [ :activate ]

  skip_before_action :authenticate_user!, :check_privacy_policy_accepted, only: [ :activate ]
  around_action :use_user_specific_templates, only: [:new, :edit, :create, :update]

  # GET /companies
  # GET /companies.json
  def index
    authorize Company
    @companies = available_companies.includes(subscription: :subscription_plan)
  end

  def show
    company = Company.find(params[:id])
    authorize company
    render json: company
  end

  # DELETE /companies.html
  def destroy
    company = Company.unscoped.find(params[:id])
    authorize company
    if current_user.company.id == company.id
      flash[:alert] = t('companies.errors.deleting_current_company')
    else
      company.delay.destroy!
      flash[:alert] = t('companies.messages.deletion_started')
    end
    redirect_to companies_path
  end

  # GET /companies/new
  # GET /companies/new.json
  def new
    authorize Company
    @company_form = CompanyForm.new
    render action: :edit
  end

  # GET /companies/1/edit
  def edit
    @company_form = CompanyForm.new(params.permit(:id))
    authorize @company_form.company
  end

  # POST /companies
  # POST /companies.json
  def create
    authorize Company
    @company_form = CompanyForm.new(params_for_new_company)

    respond_to do |format|
      if @company_form.save
        notice = t('companies.company_was_successfully_created')
        format.json { render json: { notice: notice } }
        format.html { redirect_to redirect_path_after_update, notice: notice }
      else
        format.json { render json: { errors: @company_form.errors }, status: :unprocessable_entity }
        format.html { render action: :edit }
      end
    end
  end

  # PUT /companies/1
  # PUT /companies/1.json
  def update
    @company_form = CompanyForm.new(params_for_existing_company)
    authorize @company_form.company
    respond_to do |format|
      if @company_form.save
        notice = t('companies.company_was_successfully_updated')
        format.json { render json: { notice: notice } }
        format.html { redirect_to redirect_path_after_update, notice: notice }
      else
        format.json { render json: { errors: @company_form.errors }, status: :unprocessable_entity }
        format.html { render :edit }
      end
    end
  end

  def modules
    @company = Company.find(params[:id])
  end

  def activate
    CompanyActivationService.new(@company).activate
    flash[:success] = I18n.t('companies.activate.text')
    redirect_to new_user_session_path
  end

  private

  def fetch_company_by_hashed_id
    company_id = HASHIDS.decode(params[:company_hash]).first
    @company = TrialCompany.find(company_id)
  rescue Hashids::InputError
    redirect_to new_user_session_path, alert: 'Invalid activation URL'
  end

  def params_for_new_company
    params.permit(
      company: [
        *common_company_params, :account_manager_id,
        subscription_attributes: [
          :disk_space, :users_count, :traffic, :projects_limit, :booked_submissions_amount, :id, :next_renewal_at,
          :subscription_plan_id, available_modules: []
        ]
      ],
      admin: common_admin_params
    )
  end

  def params_for_existing_company
    params.permit(
      :id,
      company: [
        *common_company_params,
        subscription_attributes: [
          :disk_space, :users_count, :traffic, :projects_limit, :booked_submissions_amount, :id, :next_renewal_at,
          available_modules: []
        ],
        sms_settings_attributes: [:client_id, :password, :service_id],
        two_factor_authentication_settings_attributes: [:id, :expires_minute,
          two_factor_authentication_resources_attributes: [:id, :resource_name, :one_time_password_message, :enabled]]
      ],
      admin: common_admin_params
    )
  end

  def common_company_params
    [
      :name, :street, :city, :zip_code, :country, :engine, :language, :time_zone, :sender_email, :beta_mode,
      :auto_deletion_appointments, :days_to_store_data, :allowed_to_login_on_backend, :header_1_color,
      :header_2_color, :link_color, :primary_text_color, :secondary_text_color, :allow_color_selection,
      :add_module, :project_no_data_sync, :hide_projects_author, :account_manager_id, :custom_login_allowed
    ]
  end

  def common_admin_params
    [:name, :email, :password, :password_confirmation]
  end

  def redirect_path_after_update
    params[:redirect_to] ||
    redirection_path(id: @company_form.company.id, active_tab: params[:active_tab])
  end

  def use_user_specific_templates
    prefix = "companies/#{current_user.class.name.underscore}"
    prefix = 'companies/supervisor' if current_user.account_manager?

    lookup_context.prefixes.prepend prefix
    yield
    lookup_context.prefixes.delete prefix
  end
end

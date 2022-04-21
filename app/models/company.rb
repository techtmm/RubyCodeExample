# Company is a main object of application. Almost all other model are related to Company.
class Company < ApplicationRecord

  # Allowed engines
  ENGINES = [NDA]

  # scopes
  scope :active, -> { where(activated: true) }
  scope :to_delete, -> { where('activated = ? AND created_at <= ?', false, 30.days.ago) }
  scope :ordered, -> { order(:name) }

  attr_reader :deleted_submissions

  # validations
  validates :name, :time_zone, :language, presence: true
  validates :name, uniqueness: true
  validates :days_to_store_data, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 99 }
  validates :engine, inclusion: { in: ENGINES }, allow_nil: true
  validate :engine_not_changed, on: :update

  # NOTE: Currently we don't need to run user_group's callbacks - all the folders will be cleaned up by Company.
  has_many :user_groups, inverse_of: :company, dependent: :delete_all

  # relationships with users
  has_many :admins, inverse_of: :company
  has_many :users
  has_many :devices, -> { readonly }, through: :users
  has_many :mobile_app_backups, -> { readonly }, through: :users

  has_many :projects # no 'dependent: :destroy' here, because we must destroy them manually
  has_many :app_code_tags, dependent: :destroy
  # this needs to have 'has_many :scene3d_types' association
  has_many :scene3ds, through: :projects, source: :as_project, source_type: 'Scene3d'

  # relationships with fonts
  belongs_to :company_font, optional: true
  belongs_to :account_manager

  has_many :form_templates, dependent: :destroy

  # relationships with assets module
  has_many :assets, dependent: :destroy
  has_many :tags, dependent: :destroy

  # relationships with linked urls
  has_many :project_links, dependent: :delete_all

  # relationships with scene3d_types
  has_many :scene3d_types, through: :scene3ds

  has_and_belongs_to_many :mobile_apps, optional: true

  has_many :push_notifications, dependent: :destroy
  has_many :sms_messages, dependent: :delete_all
  has_many :company_banners, inverse_of: :company, dependent: :destroy
  has_many :media_drive_file_metas, class_name: 'NDA', as: :owner
  has_many :media_drive_admin_events, class_name: 'NDA', dependent: :destroy
  has_many :labels, dependent: :destroy
  has_many :locations, dependent: :destroy
  has_many :business_partners, dependent: :destroy

  has_one :imap_settings, class_name: 'CompanyImapSettings', inverse_of: :company, dependent: :delete
  has_one :smtp_settings, class_name: 'CompanySmtpSettings', inverse_of: :company, dependent: :delete
  has_one :sms_settings, class_name: 'CompanySmsSettings', inverse_of: :company, dependent: :delete
  has_one :media_drive_settings, class_name: 'NDA', inverse_of: :company, dependent: :delete
  has_one :company_image, inverse_of: :company, dependent: :destroy
  has_one :subscription, inverse_of: :company, required: true, dependent: :destroy
  has_one :slack_integration, dependent: :destroy
  has_one :two_factor_authentication_settings,
          class_name: 'NDA',
          dependent: :destroy,
          inverse_of: :company
  has_one :media_drive_storage_settings,
          class_name: 'NDA',
          dependent: :destroy,
          inverse_of: :company
  has_one :open_api_settings, class_name: 'NDA', inverse_of: :company, dependent: :delete
  has_one :disk_usage, class_name: 'NDA', inverse_of: :company, dependent: :delete

  has_many :two_factor_authentication_resources, through: :two_factor_authentication_settings
  has_many :roles, dependent: :destroy

  accepts_nested_attributes_for :user_groups, allow_destroy: true
  accepts_nested_attributes_for :admins, allow_destroy: true
  accepts_nested_attributes_for :imap_settings, update_only: true
  accepts_nested_attributes_for :smtp_settings, update_only: true
  accepts_nested_attributes_for :sms_settings, update_only: true
  accepts_nested_attributes_for :media_drive_settings, update_only: true
  accepts_nested_attributes_for :media_drive_storage_settings, update_only: true
  accepts_nested_attributes_for :subscription, update_only: true
  accepts_nested_attributes_for :two_factor_authentication_settings, allow_destroy: true
  accepts_nested_attributes_for :open_api_settings, allow_destroy: true

  normalize_blank_values :engine

  before_validation :adjust_colors

  after_initialize :set_default_values
  after_create :create_folder
  after_create :create_default_user_group

  before_save :set_default_font
  before_create :activate, unless: :manual_activation?

  before_destroy :cleanup_associations
  after_destroy :send_company_deleted_email
  after_destroy :cleanup_resources

  delegate :disk_space, :users_count, :traffic, :projects_limit, :booked_submissions_amount,
           :module_available?, :add_module=, to: :subscription

  # Default colors set for company
  DEFAULT_COLORS = {
    header_1_color: '2bb7d1', header_2_color: '2b2b2b', link_color: '2bb7d1', primary_text_color: '2b2b2b', secondary_text_color: '666666',
  }
  # Modules that are active by default on company creation
  DEFAULT_ACTIVE_MODULES = ['Forms', 'Export Options', 'Upload Field', 'DOCX Delivery', 'Push-Notification'].freeze
  # Maximum amount of banners a company can upload
  COMPANY_BANNERS_LIMIT = 2

  # Finds all the company users (without {Admin}s).
  # @return [Array] list of {User}s
  def users_only
    User.unscoped.where(company_id: id, type: User::USER_TYPE_NAME)
  end

  # Invalidate cache for all the Forms.
  def touch_forms
    projects.forms.each(&:touch)
  end

  # If no font then use the first font as default.
  def set_default_font
    self.company_font = CompanyFont.first if self.company_font.blank?
  end

  # Create asset folder for company.
  def create_folder
    asset_folder = uploads_folder
    Dir.mkdir(asset_folder) unless File.directory?(asset_folder)
    Dir.mkdir(asset_folder + "/thumbs") unless File.directory?(asset_folder + "/thumbs")
    true
  end

  # Folder where all company related resources are stored.
  # @return [String] folder path
  def uploads_folder
    "#{ASS_PATH}/#{id}"
  end

  # Returns the percentage usage of the users in the company.
  # @return [Float] how many users in company in percents
  def users_usage
    return 0 if users_count.zero?

    users.count * 100 / users_count
  end

  # Returns company's disk space.
  # @return [Integer] disk space in bytes for company (in DB disk space is in Mb)
  def reserved_disk_space(in_bytes = false)
    return 0 if disk_space.zero?

    in_bytes ? disk_space * 1024 * 1024 : disk_space
  end

  # Calculates space used by assets.
  # @return [Integer] disk space used by assets in bytes
  def used_space
    assets.map(&:size).reject { |i| i.nil? }.inject(0, :+)
  end

  # Returns comma separated list of modules for this company.
  # @return [String] list of modules (presentation types) that used in company
  def scope
    if subscription.available_modules.empty?
      I18n.t('general.messages.none')
    else
      subscription.available_modules.map(&:name).join(', ')
    end
  end

  # Returns the first admin of the company admins.
  # @return [Admin]
  def admin
    self.admins.first
  end

  # Marks a company as deleted.
  def mark_deleted
    self.deleted = true
  end

  # Marks a company as deleted and saves record.
  def mark_deleted!
    self.deleted = true
    self.save
  end

  # Checks if current company was created by API (means registered from mobile device).
  # @return [Boolean]
  def created_by_api?
    self.created_by == 'API'
  end

  def created_by_form?
    self.created_by == 'Form'
  end

  def manual_activation?
    created_by == 'API' || created_by == 'Form'
  end

  # Combines errors list in a better way to have better overview on mobile device.
  # @return [Hash] list of errors
  def modified_errors
    modified_errors = {}
    errors.each do |attribute, error|
      new_attr_name = attribute
      if new_attr_name == :name
        new_attr_name = :company_name
      elsif new_attr_name.to_s.start_with?('admin')
        new_attr_name = new_attr_name.to_s.split('.').last.to_sym
      end

      if modified_errors[new_attr_name].nil?
        modified_errors[new_attr_name] = [error]
      else
        modified_errors[new_attr_name] << error
      end
    end
    modified_errors
  end

  # Marks company as activated.
  def activate
    self.activated = true
  end

  # Converts company's ID to hashed string.
  # @return [String]
  def to_hashids
    HASHIDS.encode(id)
  end

  # Checks if {Project}'s limit is reached.
  # @return [Boolean]
  def projects_limit_reached?
    projects.count >= projects_limit
  end

  # Defines company's locale based on language settings.
  # @return [Symbol] :de or :en
  def locale
    self.language == 'German' ? :de : :en
  end

  # Prepares list of company colors.
  # @return [Hash]
  def colors
    DEFAULT_COLORS.keys.map{ |color| [color, self.send(color)] }.to_h
  end

  def banners_limit_reached?
    company_banners.count >= COMPANY_BANNERS_LIMIT
  end

  def build_media_drive_settings_with_defaults
    build_media_drive_settings(NDA.defaults)
  end

  def build_media_drive_storage_settings_with_defaults
    build_media_drive_storage_settings(NDA::DEFAULTS)
  end

  def first_or_build_two_factor_authentication_settings_with_defaults
    (two_factor_authentication_settings ||
      build_two_factor_authentication_settings(expires_minute: 30)).tap do |settings|
        settings.two_factor_authentication_resources_with_defaults
      end
  end

  protected

    # Callback that creates default {UserGroup}s after new company is created.
    # @!visibility protected
    def create_default_user_group
      self.user_groups.create(name: 'Default')
    end

    # Callback that deletes {Project}s, {User}s.
    # @!visibility protected
    def cleanup_associations
      @deleted_submissions = []
      projects.with_deleted.each do |project|
        if project.display_submissions?
          @deleted_submissions << {
            project_name: project.name,
            submissions_amount: Tracking.with_deleted.where(project_id: project.as_project_id).count,
          }
        end
        # need to call 'destroy' for every specific project, because 'acts_as_relation' calls 'delete' instead
        project.specific.try(:destroy)
        project.destroy_fully!
      end
      User.unscoped.where(company_id: self.id).each do |user|
        user.force_destroy = true
        user.destroy!
      end
      Traffic.where(company_id: self.id).delete_all # no need to create association for Traffic because we never use it
      MediaDriveResourcesDestroyingService.new(self).execute
    end

    # Callback that deletes company's folder after the company has been deleted.
    # @!visibility protected
    def cleanup_resources
      if File.directory?(uploads_folder)
        logger.info "[main] deleting #{uploads_folder}"
        FileUtils.rm_r uploads_folder
      end
    end

    # Callback that sends email after a company has been deleted.
    # @!visibility protected
    def send_company_deleted_email
      SummaryMailer.company_deleted(self).deliver_now
    end

    # Callback that removes '#' sign from colors before company validation.
    # @!visibility protected
    def adjust_colors
      DEFAULT_COLORS.keys.each do |color|
        self[color] = self[color][1..-1] if self[color].size == 7 && self[color][0] == '#'
      end
    end

    def set_default_values
      self.language ||= 'German'
      self.time_zone ||= 'Berlin'
    end

    # Validation that prevents engine changing for companies
    # @!visibility protected
    def engine_not_changed
      errors.add :base, 'Engine cannot be changed' if will_save_change_to_engine?
    end
end

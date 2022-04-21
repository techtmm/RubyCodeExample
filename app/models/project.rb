# frozen_string_literal: true

# Base class for projects that contains general project attributes.
# @see NDA project type
# @see NDA project type
# @see NDA Presenter project type
class Project < ApplicationRecord
  PROJECT_TYPES = %w(Lead EBook Scene3d Link)
  acts_as_paranoid
  actable as: :as_project

  enum position: %i(default top bottom)

  belongs_to :company, optional: true
  belongs_to :creator, polymorphic: true, optional: true
  belongs_to :last_editor, polymorphic: true, optional: true
  belongs_to :company_font, optional: true
  has_many :codes, class_name: 'AppCode', dependent: :destroy
  has_many :project_links, dependent: :nullify
  has_many :user_events, dependent: :delete_all
  has_many :traffics
  has_and_belongs_to_many :labels, join_table: 'projects_labels' # rubocop:disable Rails/HasAndBelongsToMany

  # So when NDA project gets updated we have new revision for it and store its pages and presentation objects
  has_paper_trail :on => [ :update ],
    :ignore => [ :last_opened_at ],
    :if => Proc.new { |project| project.lead? },
    :meta => {
      :pages => -> (project) { project.specific.serialized_pages },
      :presentation_objects => -> (project) { project.specific.serialized_presentation_objects },
      :downloads_count => -> (project) { project.specific.downloads_count }
    }

  delegate :module_available?, :allow_color_selection?, to: :company

  validates :name, :company_id, :creator_id, presence: true
  validates :as_project_type, inclusion: { in: PROJECT_TYPES }
  validates :company, company_module: { name: :as_project_type, message: :project_type_unavailable },
            if: ->(project) { project.company.subscription.active? }
  validate :company_subscription_expired?
  validate :projects_limit_reached?, on: [:create, :move]

  # returns projects that are published (which have app codes)
  scope :published, -> { joins(:codes).select('DISTINCT (projects.id)') }

  before_validation :set_defaults
  before_create :set_project_font
  after_save :cascade_deletion, if: -> (project) { project.reload.deleted_at.present? }
  after_save :mark_app_codes_deletable, if: -> (project) { project.reload.deleted_at.present? }

  scope :forms, -> { where(as_project_type: 'NDA') }
  scope :push_notification_recipients, -> { where(as_project_type: %w(NDA)) }
  scope :filter, -> (params) { ransack(name_cont: params[:q]).result }

  # Creates project specific instance based on as_project_type attribute.
  # @param [Hash] attributes project's attributes
  # @param [Hash] options additional options (for compatibility with ActiveRecord::Base#new)
  # @return [NDA] project specific instance or Project instance if project specific class not found
  def self.init_as(attributes)
    case attributes[:as_project_type]
    when 'NDA'
      NDA.new(attributes)
    when 'NDA'
      NDA.new(attributes)
    when 'NDA'
      NDA.new(attributes)
    when 'NDA'
      NDA.new(attributes)
    else
      NDA.new(attributes)
    end
  end

  def self.all_attribute_names
    ([self] + PROJECT_TYPES.map(&:safe_constantize)).compact.map(&:attribute_names).inject(:|)
  end

  # Set the font of the project to the font of the company.
  def set_project_font
    self.company_font = self.company.company_font
  end

  # Creates special preview app code after getting project.
  # It doesn't create app code if such one already exists.
  # Method also considers that app code name must be unique.
  # @return [AppCode] preview app_code
  def create_preview_code
    return self.codes.preview if preview_code_exists?

    code = AppCode.new(:name => "Preview", :online => true, :public => true)
    code.project = self
    code.generate_code
    until code.name_is_unique
      code.name = "#{code.name}1"
    end
    code.save
    code
  end

  # Is special preview app code exists?
  # @return [Boolean]
  def preview_code_exists?
    self.codes.preview.present?
  end

  # Is project published?
  # @return [Boolean]
  def published?
    self.codes.count > 0
  end

  # Return the font of the project or the font of the company.
  # @return [CompanyFont]
  def font
    self.company_font || self.company.company_font
  end

  # Returns font class of the project or company.
  # @return [String]
  def font_class
    self.font.try(:font_class)
  end

  # Returns presentation type for project.
  # @return [String, NilClass] presentation type or nil if not found
  def presentation_type
    Utils::ProjectTypesNamingConverter.project_type_to_module_name(as_project_type)
  end

  # Returns project creator name.
  # @return [String, NilClass] creator name or nil if not found
  def project_creator
    return "Account Manager" if creator.is_a?(AccountManager)

    creator.try(:name)
  end

  # Returns project last editor name.
  # @return [String, NilClass] last editor name or nil if not found
  def last_project_editor
    last_editor.try(:name)
  end

  # Generates preview URL link based on special preview {AppCode}.
  # @return [String] URL link or empty string if no preview AppCode
  def preview_link
    Rails.application.routes.url_helpers.project_preview_path(self.id)
  end

  # Generates preview URL link based on special preview {AppCode}.
  # @return [String] URL link or empty string if no preview AppCode
  def desktop_preview_link
    Rails.application.routes.url_helpers.project_view_path(self.id)
  end

  # Returns company font name.
  # @return [String]
  def company_font_name
    self.font.try(:name)
  end

  # Display submissions list on project details page? Only {NDA} projects use submissions.
  # @return [Boolean]
  def display_submissions?
    as_project_type == 'NDA' && !company.module_available?('NDA')
  end

  # Display user events list on project details page? {NDA} projects don't use user events.
  # @return [Boolean]
  def display_user_events?
    self.as_project_type != 'NDA' && self.as_project_type != 'NDA' && self.tracking_available?
  end

  # Method updates 'updated_at' attribute explicitly to trigger saving previous version
  # Use this only when project structure changes, otherwise there's no need to create new version, because it's structure matches current project structure
  def touch_hard
    update_attribute('updated_at', Time.now)
  end

  # Generates hash that will be used in search result.
  # @return [Hash]
  def to_search_result
    company = Company.unscoped.find_by(id: company_id)
    {
      id: id,
      name: deleted? ? "#{name} (deleted)" : name,
      app_codes: AppCode.with_deleted.where(project_id: id).map{ |app_code| app_code.deleted? ? "#{app_code.code} (deleted)" : app_code.code },
      company: {
        id: company.try(:id),
        name: company.try(:deleted?) ? "#{company.try(:name)} (deleted)" : company.try(:name),
      },
    }
  end

  # Validates if corresponding project type is available for user.
  # @return [Boolean]
  def available?
    module_available?(as_project_type)
  end

  # Checks if {CompanyModule} is available.
  # @param [String] name
  # @return [Boolean]
  def addon_available?(name)
    module_available?(name)
  end

  # Generates methods like `sms_available?` etc
  CompanyModule.all_addons.each do |addon|
    define_method("#{addon.db_name}_available?") do
      addon_available?(addon.db_name)
    end
  end

  # acts_as_paranoid doesn't trigger callback on deletion, so need to do that manually
  def delete
    with_transaction_returning_status do
      run_callbacks :save do
        super
      end
    end
  end

  # `acts_as_relation` gem that we previously used allowed to call method of specific projects,
  # We want to keep this functionality.
  def method_missing(method, *arg, &block)
    if specific && specific.respond_to?(method)
      specific.send(method, *arg, &block)
    else
      super
    end
  end

  def lead?
    specific.is_a?(NDA)
  end

  protected

    # Validates if the project limit is reached for current {Company}.
    # @!visibility protected
    def projects_limit_reached?
      errors.add(:base, I18n.t('projects.errors.projects_limit_reached', count: company.projects.count)) if company.projects_limit_reached?
    end

    def company_subscription_expired?
      return if company.subscription.active?

      errors.add(:base, :company_subscription_expired)
    end

    # According to last changes we also need to mark app_codes as deleted. For now we don't care about other associations.
    def cascade_deletion
      codes.each { |code| code.delete }
    end

    def mark_app_codes_deletable
      codes.with_deleted.update_all(deletable: true)
    end

    def set_defaults
      self.no_data_sync ||= company.project_no_data_sync
      true
    end
end

# Handles push notifications, created by {User}.
class PushNotification < ApplicationRecord

  # Allowed recipients type
  RECIPIENTS_TYPES = ['User Group', 'Project', 'Push-Only', 'User']
  # Allowed notification statuses
  STATUSES = %w(Planned Delivered Failed)
  # User can modify push notification within this time frame
  MODIFICATION_TIME_FRAME = 15.minutes
  PLANNED_STATUS = 'Planned'

  belongs_to :company, optional: true
  belongs_to :delayed_job, -> { order(id: :desc) }, class_name: '::Delayed::Job', optional: true

  validates :company_id, numericality: true, allow_nil: false
  validates :recipients_type, inclusion: { in: RECIPIENTS_TYPES }
  validates :status, inclusion: { in: STATUSES }
  validates :created_by, numericality: true, allow_nil: true
  validates :subject, :text, presence: true
  validates :text, length: { maximum: 500 }
  validate :must_be_published_in_future

  before_validation :set_default_values, on: :create
  before_validation :modification_allowed?, on: :update
  before_validation :collect_recipients_info
  before_destroy :destroy_allowed?

  after_save :set_delayed_job, if: :saved_change_to_publish_at?
  after_destroy :delete_delayed_job

  serialize :recipients_info, Array
  serialize :additional_data, Hash

  # Converts ActionController::Parameters to Hash to store less data in DB.
  # @param [Array] value
  def recipients_info=(value)
    self[:recipients_info] = value.is_a?(Array) ? value.map { |val| val.respond_to?(:to_h) ? val.symbolize_keys.to_h : { id: val, is_read: false } } : nil
  end

  def mark_read_by(user_ids)
    user_ids = [user_ids] unless user_ids.is_a?(Array)
    user_ids.compact!
    self[:recipients_info] = self[:recipients_info].map { |user| user_ids.include?(user[:id]) ? user.merge({ is_read: true }) : user }
    save(validate: false)
  end

  protected

    # Validation that checks push notification is published in future.
    # @!visibility protected
    def must_be_published_in_future
      errors.add :publish_at, I18n.t('push_notifications.errors.must_be_future') if self[:publish_at] <= Time.current
    end

    # Callback that sets some default values before creating new push notification.
    # @!visibility protected
    def set_default_values
      self[:status] = PLANNED_STATUS if self[:status].nil?
      self[:publish_at] = 5.seconds.since if self[:publish_at].nil?
    end

    # Callback that checks if notification can be modified before updating push notification.
    # @!visibility protected
    # @return [Boolean]
    def modification_allowed?
      if status != PLANNED_STATUS || publish_at_was < MODIFICATION_TIME_FRAME.since
        errors.add :base, I18n.t('push_notifications.errors.too_late_for_modification')
        throw(:abort)
      end
    end

    def destroy_allowed?
      status != PLANNED_STATUS
    end

    # Callback that calculates amounts of users and devices based on recipients data before saving push notification.
    # @!visibility protected
    def collect_recipients_info
      if self.recipients_type == 'User Group' && self[:recipients_info].is_a?(Array)
        users_amount = 0
        devices_amount = 0
        self[:recipients_info].each do |user_group_data|
          user_group = UserGroup.find(user_group_data[:id]) rescue next
          users_amount += user_group.users.count
          devices_amount += user_group.devices.count
        end
        self[:users_amount] = users_amount
        self[:devices_amount] = devices_amount
      elsif self.recipients_type == 'User' && self[:recipients_info].is_a?(Array)
        self[:users_amount] = self[:recipients_info].size
        self[:devices_amount] = self.company.devices.real.where(user_id: self[:recipients_info]).count
      else
        self[:users_amount] = self.company.users.count
        self[:devices_amount] = self.company.devices.count
      end
    end

    # Callback that configures delayed job and connects it to the record after saving push notification.
    # @!visibility protected
    def set_delayed_job
      if self.delayed_job_id.nil?
        job = PushNotifications::SendToFireBaseJob.new(id)
        job_id = Delayed::Job.enqueue(job, run_at: self.publish_at).id
        self.update_column('delayed_job_id', job_id)
      else
        if delayed_job.present?
          raise 'Delayed Job has been already started somehow... Notification will not be sent.' if job_failed_or_running?
          delayed_job.update_attribute('run_at', self.publish_at)
        else
          raise 'Associated Delayed Job not found. Notification will not be sent.'
        end
      end
    end

    # Callback that deletes associated delayed job after deleting push notification.
    # @!visibility protected
    def delete_delayed_job
      if delayed_job
        if job_failed_or_running?
          Rails.logger.warn 'Delayed job is running now and will be deleted automatically'
        else
          delayed_job.destroy
        end
      end
    end

    def job_failed_or_running?
      delayed_job.attempts > 0 || delayed_job.locked_at.present?
    end
end

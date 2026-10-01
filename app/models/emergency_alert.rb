class EmergencyAlert < Message
  before_create :update_body
  after_create_commit :broadcast_alert

  # Not yet answered with "Got it!": shown again on every page until someone does.
  scope :open_for, ->(provider_id) { where(provider_id: provider_id, read_at: nil).where("messages.created_at > ?", 12.hours.ago) }

  def message
    "Driver #{sender.display_name}#{run ? " (#{run.name})" : ''} has an emergency. Please respond immediately!"
  end

  private

  def update_body
    self.body = self.message
  end

  def broadcast_alert
    EmergencyAlertWorker.perform_async(self.id)
  end
end
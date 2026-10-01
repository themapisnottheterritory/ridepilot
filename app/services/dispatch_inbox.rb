# The dispatch desk's shared inbox of driver messages (2026-10-01). A message
# from a driver is unhandled until any dispatcher opens that driver's chat or
# answers it; then it's handled for everyone ("answered by Kristie 9:14"), so
# two people don't both call the driver. Live updates go to every dispatcher
# of the agency on "dispatch_<provider_id>" (DispatchChannel).
class DispatchInbox
  RECENT = 15

  def self.stream(provider_id) = "dispatch_#{provider_id}"

  def initialize(provider_id)
    @provider_id = provider_id
  end

  def unhandled
    RoutineMessage.for_today.from_drivers.unhandled.where(provider_id: @provider_id)
  end

  def unhandled_count
    unhandled.count
  end

  # Newest first: everything unhandled, then the latest handled ones.
  def recent
    base = RoutineMessage.for_today.from_drivers.where(provider_id: @provider_id).includes(:handled_by, run: [], driver: :user)
    (base.unhandled.order(created_at: :desc).to_a + base.where.not(handled_at: nil).order(created_at: :desc).limit(RECENT).to_a)
  end

  # A dispatcher opened or answered this driver's chat.
  def handle!(driver_id, user)
    ids = unhandled.where(driver_id: driver_id).pluck(:id)
    return [] if ids.empty?
    RoutineMessage.where(id: ids).update_all(handled_at: Time.current, handled_by_id: user.id)
    ActionCable.server.broadcast(self.class.stream(@provider_id), {
      kind: "handled", driver_id: driver_id.to_i, ids: ids, by: user.display_name, at: Time.current.iso8601,
      unhandled: unhandled_count
    })
    ids
  end

  def self.payload(message, unhandled)
    { kind: "chat", id: message.id, driver_id: message.driver_id, driver_name: message.driver.try(:user).try(:display_name) || message.driver.try(:name),
      run_id: message.run_id, run_name: message.run.try(:name), body: message.body, at: message.created_at.iso8601, unhandled: unhandled }
  end
end

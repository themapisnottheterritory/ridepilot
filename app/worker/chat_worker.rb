class ChatWorker
  include Sidekiq::Worker
  sidekiq_options queue: 'critical'

  def perform(message_id)
    Rails.logger.info "ChatWorker#perform"
    message = RoutineMessage.find_by_id message_id
    return unless message

    chat = {
      sender_id: message.sender_id,
      sender_name: message.sender.try(:display_name),
      body: message.body,
      driver_id: message.driver_id,
      provider_id: message.provider_id,
      run_id: message.run_id,
      trip_id: message.trip_id,
      itinerary_id: message.pickup_itinerary_id,
      created_at: message.created_at,
      id: message.id
    }
    # The CAD chat popup reads the fields at the top level; the Demand Response
    # tablet's chat page reads them under "message" (until 2026-10-01 it got
    # none, so a driver never saw a dispatcher's message arrive live).
    ActionCable.server.broadcast "chat_channel_#{message.provider_id}_#{message.driver_id}",
                                 chat.merge(action: 'CreateMessage', message: chat)

    if message.run_id
      ActionCable.server.broadcast "chat_alert_channel_#{message.run_id}", {
        message_id: message.id,
        sender_id: message.sender_id,
        action: 'NewChat'
      }
    end

    # The dispatch desk's inbox, on every RidePilot page (DispatchInbox)
    if message.from_driver?
      ActionCable.server.broadcast DispatchInbox.stream(message.provider_id),
                                   DispatchInbox.payload(message, DispatchInbox.new(message.provider_id).unhandled_count)
    end
  end
end

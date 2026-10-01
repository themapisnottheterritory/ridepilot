class ChatChannel < ApplicationCable::Channel
  def subscribed
    return reject unless may_follow_driver?(params[:provider_id], params[:driver_id])
    stream_from "chat_channel_#{params[:provider_id]}_#{params[:driver_id]}"
  end

  def unsubscribed
    # Any cleanup needed when channel is unsubscribed
  end

  # Only into the conversation this subscription is for, and with a run (a
  # message without one is never saved).
  def create(data)
    driver = Driver.find_by(id: params[:driver_id], provider_id: params[:provider_id])
    run = Message.run_for(driver, data["run_id"])
    return unless driver && run && data["body"].present?
    RoutineMessage.create(provider_id: driver.provider_id, sender: current_user, body: data["body"], driver: driver, run: run)
  end
end

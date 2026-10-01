class AlertChannel < ApplicationCable::Channel
  def subscribed
    return reject unless may_follow_provider?(params[:provider_id])
    stream_from "alert_channel_#{params[:provider_id]}"
  end

  def unsubscribed
    # Any cleanup needed when channel is unsubscribed
  end

  # from a driver's own connection only, with their driver and run, so the
  # "received" answer can reach their tablet
  def trigger
    return unless own_driver && own_driver.provider_id == params[:provider_id].to_i
    EmergencyAlert.create(provider_id: own_driver.provider_id, sender: current_user, driver: own_driver, run: Message.run_for(own_driver))
  end

  def dismiss(data)
    alert = EmergencyAlert.find_by(id: data['id'])
    if alert
      reader = current_user   # whoever pressed "Got it!", not who the browser says
      if reader && staff_of?(alert.provider_id) && alert.read_at.nil?
        alert.reader = reader
        alert.read_at = DateTime.now
        alert.save(validate: false)

        EmergencyAlertDismissWorker.perform_async(alert.id)
      end
    end
  end
end

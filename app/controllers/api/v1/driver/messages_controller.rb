class Api::V1::Driver::MessagesController < Api::V1::Driver::BaseController
  def send_emergency_alert
    if @driver
      # Message#run is a required belongs_to (Rails 7 default), so an alert
      # created without one silently failed validation and no alert ever
      # reached dispatch. Take the run from the tablet if it sent one, else
      # the driver's active (started, un-ended) run, else any run today.
      run = Run.find_by(id: params[:run_id], driver: @driver) ||
            Run.where(driver: @driver, date: Date.today)
               .where.not(start_odometer: nil).where(end_odometer: nil).first ||
            Run.where(driver: @driver, date: Date.today).first
      alert = EmergencyAlert.create(provider_id: @driver.provider_id, driver: @driver, sender: @driver.user, run: run)
      Rails.logger.warn "send_emergency_alert: NOT saved for driver #{@driver.id}: #{alert.errors.full_messages.join(', ')}" unless alert.persisted?
    end

    render success_response({success: true})
  end

  def chats
    opts = {}
    if @driver
      @messages = RoutineMessage.for_today.where(provider_id: @driver.provider_id, driver: @driver)
    end

    render success_response(@messages, opts)
  end

  def driver_message_templates
    if @driver
      @templates = DriverMessageTemplate.by_provider(@driver.provider)
    end

    render success_response(@templates, {})
  end

  def send_message
    if @driver
      RoutineMessage.create(provider_id: @driver.provider_id, driver: @driver, sender: @driver.user, run_id: params[:run_id], body: params[:body])
    end

    render success_response({success: true})
  end

  def read_message
    if @driver
      ChatReadReceipt.create(run_id: params[:run_id], message_id: params[:message_id], read_by_id: params[:read_by_id])
    end

    render success_response({success: true})
  end
end

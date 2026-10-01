module Cad
  class ChatController < ::ApplicationController
    layout "cad/chat"

    # The chat popup for one run's driver. Opening it counts as the desk
    # having seen that driver's messages (DispatchInbox#handle!).
    def index
      @run = visible_runs.find_by(id: params[:run_id])
      @driver = @run.try(:driver)
      unless @run && @driver
        return render plain: "This run has no driver assigned, so there's no one to chat with yet.", layout: false
      end
      @messages = RoutineMessage.for_today.where(driver_id: @driver.id).order(created_at: :asc)
      DispatchInbox.new(@run.provider_id).handle!(@driver.id, current_user)
    end

    def create
      @driver = Driver.where(provider_id: visible_provider_ids).find_by(id: params[:driver_id])
      @run = Message.run_for(@driver, params[:run_id])
      if @driver && @run && params[:message].present?
        @message = RoutineMessage.create(provider_id: @driver.provider_id, run: @run, driver: @driver, sender: current_user, body: params[:message])
        DispatchInbox.new(@driver.provider_id).handle!(@driver.id, current_user)   # answering is handling
      end
    end

    def show
      @message = RoutineMessage.where(provider_id: visible_provider_ids).find_by(id: params[:id])
      head :no_content unless @message
    end

    # The popup has focus and shows the driver's latest message.
    def read
      message = RoutineMessage.where(provider_id: visible_provider_ids).find_by(id: params[:message_id])
      if message
        ChatReadReceipt.create(message_id: message.id, read_by_id: current_user.id, run_id: message.run_id)
        DispatchInbox.new(message.provider_id).handle!(message.driver_id, current_user)
      end
      render json: {}
    end

    private

    def visible_provider_ids
      current_user.super_admin? ? Provider.pluck(:id) : current_user.roles.pluck(:provider_id)
    end

    def visible_runs
      Run.where(provider_id: visible_provider_ids)
    end
  end
end

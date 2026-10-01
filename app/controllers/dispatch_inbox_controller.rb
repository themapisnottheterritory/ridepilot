# The header's driver-messages list (DispatchInbox), loaded when it's opened.
class DispatchInboxController < ApplicationController
  def index
    authorize! :read, Run
    @messages = DispatchInbox.new(current_provider_id).recent
    render partial: "dispatch_inbox/list", layout: false
  end
end

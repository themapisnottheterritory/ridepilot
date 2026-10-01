# The dispatch desk's live feed on every RidePilot page: driver messages for
# the inbox and their "handled" updates (DispatchInbox). Office staff of the
# agency only; a driver's tablet can't listen.
class DispatchChannel < ApplicationCable::Channel
  def subscribed
    return reject unless staff_of?(params[:provider_id])
    stream_from DispatchInbox.stream(params[:provider_id].to_i)
  end
end

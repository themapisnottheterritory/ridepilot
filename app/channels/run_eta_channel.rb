class RunEtaChannel < ApplicationCable::Channel
  def subscribed
    stream_from "run_eta_#{params[:run_id]}"
  end
end

class ManifestChannel < ApplicationCable::Channel
  def subscribed
    return reject unless may_follow_run?(params[:run_id])
    stream_from "manifest_channel_#{params[:run_id]}"
  end

  def unsubscribed
    # Any cleanup needed when channel is unsubscribed
  end
end

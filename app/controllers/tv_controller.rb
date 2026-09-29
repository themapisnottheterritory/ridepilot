# The dispatch TV: a full-screen live board for a TV in the office (TvBoard).
# Opened with /tv?k=<key> so the TV needs no sign-in, like the call center
# wall on the PBX. The key lives in config/tv_wall_key (not in git), or
# TV_WALL_KEY. ?p=<provider id> picks the agency (default GCRPC).
class TvController < ApplicationController
  skip_before_action :authenticate_user!
  before_action :require_key
  layout false

  def show
    @provider = provider
  end

  def data
    render json: TvBoard.new(provider)
  end

  private

  def require_key
    key = ENV["TV_WALL_KEY"].presence || (File.read(Rails.root.join("config", "tv_wall_key")).strip rescue nil)
    return if key.present? && ActiveSupport::SecurityUtils.secure_compare(key, params[:k].to_s)
    render plain: "This board needs its link. Ask GCRPC I.T. for the TV address.", status: :forbidden
  end

  def provider
    Provider.find_by(id: params[:p]) || Provider.find(1)
  end
end

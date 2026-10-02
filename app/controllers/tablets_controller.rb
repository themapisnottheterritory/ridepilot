# Vehicles > Tablets (Philz 2026-10-02): every driver tablet as its Demand
# Response app reports it (Tablet, TabletPing) for GCRPC I.T.: who is behind
# on an update, still has the old apps, has WireGuard set up, battery,
# storage, use. Tablets are GCRPC's, shared by every agency, so this is for
# GCRPC admins and system admins. Ask/summary: TabletAssistant (local model).
class TabletsController < ApplicationController
  before_action :require_it_admin
  before_action :load_tablet, only: [:show, :update, :summary, :destroy, :ask_update]

  def index
    @tablets = Tablet.by_number.to_a
    @published = Tablet.published
    @tablets.select! { |t| t.issues.any? } if params[:attention].present?
  end

  def show
    @pings = @tablet.pings.where("at >= ?", 24.hours.ago).order(:at).to_a
  end

  def update
    @tablet.update!(notes: params.require(:tablet)[:notes].to_s.first(4000))
    redirect_to tablet_path(@tablet), notice: "Notes saved."
  end

  # The same device reinstalled under a new Android ID leaves an old row behind.
  def destroy
    @tablet.destroy!
    redirect_to tablets_path, notice: "#{@tablet.label} (#{@tablet.android_id.first(6)}) removed from the list."
  end

  # "Ask to update": the app puts a full-width Update bar up at its next report (Tablet#update_wanted?).
  def ask_update
    @tablet.ask_to_update!(current_user.username)
    redirect_back fallback_location: tablet_path(@tablet), notice: "Asked #{@tablet.label} to update. It shows the driver an Update bar at its next report (within 10 minutes of the app being open)."
  end

  def ask_update_all
    behind = Tablet.all.select(&:behind?)
    behind.each { |t| t.ask_to_update!(current_user.username) }
    redirect_to tablets_path, notice: behind.any? ? "Asked #{behind.size} tablet#{'s' if behind.size > 1} to update: #{behind.map(&:label).join(', ')}." : "Every tablet that reports is on the current release."
  end

  def summary
    render json: { text: TabletAssistant.summary(@tablet) }
  end

  def ask
    render json: { text: TabletAssistant.fleet(params[:question]) }
  end

  private

  def load_tablet
    @tablet = Tablet.find(params[:id])
  end

  def require_it_admin
    ok = current_user && (current_user.super_admin? || current_user.roles.where(provider_id: 1).where("level >= ?", Role::ADMIN_LEVEL).exists?)
    redirect_to root_path, alert: "The Tablets page is for GCRPC I.T." unless ok
  end
end

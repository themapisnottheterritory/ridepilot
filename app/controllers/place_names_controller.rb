# Saved places -> "Name busy places": the busiest trip destinations that have
# no name, for someone who knows them to name in a click (PlaceNaming).
# Admins and editors, the people who may add saved places.
class PlaceNamesController < ApplicationController
  before_action :allowed

  def index
    @places = PlaceNaming.unnamed_destinations(current_provider)
    @groups = AddressGroup.where.not(name: AddressGroup::UNKNOWN_TYPE).order(:id).pluck(:name, :id)
    @named  = flash[:named]
  end

  def create
    ids = params[:address_ids].to_s.split(",").map(&:to_i)
    result = PlaceNaming.name_place!(provider: current_provider, user: current_user, address_ids: ids,
                                     name: params[:name], address_group_id: params[:address_group_id])
    flash[:named] = "Named **#{result[:saved_place].name}** (#{result[:saved_place].address}): a saved place, and #{result[:renamed]} trip address#{'es' if result[:renamed] != 1} now show the name."
    redirect_to place_names_path
  rescue ArgumentError, ActiveRecord::RecordInvalid => e
    flash[:alert] = "Not saved: #{e.message}"
    redirect_to place_names_path
  end

  def skip
    PlaceNaming.skip!(current_provider, params[:key].to_s)
    head :no_content
  end

  # Businesses Azure Maps lists within a few metres: names to choose from, never saved by itself
  def suggest
    names = PlaceSearch.nearby(lat: params[:lat].to_f, lon: params[:lon].to_f)
    render json: names
  end

  private

  def allowed
    raise CanCan::AccessDenied unless can?(:new, ProviderCommonAddress)
  end
end

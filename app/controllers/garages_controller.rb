# Vehicles > Garages: the yards this agency's buses live at (named
# GarageAddress records, 2026-10-01). Fleet adds one by name and address;
# the address has to come from the search list, so it's on the map and in the
# service area. A garage still used by a bus or an upcoming run can't be
# retired.
class GaragesController < ApplicationController
  before_action :load_garage, only: [:edit, :update, :retire]

  def index
    authorize! :read, Vehicle
    @garages = GarageAddress.named.where(provider_id: current_provider_id).order(Arel.sql("coalesce(addresses.inactive, false), lower(addresses.name)"))
    @counts = Vehicle.where(active: true, garage_address_id: @garages.map(&:id)).group(:garage_address_id).count
  end

  def new
    authorize! :edit, Vehicle
    @garage = GarageAddress.new(provider_id: current_provider_id, state: "TX")
  end

  def create
    authorize! :edit, Vehicle
    @garage = GarageAddress.new(garage_params.merge(provider_id: current_provider_id))
    @garage.the_geom = Address.compute_geom(params[:lat], params[:lon])
    return render(:new) if missing_name? || !@garage.save
    redirect_to garages_path, notice: "Garage “#{@garage.name}” added."
  end

  def edit
    authorize! :edit, Vehicle
  end

  def update
    authorize! :edit, Vehicle
    @garage.assign_attributes(garage_params)
    @garage.the_geom = Address.compute_geom(params[:lat], params[:lon]) if params[:lat].present? || params[:lon].present?
    return render(:edit) if missing_name? || !@garage.save
    redirect_to garages_path, notice: "Garage “#{@garage.name}” saved. Every bus and run that uses it now uses the new details."
  end

  def retire
    authorize! :edit, Vehicle
    if @garage.retire!
      redirect_to garages_path, notice: "“#{@garage.name}” retired."
    else
      redirect_to garages_path, alert: "“#{@garage.name}” is still used by a bus or an upcoming run: move them first."
    end
  end

  private

  def load_garage
    @garage = GarageAddress.named.where(provider_id: current_provider_id).find(params[:id])
  end

  def missing_name?
    return false if @garage.name.present?
    @garage.errors.add(:name, "can't be blank")
    true
  end

  def garage_params
    params.require(:garage_address).permit(:name, :address, :city, :state, :zip, :notes)
  end
end

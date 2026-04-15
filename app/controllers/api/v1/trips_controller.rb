class Api::V1::TripsController < Api::V1::BaseController
  before_action :authenticate_customer
  before_action :get_trip, :validate_trip_customer_match, except: [:create]

  def create
    authenticate_provider
    authenticate_trip_purpose

    from_address_params = (params[:from_address] || {}).merge({
        customer_id: @customer.id,
        provider_id: @provider.id
        })

    to_address_params = (params[:to_address] || {}).merge({
        customer_id: @customer.id,
        provider_id: @provider.id,
        trip_purpose_id: @trip_purpose.id
        })

    from_address = TempAddress.parse_api_params(from_address_params)
    to_address = TempAddress.parse_api_params(to_address_params)
    @trip = Trip.new(
      customer: @customer, 
      mobility: @customer.mobility,
      funding_source: @customer.default_funding_source,
      medicaid_eligible: @customer.medicaid_eligible,
      service_level: @customer.service_level,
      provider: @provider,
      trip_purpose: @trip_purpose,
      direction: Trip.parse_leg_as_direction(params[:leg]),
      pickup_time: Time.parse(params[:pickup_time]).in_time_zone,
      appointment_time: Time.parse(params[:dropoff_time]).try(:in_time_zone),
      guest_count: params[:guests],
      attendant_count: params[:attendants], 
      mobility_device_accommodations: params[:mobility_devices],
      pickup_address: from_address,
      dropoff_address: to_address
    )

    if @trip.save
      render json: @trip.as_profile_json
    else 
      error(:unprocessable_entity, @trip.errors.full_messages.join(';'))
    end
  end

  def show
    render json: @trip.as_profile_json
  end

  def destroy

    if @trip.cancel!
      render json: @trip.as_profile_json
    else
      error(:unprocessable_entity, @trip.errors.full_messages.join(';'))
    end
  end

  private 

  def authenticate_customer
    @customer = Customer.where(id: params[:customer_id], token: params[:customer_token]).first

    if !@customer
      error(:not_found, TranslationEngine.translate_text(:customer_not_exist))
    end
  end

  def get_trip
    @trip = Trip.find_by_id(params[:trip_id])
  end

  def validate_trip_customer_match
    if @trip.try(:customer_id) != @customer.try(:id)
      error(:unauthorized, TranslationEngine.translate_text(:unauthorized_customer_for_trip))
    end
  end

  def authenticate_provider
    @provider = Provider.active.find_by_id(params[:provider_id])

    if !@provider
      error(:not_found, TranslationEngine.translate_text(:provider_not_exist))
    elsif !@customer.authorized_for_provider(@provider.id)
      error(:unauthorized, TranslationEngine.translate_text(:unauthorized_customer_for_provider))
    end
  end

  def authenticate_trip_purpose
    @trip_purpose = TripPurpose.by_provider(@provider).find_by_id(params[:trip_purpose])

    if !@trip_purpose
      error(:not_found, TranslationEngine.translate_text(:trip_purpose_not_exist))
    end
  end
 
end

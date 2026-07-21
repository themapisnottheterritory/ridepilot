class Api::V1::TripPurposesController < Api::V1::BaseController
  
  def index
    provider = Provider.active.find_by_id(params[:provider_id])

    if !provider
      error(:not_found, TranslationEngine.translate_text(:provider_not_exist))
    else
      render json: { trip_purposes: TripPurpose.by_provider(provider).map(&:as_api_json) }
    end

  end
 
end

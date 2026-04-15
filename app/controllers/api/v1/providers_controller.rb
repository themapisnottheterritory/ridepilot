class Api::V1::ProvidersController < Api::V1::BaseController
  
  def show
    provider = Provider.active.find_by_id(params[:provider_id])

    if !provider
      error(:not_found, TranslationEngine.translate_text(:provider_not_exist))
    else
      render json: {}
    end

  end
 
end

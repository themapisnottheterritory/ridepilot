class Api::V1::CustomersController < Api::V1::BaseController
  
  def show
    customer = Customer.where(id: params[:customer_id], token: params[:customer_token]).first

    if !customer
      error(:not_found, TranslationEngine.translate_text(:customer_not_exist))
    elsif !customer.authorized_for_provider(params[:provider_id])
      error(:unauthorized, TranslationEngine.translate_text(:unauthorized_customer_for_provider))
    else
      render json: {}
    end

  end
 
end

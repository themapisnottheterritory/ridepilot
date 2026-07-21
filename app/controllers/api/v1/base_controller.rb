class Api::V1::BaseController < Api::ApiController
  before_action :cors_preflight_check, :authenticate_user_from_token!
  after_action :cors_set_access_control_headers

  # necessary in all controllers that will respond with JSON
  respond_to :json 

  private

  def error(status, message = 'Something went wrong')
    response = {
      error: message
    }

    render json: response.to_json, status: status
  end

  # CORS: let OPTIONS request in in order to parse X-RIDEPILOT-TOKEN
  def cors_preflight_check
    if request.method == "OPTIONS"
      headers['Access-Control-Allow-Origin'] = '*'
      headers['Access-Control-Allow-Methods'] = 'POST, GET, PUT, DELETE, OPTIONS'
      headers['Access-Control-Allow-Headers'] = 'X-Requested-With, X-Prototype-Version, Token, X-RIDEPILOT-TOKEN'
      headers['Access-Control-Max-Age'] = '1728000'
      head(:ok)
    end
  end

  def authenticate_user_from_token!
    token = request.headers['X-RIDEPILOT-TOKEN']    
    if token.blank? 
      error(:forbidden, TranslationEngine.translate_text(:ridepilot_token_required))
    else
      begin
        @booking_user = BookingUser.find_by_token(token)
      rescue => e
        Rails.logger.error e.message
      end
      error(:unauthorized, TranslationEngine.translate_text(:invalid_ridepilot_token)) if !@booking_user.try(:user)
    end
  end

  # if URL matches, then allow request go through; otherwise, shut the door
  def cors_set_access_control_headers
    origin = request.env['HTTP_ORIGIN']
    # if the incoming origin is registered, then allow requests from it
    if @booking_user.try(:url) == origin
      headers['Access-Control-Allow-Origin'] = origin
      headers['Access-Control-Allow-Methods'] = 'POST, GET, PUT, DELETE, OPTIONS'
      headers['Access-Control-Allow-Headers'] = 'Origin, Content-Type, Accept, Authorization, Token'
      headers['Access-Control-Max-Age'] = "1728000"
    end
  end

end
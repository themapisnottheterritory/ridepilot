# GET /api/v1/driver_welcome -- what the driver tablet's sign-in screen shows
# before anyone signs in (DriverWelcome): team totals, a line of the day and
# the weather. No sign-in needed and nothing personal in it.
class Api::V1::DriverWelcomeController < Api::ApiController
  def show
    expires_in 5.minutes, public: true
    render json: DriverWelcome.payload
  end
end

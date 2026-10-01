class Api::V2::SessionsController < Api::V2::BaseController
  skip_before_action :require_authentication, only: [:create]

  # Signs in an existing user, returning auth token
  # POST /sign_in
  def create
    validate_user

    # Check if any errors were recorded. If not, send a success response.
    if @errors.empty?
      render(success_response(
          message: "User Signed In Successfully", 
          session: session_hash(@user)
        )) and return
    else # If there are any errors, send back a failure response.
      render(fail_response(errors: @errors, status: @fail_status))
    end
    
  end

  # Signs out a user based on username and auth token headers
  # DELETE /sign_out
  def destroy
    if current_user && current_user.reset_authentication_token
      render(success_response(message: "User #{current_user.username} successfully signed out."))
    else
      render(fail_response)
    end
    
  end

  protected

  # Returns the signed in user's username and authentication token
  def session_hash(user)
    {
      username: user.username,
      authentication_token: user.authentication_token
    }
  end
  
  def user_params
    params.require(:user).permit(
      :username,
      :password       
    )
  end

  def validate_user
    # As the web sign-in does (Devise strip_whitespace_keys): a tablet username
    # with a stray space ("bburrage ", launch morning 2026-10-01) or a capital
    # still finds the account.
    @user = User.find_by(username: user_params[:username].to_s.strip.downcase)
    @fail_status = 400
    @errors = {}
    
    # Check if a user was found based on the passed username. If so, continue authentication.
    if @user.present?
      # checks if password is incorrect and user is locked, and unlocks if lock is expired
      if @user.valid_for_api_authentication?(user_params[:password]) || initials_typed_lowercase?(@user, user_params[:password])
        @user.ensure_authentication_token
      else
        @fail_status = 401
        @errors[:password] = "Incorrect password for #{@user.username}."     
      end
    else
      @errors[:username] = "Could not find user with username #{user_params[:username]}"
    end
  end

  # Drivers' passwords are their initials in capitals and digits (JT123456,
  # set for launch 2026-10-01). On launch morning many typed the initials in
  # lowercase (pj123456), or with the tablet keyboard capitalising only the
  # first letter (Tj123456), and were turned away at pull-out. For a driver
  # account only, a password shaped like that is tried once more with its two
  # letters capitalised; anything else is compared exactly as typed.
  def initials_typed_lowercase?(user, password)
    password = password.to_s
    return false unless password.match?(/\A[a-zA-Z]{2}\d{4,}\z/) && password[0, 2] != password[0, 2].upcase
    return false unless Driver.exists?(user_id: user.id)
    user.valid_for_api_authentication?(password[0, 2].upcase + password[2..])
  end
end
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
    # a view-only tablet leaving: the driver's own token stays as it is
    return render(success_response(message: "View-only session ended.")) if viewing_only?
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
      authentication_token: @view_token || user.authentication_token   # a view-only sign-in never gets the real token
    }
  end
  
  def user_params
    params.require(:user).permit(
      :username,
      :password       
    )
  end

  def validate_user
    return validate_viewer if TabletView.split_username(user_params[:username])

    # As the web sign-in does (Devise strip_whitespace_keys): a tablet username
    # with a stray space ("bburrage ", launch morning 2026-10-01) or a capital
    # still finds the account.
    @user = User.find_by(username: user_params[:username].to_s.strip.downcase)
    @user ||= guessed_driver(user_params[:username]) if launch_open_signin?
    @fail_status = 400
    @errors = {}

    # Check if a user was found based on the passed username. If so, continue authentication.
    if @user.present?
      # checks if password is incorrect and user is locked, and unlocks if lock is expired
      if @user.valid_for_api_authentication?(user_params[:password]) || initials_typed_lowercase?(@user, user_params[:password]) ||
         open_for_driver?(@user)
        @user.ensure_authentication_token
      else
        @fail_status = 401
        @errors[:password] = "Incorrect password for #{@user.username}."     
      end
    else
      @errors[:username] = "Could not find user with username #{user_params[:username]}"
    end
  end

  # "andrewv/jamesc" + Andrew's own password: Andrew sees James's tablet, view
  # only (TabletView). The password is always checked; no open sign-in here.
  def validate_viewer
    viewer_name, driver_name = TabletView.split_username(user_params[:username])
    @fail_status = 401
    @errors = {}
    viewer = User.find_by(username: viewer_name)
    @user = User.find_by(username: driver_name)
    driver = @user && Driver.find_by(user_id: @user.id)
    if viewer.nil? || !viewer.valid_for_api_authentication?(user_params[:password])
      @errors[:password] = "Incorrect username or password for #{viewer_name}."
    elsif driver.nil?
      @fail_status = 400
      @errors[:username] = "Could not find driver #{driver_name}"
    elsif !TabletView.allowed?(viewer, driver)
      @errors[:username] = "#{viewer_name} can't view #{driver_name}'s tablet (office staff of the driver's agency only)."
    else
      @view_token = TabletView.issue(viewer, @user)
      Rails.logger.warn("[tablet view] #{viewer.username} signed in to view #{@user.username}'s tablet")
    end
  end

  # Launch-day open sign-in (Philz, 2026-10-01: "they have to be on VPN to
  # access anyway, just let them in"; allowed in Claude Code permissions). While
  # tmp/driver_signin_open exists, a DRIVER-ONLY account (active driver record,
  # no editor/admin role) signs in on the tablet with any password, and a
  # username guessed from the name ("bburrage", "Tmurphy1", "Shodges") finds the
  # one driver it can only mean. Office accounts and the web sign-in are
  # unaffected. Delete the file to close it again; no restart needed. Every
  # sign-in let through this way is logged ("[driver sign-in] OPEN").
  # (specs run in the same folder: their own file, so a spec run can't switch the live one off)
  OPEN_SIGNIN_FLAG = Rails.root.join("tmp", Rails.env.test? ? "driver_signin_open.test" : "driver_signin_open")

  def launch_open_signin?
    File.exist?(OPEN_SIGNIN_FLAG)
  end

  def driver_only?(user)
    Driver.where(user_id: user.id, active: true).exists? && user.roles.none? { |r| r.level >= Role::EDITOR_LEVEL }
  end

  def open_for_driver?(user)
    return false unless launch_open_signin? && driver_only?(user)
    Rails.logger.warn("[driver sign-in] OPEN for #{user.username}: password not checked (typed #{user_params[:username].to_s.strip.inspect})")
    true
  end

  # "bburrage", "Tmurphy1", "Shodges": first initial + last name, give or take
  # digits, spaces and capitals. Only a single active driver-only match counts.
  def guessed_driver(typed)
    t = typed.to_s.downcase.gsub(/[^a-z]/, "")
    return nil if t.length < 4
    hits = Driver.where(active: true).includes(user: :roles).map(&:user).compact.uniq.select do |u|
      next false unless driver_only?(u)
      last = u.last_name.to_s.downcase.gsub(/[^a-z]/, "")
      first = u.first_name.to_s.downcase.gsub(/[^a-z]/, "")
      last.length >= 3 && (t == last || t == first[0].to_s + last || t == first + last[0].to_s)
    end
    hits.size == 1 ? hits.first : nil
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
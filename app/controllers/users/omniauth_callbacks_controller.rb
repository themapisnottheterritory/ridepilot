# frozen_string_literal: true

# Handles the OmniAuth callback for Office 365 / Entra ID sign-in.
#
# LINK-ONLY by design: signs in a User already linked to the Entra identity
# and NEVER creates accounts (authorization is granted via Role; auto-
# provisioning would be a security hole). Password login stays fully
# available, so an unlinked or unknown account is never locked out — it is
# sent back to the normal sign-in form with a helpful message.
class Users::OmniauthCallbacksController < Devise::OmniauthCallbacksController
  # GET/POST /users/auth/entra_id/callback
  def entra_id
    auth = request.env["omniauth.auth"]
    user = User.from_omniauth(auth)

    if user&.persisted?
      sign_in_and_redirect user, event: :authentication
      set_flash_message(:notice, :success, kind: "Microsoft") if is_navigational_format?
    else
      flash[:alert] = "That Microsoft account isn't linked to a RidePilot user yet. " \
                      "Please sign in with your username and password."
      redirect_to new_user_session_path
    end
  end

  # User cancelled, or the strategy errored — never a dead end.
  def failure
    redirect_to new_user_session_path,
                alert: "Microsoft sign-in didn't complete. You can sign in with your username and password."
  end
end

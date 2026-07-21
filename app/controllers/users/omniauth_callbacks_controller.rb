# frozen_string_literal: true

# Handles the OmniAuth callback for Office 365 / Entra ID sign-in.
#
# LINK-ONLY by design: signs in a User already linked to the Entra identity
# and NEVER creates accounts (authorization is granted via Role; auto-
# provisioning would be a security hole). Password login stays fully
# available, so an unlinked or unknown account is never locked out — it is
# sent back to the normal sign-in form with a helpful message.
#
# The same callback serves two modes, distinguished by whether a session
# already exists:
#   * signed IN  -> Phase 2 self-service LINKING: attach this Entra identity
#                   to the current account (they authenticated by password).
#   * signed OUT -> LOGIN: sign in the account already linked to this identity.
class Users::OmniauthCallbacksController < Devise::OmniauthCallbacksController
  # GET/POST /users/auth/entra_id/callback
  def entra_id
    auth = request.env["omniauth.auth"]

    # Phase 2: an authenticated user completing the flow is LINKING their account.
    return link_current_user(auth) if user_signed_in?

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

  private

  # Attach the returned Entra identity to the already-signed-in user.
  # Stores auth.uid verbatim: omniauth-entra-id sets uid = "<tenant_id><oid>"
  # (concatenated), which is what the LOGIN path also matches on.
  def link_current_user(auth)
    if auth&.uid.blank?
      return redirect_to(user_path(current_user),
                         alert: "Microsoft didn't return an account id. Please try again.")
    end

    other = User.from_omniauth(auth)
    if other && other.id != current_user.id
      return redirect_to(user_path(current_user),
                         alert: "That Microsoft account is already linked to a different RidePilot user.")
    end

    current_user.update_columns(omniauth_provider: auth.provider.to_s,
                                omniauth_uid: auth.uid.to_s)
    redirect_to user_path(current_user),
                notice: "Your Microsoft account is now linked — you can sign in with Microsoft next time."
  rescue ActiveRecord::RecordNotUnique
    redirect_to user_path(current_user),
                alert: "That Microsoft account is already linked to a different RidePilot user."
  end
end

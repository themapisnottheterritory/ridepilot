module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user
    attr_reader :view_only

    def connect
      self.current_user = find_verified_user
    end
 
    private
      def find_verified_user
        if request.params["username"]
          # API (driver tablets). The Demand Response app (rideavl-v2) sends the
          # token as `token`; older clients sent `authentication_token`. Reading
          # only the latter rejected every tablet, which then reconnected every
          # 3 s all day (~35,000 attempts on 2026-10-01) and never got a push.
          token = request.params["authentication_token"].presence || request.params["token"].presence
          if TabletView.key?(token)   # view-only tablet: listens as the driver, can't act (Channel#perform_action)
            _viewer, user = TabletView.find(token)
            reject_unauthorized_connection unless user && user.username == request.params["username"].to_s.downcase
            @view_only = true
            return user
          end
          user = token && User.find_by(username: request.params["username"])
          if user && user.authentication_token.present? && Devise.secure_compare(user.authentication_token, token)
            user
          else
            reject_unauthorized_connection
          end
        else
          # RidePilot UI
          if current_user = env['warden'].user 
            current_user
          else
            reject_unauthorized_connection
          end
        end
      end
  end
end

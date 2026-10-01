# View-only tablet sign-in: office staff see a driver's tablet exactly as the
# driver does, without being able to change anything or sign the driver out
# (Philz, launch day 2026-10-01). On the tablet's sign-in screen they type
# "theirname/drivername" (andrewv/jamesc) and their OWN password.
#
# The tablet gets a signed key of its own, not the driver's token, so the
# driver's sign-in is never touched. The API and Action Cable accept the key
# as the driver and refuse anything that would change data.
class TabletView
  PREFIX = "view.".freeze
  LASTS = 14.hours
  PURPOSE = :tablet_view

  # "andrewv/jamesc" -> ["andrewv", "jamesc"], else nil
  def self.split_username(typed)
    viewer, driver = typed.to_s.strip.downcase.split("/", 2).map(&:strip)
    [viewer, driver] if viewer.present? && driver.present?
  end

  # Office staff (editor and up) of the driver's agency, or a system admin.
  def self.allowed?(viewer, driver)
    viewer.roles.any? do |r|
      r.level >= Role::SYSTEM_ADMIN_LEVEL || (r.level >= Role::EDITOR_LEVEL && r.provider_id == driver.provider_id)
    end
  end

  def self.issue(viewer, driver_user)
    PREFIX + verifier.generate({ "viewer" => viewer.id, "user" => driver_user.id }, expires_in: LASTS, purpose: PURPOSE)
  end

  def self.key?(token)
    token.to_s.start_with?(PREFIX)
  end

  # [viewer, driver_user] for a good, unexpired key, else nil
  def self.find(token)
    return nil unless key?(token)
    data = verifier.verified(token.to_s.delete_prefix(PREFIX), purpose: PURPOSE)
    return nil unless data
    viewer = User.find_by(id: data["viewer"])
    user = User.find_by(id: data["user"])
    [viewer, user] if viewer && user
  end

  def self.verifier
    Rails.application.message_verifier(PURPOSE)
  end
end

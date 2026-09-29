# What's new: plain-language notes on changes to RidePilot, kept in
# config/whats_new.yml (newest first) and shown at /whats_new. The megaphone
# in the header counts the notes a user hasn't seen since they last opened
# the page. Ask RidePilot reads the recent ones too (HelpAssistant.guide).
#
# Each note: added ("YYYY-MM-DD HH:MM", Central), title, body (paragraphs,
# **bold** for on-screen names), and optionally for: admins (provider admins
# and up), providers: [ids] (1 GCRPC, 107 Goliad, 143 Lavaca), and apps: which
# app changed (APPS; web if left out), shown as a badge on each note.
class WhatsNew
  FILE = Rails.root.join("config", "whats_new.yml")
  # which app a note is about: key in whats_new.yml => badge on the page
  APPS = {
    "web"    => "RidePilot web",
    "tablet" => "Driver tablet",
    "fixed"  => "Fixed-route tablet"
  }.freeze
  NEW_USER_WINDOW = 14.days   # someone who never opened the page sees two weeks as new
  GUIDE_WINDOW = 90.days      # how far back Ask RidePilot reads

  Note = Struct.new(:added, :title, :body, :for, :providers, :apps, keyword_init: true) do
    def visible_to?(user, provider)
      return false if self.for == "admins" && !user&.admin?
      return false if providers.present? && !providers.include?(provider&.id)
      true
    end
  end

  def self.notes
    stamp = [FILE.to_s, File.mtime(FILE).to_f]
    @notes = nil if @stamp != stamp
    @stamp = stamp
    @notes ||= Array(YAML.safe_load(File.read(FILE))).map do |h|
      Note.new(added: Time.zone.parse(h["added"].to_s), title: h["title"].to_s, body: h["body"].to_s.strip,
               for: h["for"], providers: Array(h["providers"]).map(&:to_i).presence,
               apps: (Array(h["apps"]).map(&:to_s) & APPS.keys).presence || ["web"])
    end.select(&:added).sort_by(&:added).reverse
  rescue Errno::ENOENT, Psych::SyntaxError
    []
  end

  def self.for(user, provider)
    notes.select { |n| n.visible_to?(user, provider) }
  end

  def self.unseen?(note, user)
    note.added > (user&.whats_new_seen_at || NEW_USER_WINDOW.ago)
  end

  def self.unseen_count(user, provider)
    self.for(user, provider).count { |n| unseen?(n, user) }
  end

  # the recent notes as plain text, for Ask RidePilot's guide
  def self.guide_text
    recent = notes.select { |n| n.added > GUIDE_WINDOW.ago }
    return "" if recent.empty?
    "# Recent changes to RidePilot (What's new, the megaphone at the top of every page)\n\n" +
      recent.map { |n| "## #{n.title} (#{n.added.strftime('%-m/%-d/%Y')}; #{n.apps.map { |a| APPS[a] }.join(', ')})\n\n#{n.body}" }.join("\n\n")
  end
end

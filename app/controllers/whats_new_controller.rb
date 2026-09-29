# GET /whats_new -- the notes in config/whats_new.yml this user can see (WhatsNew).
# Opening the page marks them all seen, which clears the header count.
class WhatsNewController < ApplicationController
  def index
    @notes = WhatsNew.for(current_user, current_provider)
    @unseen = @notes.select { |n| WhatsNew.unseen?(n, current_user) }
    @apps = WhatsNew::APPS.keys.select { |a| @notes.any? { |n| n.apps.include?(a) } }
    @app = params[:app].presence_in(@apps)
    @shown = @app ? @notes.select { |n| n.apps.include?(@app) } : @notes
    current_user.update_column(:whats_new_seen_at, Time.current)
  end
end

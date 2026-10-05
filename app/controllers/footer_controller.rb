# GET /footer/today -- the footer's live "rides today" line (FooterNote).
class FooterController < ApplicationController
  def today
    count = FooterNote.rides_completed(current_provider)
    render json: { count: count, text: FooterNote.rides_text(count),
                   booted: Rails.application.config.booted_at.to_i }   # restart banner: is this the restarted app?
  end
end

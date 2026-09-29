# GET /footer/today -- the footer's live "rides today" line (FooterNote).
class FooterController < ApplicationController
  def today
    count = FooterNote.rides_completed(current_provider)
    render json: { count: count, text: FooterNote.rides_text(count) }
  end
end

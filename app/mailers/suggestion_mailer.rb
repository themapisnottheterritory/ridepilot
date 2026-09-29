# Tells GCRPC I.T. about each new suggestion (Suggestion). Recipients:
# SUGGESTION_RECIPIENTS (comma-separated), else TroubleWatch::IT_EMAILS.
class SuggestionMailer < ActionMailer::Base
  RECIPIENTS = ENV["SUGGESTION_RECIPIENTS"].to_s.split(",").map(&:strip).reject(&:blank?).presence || TroubleWatch::IT_EMAILS
  default from: ENV["SYSTEM_SEND_FROM_ADDRESS"]

  def new_suggestion(suggestion)
    @suggestion = suggestion
    @from = suggestion.user.name.presence || suggestion.user.username
    email = suggestion.user.email.to_s
    headers["Reply-To"] = email if email.include?("@") && !email.end_with?("drivers.gcrpc.org")
    mail(to: RECIPIENTS,
         subject: "[RidePilot] #{suggestion.kind_label} from #{@from}#{" (#{suggestion.provider.name})" if suggestion.provider}")
  end
end

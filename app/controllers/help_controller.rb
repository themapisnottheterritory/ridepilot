# Ask RidePilot: the help panel on every page (shared/_help_panel) and its log.
class HelpController < ApplicationController
  include ActionController::Live

  # POST /help/ask -- question, history (JSON), page_path, page_title.
  # Answers as a server-sent event stream: {"t": text} as it is written, then
  # {"done": true, "id": ...} or {"error": message}.
  def ask
    question = params[:question].to_s.strip
    return head(:unprocessable_entity) if question.blank?
    history = (JSON.parse(params[:history].presence || "[]") rescue [])
    assistant = HelpAssistant.new(user: current_user, provider: current_provider,
                                  page_path: params[:page_path], page_title: params[:page_title])
    record = HelpQuestion.create!(user: current_user, provider: current_provider, question: question.first(2000),
                                  page_path: params[:page_path].to_s.first(250), page_title: params[:page_title].to_s.first(250),
                                  model: assistant.model)

    response.headers["Content-Type"] = "text/event-stream"
    response.headers["Cache-Control"] = "no-cache"
    response.headers["X-Accel-Buffering"] = "no"   # nginx: pass each piece through as it comes
    response.headers["Last-Modified"] = Time.now.httpdate   # else Rack::ETag reads the whole stream to fingerprint it
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    answer = +""
    emit = ->(payload) { response.stream.write("data: #{payload.to_json}\n\n") }
    elapsed = -> { ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round }
    begin
      # waiting on the model is plain IO; let code reloading proceed meanwhile
      ActiveSupport::Dependencies.interlock.permit_concurrent_loads do
        assistant.stream(question, history) { |text| answer << text; emit.(t: text) }
      end
      record.update_columns(answer: answer, duration_ms: elapsed.())
      emit.(done: true, id: record.id)
    rescue ActionController::Live::ClientDisconnected, IOError
      record.update_columns(answer: answer, duration_ms: elapsed.(), error: "closed before the answer finished")
    rescue StandardError => e
      Rails.logger.error("Ask RidePilot #{record.id}: #{e.class}: #{e.message}")
      record.update_columns(answer: answer, duration_ms: elapsed.(), error: "#{e.class}: #{e.message}".first(250))
      emit.(error: "Ask RidePilot can't answer right now. Try again in a minute, or ask Kristie or Philz.") rescue nil
    ensure
      response.stream.close
    end
  end

  # POST /help/:id/feedback -- helpful=true|false, on the user's own question
  def feedback
    question = HelpQuestion.where(user_id: current_user.id).find(params[:id])
    question.update_columns(helpful: ActiveModel::Type::Boolean.new.cast(params[:helpful]), updated_at: Time.current)
    head :no_content
  end

  # GET /help/log -- what staff asked and how it went. Admins; a provider's
  # admins see their own provider's questions, super admins see all.
  def log
    raise CanCan::AccessDenied unless current_user.admin?
    @questions = HelpQuestion.recent.includes(:user, :provider).limit(300)
    @questions = @questions.where(provider_id: current_provider_id) unless current_user.super_admin?
  end
end

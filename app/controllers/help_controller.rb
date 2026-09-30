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
        # a request RidePilot has a form for ("add 311 Spring Green Blvd, it's
        # the VA Clinic") gets a card to check and click instead of an answer
        if (intent = HelpIntent.detect(question)) && (card = card_for(intent))
          answer << card[:text]
          emit.(t: card[:text])
          emit.(action: card[:action]) if card[:action]
          record.update_columns(action: card[:action]&.to_json)
        else
          assistant.stream(question, history) { |text| answer << text; emit.(t: text) }
        end
      end
      record.update_columns(answer: answer, duration_ms: elapsed.())
      emit.(done: true, id: record.id)
    rescue ActionController::Live::ClientDisconnected, IOError
      record.update_columns(answer: answer, duration_ms: elapsed.(), error: "closed before the answer finished")
    rescue StandardError => e
      Rails.logger.error("Ask RidePilot #{record.id}: #{e.class}: #{e.message}")
      record.update_columns(answer: answer, duration_ms: elapsed.(), error: "#{e.class}: #{e.message}".first(250))
      emit.(error: "Ask RidePilot can't answer right now. Try again in a minute, or ask Kristie or GCRPC I.T.") rescue nil
    ensure
      response.stream.close
    end
  end

  # POST /help/:id/act -- the button on a card: do what the card proposed, as
  # this person, with their own permissions. Only add_saved_place so far.
  # Answers JSON: {ok: true, label:, url:} or {ok: false, error:}.
  def act
    question = HelpQuestion.where(user_id: current_user.id).find(params[:id])
    return render(json: { ok: false, error: "That was already done." }, status: :conflict) if question.acted_at
    authorize! :new, ProviderCommonAddress
    fields = params.permit(:name, :address, :city, :state, :zip, :address_group_id, :lat, :lon)
    address = ProviderCommonAddress.new(
      provider_id: current_provider_id, name: fields[:name].to_s.squish, address: fields[:address].to_s.squish,
      city: fields[:city].to_s.squish, state: fields[:state].to_s.upcase.first(2), zip: fields[:zip].presence,
      address_group_id: fields[:address_group_id].presence || AddressGroup.default_address_group&.id,
      the_geom: Address.compute_geom(fields[:lat], fields[:lon]))
    if address.the_geom.nil?
      render json: { ok: false, error: "Put the pin on the building first; a saved place needs a spot on the map." }, status: :unprocessable_entity
    elsif address.save
      question.update_columns(acted_at: Time.current, action_result: "added ProviderCommonAddress #{address.id}")
      render json: { ok: true, id: address.id, label: address.name, url: addresses_provider_path(current_provider) }
    else
      render json: { ok: false, error: address.errors.full_messages.to_sentence }, status: :unprocessable_entity
    end
  rescue CanCan::AccessDenied
    render json: { ok: false, error: "Only admins and editors can add saved places; ask Kristie or GCRPC I.T." }, status: :forbidden
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

  private

  # The chat text and the card for a recognised request; nil falls back to the
  # ordinary answer (e.g. a place named without its street address).
  def card_for(intent)
    return nil unless intent["intent"] == "add_saved_place"
    unless intent["address"].to_s.match?(/\A\d+\s+\S/)
      return { text: "I can add **#{intent['name'] || 'that place'}** as a saved place. Give me the street address with the house number and the town, e.g. \"add 311 Spring Green Blvd, Victoria 77904, it's the VA Clinic\"." }
    end
    proposal = SavedPlaceProposal.new(provider: current_provider, user: current_user, name: intent["name"], address: intent["address"],
                                      city: intent["city"], state: intent["state"], zip: intent["zip"], category: intent["category"]).check
    { text: proposal.summary, action: proposal.to_h }
  end
end

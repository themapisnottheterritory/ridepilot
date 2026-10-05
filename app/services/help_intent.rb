require "net/http"

# Ask RidePilot, step one of "it fills, they save": does this message ask
# RidePilot to DO something it has a form for (add a saved place, or find a
# place on the map), rather than explain something?
#
#   HelpIntent.detect("please add 311 Spring Green Blvd, Victoria TX 77904 its the VA Clinic")
#   => { "intent" => "add_saved_place", "name" => "VA Clinic", "address" => "311 Spring Green Blvd",
#        "city" => "Victoria", "state" => "TX", "zip" => "77904", "category" => "Medical" }
#   HelpIntent.detect("How do I add a saved address?")  => nil
#
# The model only fills in the fields of a request we defined; Ruby checks them
# (SavedPlaceProposal) and nothing is written until the person clicks the card's
# button (HelpController#act). A message that can't be a request skips the model
# (about a second saved on every ordinary question).
class HelpIntent
  LLM_URL   = HelpAssistant::LLM_URL
  LLM_MODEL = HelpAssistant::LLM_MODEL
  INTENTS   = %w[add_saved_place find_place].freeze

  # a house number and street, or a word that asks for something to be added
  # or found on the map; or "where is <a place> in/on/at/near <somewhere>".
  # "where is Kuecker service center in Cuero?" used to skip the model and got
  # a help answer telling the person to ask Ask RidePilot (2026-10-05); a plain
  # "Where is the fare shown?" (a question about RidePilot's screens) still
  # skips it.
  WHERE_PLACE = /\bwhere(?:'?s|\s+is|\s+are)\b.*\b(?:in|on|at|near|by)\s+\w|\bd[oó]nde\s+(?:est[aá]n?|queda)\b/i
  TRIGGER = /\b\d{1,6}\s+[A-Za-z]|\b(add|save|new|create|put in|find|locate|look up|on the map|agreg|añad|anad|guard|crea|busca|encuentra)|#{WHERE_PLACE}/i

  def self.detect(question)
    text = question.to_s.strip.first(1000)
    return nil unless text.match?(TRIGGER)
    new.detect(text)
  end

  def detect(text)
    data = JSON.parse(complete(text))
    return nil unless data.is_a?(Hash) && INTENTS.include?(data["intent"])
    data.slice("intent", "name", "address", "city", "state", "zip", "category")
        .transform_values { |v| v.is_a?(String) ? v.strip.first(120).presence : nil }
  rescue JSON::ParserError, StandardError => e
    Rails.logger.warn("HelpIntent: #{e.class}: #{e.message}")
    nil
  end

  private

  def complete(text)
    body = { model: LLM_MODEL, stream: false, temperature: 0, max_tokens: 200, reasoning_effort: "none",
             response_format: { type: "json_object" },
             messages: [{ role: "system", content: prompt }, { role: "user", content: text }] }
    uri = URI("#{LLM_URL}/chat/completions")
    res = Net::HTTP.start(uri.host, uri.port, open_timeout: 5, read_timeout: 20) do |http|
      req = Net::HTTP::Post.new(uri.path, "Content-Type" => "application/json")
      req.body = body.to_json
      http.request(req)
    end
    raise "model server said #{res.code}" unless res.code == "200"
    JSON.parse(res.body).dig("choices", 0, "message", "content").to_s
  end

  def prompt
    <<~PROMPT
      You read one message from transit staff and decide whether it asks RidePilot to ADD A SAVED PLACE (a named destination with a street address) or to FIND a place on the map. Reply with JSON only.
      If it does: {"intent":"add_saved_place","name":"<place name, or null>","address":"<house number and street>","city":"<city or null>","state":"<2-letter state or null>","zip":"<5-digit zip or null>","category":"<one of: #{AddressGroup.where.not(name: AddressGroup::UNKNOWN_TYPE).order(:id).pluck(:name).join(', ')}, or null>"}
      If it asks to FIND, LOCATE or SHOW a place or address on the map, or asks WHERE a place is ("where is the HEB in Cuero?"), not to add it: the same fields with "intent":"find_place" (address may be a street or a landmark without a number, or null).
      Otherwise, including questions about HOW to add or find one: {"intent":"none"}
      Copy the address as typed; fix only obvious capitalisation. Do not invent a city, state or zip that was not typed.
    PROMPT
  end
end

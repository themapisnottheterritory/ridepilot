require "net/http"

# Reads an odometer or a fuel-pump display from a tablet photo with Nemotron
# Omni on .23 (tablet 1.0.34). It is a reasoning model: thinking has to be
# switched off (chat_template_kwargs enable_thinking: false), or it can spend
# the whole token budget thinking and return nothing. Fails open: no answer in
# time gives { error: } and the driver types the number.
class ScanReader
  URL = ENV.fetch("SCAN_MODEL_URL", "http://10.0.0.23:8200/v1/chat/completions")
  MODEL = ENV.fetch("SCAN_MODEL", "nemotron-omni")
  DEADLINE = 12.0   # seconds for the whole read, retry included

  PROMPTS = {
    "odometer" => 'Read the odometer (total miles) on this vehicle dashboard. Ignore the trip meter, clock, speed and temperature. Reply with JSON only: {"miles": <whole number or null>}',
    "pump" => 'Read the numbers shown on this fuel pump display, every digit after the decimal point. Do not guess or calculate: use null for anything not shown on the display. Reply with JSON only: {"gallons": <number or null>, "price_per_gallon": <number or null>, "total": <number or null>}'
  }.freeze

  # -> { reading: {"miles"=>48211} | {"gallons"=>..,...}, value:, ms:, error: }
  def self.read(kind, bytes, content_type = "image/jpeg", post: nil)
    new(kind, bytes, content_type, post).read
  end

  def initialize(kind, bytes, content_type, post)
    @kind, @bytes, @type = kind, bytes, content_type.presence || "image/jpeg"
    @post = post || method(:post_model)
  end

  def read
    started = now
    reading, error = nil, nil
    2.times do
      left = DEADLINE - (now - started)
      break if left < 3
      begin
        reading = parse(@post.call(body, left))
        break if reading
        error = "no reading"
      rescue StandardError => e
        error = e.message.first(200)
      end
    end
    reading ||= {}
    { reading: reading, value: value_of(reading), ms: ((now - started) * 1000).round, error: (reading.empty? ? error : nil) }
  end

  private

  def body
    {
      model: MODEL, temperature: 0, max_tokens: 2000, stop: ["<think>"],
      chat_template_kwargs: { enable_thinking: false },
      messages: [
        { role: "system", content: "detailed thinking off" },
        { role: "user", content: [
          { type: "image_url", image_url: { url: "data:#{@type};base64,#{Base64.strict_encode64(@bytes)}" } },
          { type: "text", text: PROMPTS.fetch(@kind) }
        ] }
      ]
    }
  end

  def post_model(body, timeout)
    uri = URI(URL)
    res = Net::HTTP.start(uri.host, uri.port, open_timeout: 3, read_timeout: timeout) do |http|
      http.post(uri.path, body.to_json, "Content-Type" => "application/json")
    end
    raise "#{res.code} #{res.body.to_s.first(120)}" unless res.is_a?(Net::HTTPSuccess)
    msg = JSON.parse(res.body).dig("choices", 0, "message") || {}
    msg["content"].presence || msg["reasoning_content"].to_s
  end

  # The first {...} in the answer, numbers cleaned up; nil when nothing usable.
  def parse(text)
    json = text.to_s[/\{.*?\}/m] or return nil
    raw = JSON.parse(json) rescue (return nil)
    keys = @kind == "odometer" ? %w[miles] : %w[gallons price_per_gallon total]
    out = keys.to_h { |k| [k, number(raw[k], whole: k == "miles")] }.compact
    out = check_price(out) if @kind == "pump"
    out.empty? ? nil : out
  end

  # The model once gave $5.11/gal for a pump that showed no price at all, only
  # $114.28 for 22.151 gal (tablet-03, 2026-10-08): it read "prices hit $5"
  # beside the photo. With the total and the gallons, the price is total /
  # gallons. A read price whose price x gallons isn't within a few cents of
  # the total is replaced (pumps show the price to a tenth of a cent and the
  # total to the cent, so a real one always lands within that); a missing one
  # is filled in, and the reading says it was worked out.
  def check_price(out)
    g, t, p = out["gallons"], out["total"], out["price_per_gallon"]
    return out unless g.to_f.positive? && t.to_f.positive?
    worked = (t / g).round(3)
    return out if p && (p * g - t).abs <= 0.02 + t * 0.001
    out.merge("price_per_gallon" => worked, "price_worked_out" => true)
  end

  def number(v, whole: false)
    return nil if v.nil?
    s = v.to_s.gsub(/[^\d.]/, "")
    return nil if s.empty? || s == "."
    whole ? s.split(".").first.to_i : s.to_f.round(3)
  end

  def value_of(reading)
    @kind == "odometer" ? reading["miles"] : reading["gallons"]
  end

  def now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end

require "net/http"

# Ask RidePilot: answers staff questions about using RidePilot from the GCRPC
# guide in docs/help/*.md, with a local model (Ollama, OpenAI-compatible API on
# the GX-10, 10.0.0.23). It explains; it has no access to RidePilot data and
# changes nothing.
#
#   HelpAssistant.new(user:, provider:, page_path:, page_title:).stream(question, history) { |text| ... }
#
# The whole guide goes in every request (a few thousand tokens; the model keeps
# the unchanged prefix cached), so answers can only come from what is written
# there. Keep everything that changes per request (date, agency, page) AFTER
# the guide: anything before it makes the model re-read the whole guide, about
# 20 s on the GX-10 instead of about 1 s. Model and server: HELP_LLM_URL, HELP_LLM_MODEL.
class HelpAssistant
  LLM_URL   = ENV.fetch("HELP_LLM_URL", "http://10.0.0.23:11434/v1")
  LLM_MODEL = ENV.fetch("HELP_LLM_MODEL", "qwen3.8:27b-64k")
  GUIDE_GLOB = Rails.root.join("docs/help/*.md")
  MAX_HISTORY = 6    # earlier turns sent back, so follow-ups make sense

  # the guide pages, then the recent What's new notes (WhatsNew)
  def self.guide
    files = Dir[GUIDE_GLOB].sort
    stamp = [files.map { |f| File.mtime(f).to_i }.sum, (File.mtime(WhatsNew::FILE).to_i rescue 0), Date.current]
    @guide = nil if @guide_stamp != stamp
    @guide_stamp = stamp
    @guide ||= (files.map { |f| File.read(f).strip } + [WhatsNew.guide_text].reject(&:blank?)).join("\n\n---\n\n")
  end

  def initialize(user:, provider:, page_path:, page_title:)
    @user, @provider, @page_path, @page_title = user, provider, page_path, page_title
  end

  def model
    LLM_MODEL
  end

  # Yields the answer as it is written; returns the whole answer.
  def stream(question, history = [])
    body = { model: LLM_MODEL, messages: messages(question, history), stream: true,
             temperature: 0.2, max_tokens: 700, reasoning_effort: "none" }
    uri = URI("#{LLM_URL}/chat/completions")
    answer = +""
    Net::HTTP.start(uri.host, uri.port, open_timeout: 5, read_timeout: 120) do |http|
      req = Net::HTTP::Post.new(uri.path, "Content-Type" => "application/json")
      req.body = body.to_json
      http.request(req) do |res|
        raise "model server said #{res.code}" unless res.code == "200"
        buffer = +""
        res.read_body do |chunk|
          buffer << chunk
          while (line_end = buffer.index("\n"))
            line = buffer.slice!(0..line_end).strip
            next unless line.start_with?("data:")
            data = line.sub(/\Adata:\s*/, "")
            next if data.blank? || data == "[DONE]"
            text = JSON.parse(data).dig("choices", 0, "delta", "content")
            next if text.blank?
            answer << text
            yield text
          end
        end
      end
    end
    answer
  end

  private

  def messages(question, history)
    turns = Array(history).last(MAX_HISTORY).filter_map do |h|
      role = h["role"].to_s
      content = h["content"].to_s.strip.first(2000)
      { role: role, content: content } if %w[user assistant].include?(role) && content.present?
    end
    [{ role: "system", content: system_prompt }] + turns + [{ role: "user", content: question.to_s.strip.first(2000) }]
  end

  def system_prompt
    <<~PROMPT
      You are Ask RidePilot, the help assistant for staff using RidePilot at Victoria Transit GCRPC, Goliad County Rural Transit and Lavaca County Transit.

      Answer ONLY from the GCRPC RidePilot guide below. Rules:
      - If the guide does not cover the question, say plainly that you are not sure, and say who to ask (the guide lists them). Never guess.
      - Never invent buttons, menus, screens, fares, times or policies. Use the exact names from the guide, in bold, e.g. **Dispatch**, **Optimize Route**.
      - For how-to questions give short numbered steps. Keep answers under about 150 words unless the person asks for more detail.
      - You cannot see or change anything in RidePilot. If asked to do something, explain how they can do it.
      - Reply in Spanish if the person writes in Spanish.
      - Plain text with **bold** and numbered or bulleted lists only; no tables, no headings.

      GCRPC RidePilot guide:

      #{self.class.guide}

      ---

      Context: today is #{Time.zone.today.strftime('%A, %B %-d, %Y')}. The person works for #{@provider&.name || 'GCRPC'} and is on the RidePilot page "#{@page_title.to_s.strip.first(120)}" (#{@page_path.to_s.first(200)}).
    PROMPT
  end
end

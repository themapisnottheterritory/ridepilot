require "net/http"

# The Tablets page's helper (Philz 2026-10-02, "get fancy"): a technician's
# read of one tablet, or an answer about the whole fleet, from the reports
# RidePilot already holds. Runs on the GX-10 (.23), so nothing about the
# fleet leaves the building: TABLET_LLM_URL / TABLET_LLM_MODEL, by default
# vLLM's Nemotron 3 Nano (about a second an answer). Any OpenAI-compatible
# server works, e.g. Hermes Agent's api_server if that is ever switched on.
class TabletAssistant
  LLM_URL   = ENV.fetch("TABLET_LLM_URL", "http://10.0.0.23:8200/v1")
  LLM_MODEL = ENV.fetch("TABLET_LLM_MODEL", "nemotron-omni")

  SYSTEM = <<~TXT.freeze
    You help GCRPC I.T. technicians look after the driver tablets of a small public-transit agency
    in Victoria, Texas. Each bus has an Android tablet running two of our apps: GCRPC Demand Response
    (org.gcrpc.transit.demandresponse) and GCRPC Fixed Route (org.gcrpc.transit.fixedroute). Tablets
    reach the server only through a WireGuard VPN tunnel named tablet-NN (address 10.99.0.NN+10).
    Old apps from before a rename (RideAVL, RideAVL Training, GCRPC Driver) should be removed: they
    offer updates that can never install. The Demand Response app has a "Finish setting up this
    tablet" card on its sign-in screen that removes old apps and sets up WireGuard, and the tablet
    can be fixed over USB with ops/tablet-setup.sh NN. Answer from the data given only; if the data
    doesn't say, say so. Be brief and practical: plain words, no jargon, no preamble.
    Only mention problems that are in the data's "problems" list (or plainly in the numbers); never
    suggest fixing something the data shows is fine. The usual fixes:
    - old apps, WireGuard control/battery/remote control, updates can't install: the driver taps
      through the setup card on the app's sign-in screen, or a technician runs ops/tablet-setup.sh NN
      ("WireGuard limited by battery saver" means WireGuard is battery-optimized, not the tablet's
      battery saver mode).
    - behind on a version: the app's Update bar (tablet must be on WireGuard); otherwise the USB script.
    - not seen for a day or more: tablet off, WireGuard off, or app not opened; check it in person.
    - low battery not charging, bad battery health, low storage, wrong clock: hardware or settings,
      check in person.
  TXT

  def self.summary(tablet)
    Rails.cache.fetch(["tablet-ai", tablet.id, tablet.last_seen_at.to_i], expires_in: 30.minutes) do
      ask_model("Here is one tablet's latest report.\n\n#{brief(tablet)}\n\n" \
                "In at most 4 short bullet points: is anything wrong, and what should the technician do, " \
                "most important first? If all is well, say so in one line.", 350)
    end
  end

  def self.fleet(question)
    rows = Tablet.by_number.map { |t| brief(t, short: true) }.join("\n")
    ask_model("All tablets, one per line:\n#{rows}\n\nQuestion from a technician: #{question.to_s.first(500)}", 600)
  end

  def self.brief(t, short: false)
    issues = t.issues.map(&:last)
    parts = [
      t.label, "last seen #{t.last_seen_at ? "#{ApplicationController.helpers.time_ago_in_words(t.last_seen_at)} ago" : 'never'}",
      "#{t.manufacturer} #{t.model}, Android #{t.android_version}",
      "Demand Response #{t.app_version || '?'}", "Fixed Route #{t.fr_version || 'not installed'}",
      "battery #{t.battery['percent'] || '?'}%#{' charging' if t.battery['charging']}#{" health #{t.battery['health']}" if t.battery['health']}",
      "storage free #{t.storage['freeMB'] || '?'} MB",
      "network #{[('Wi-Fi' if t.network['wifi']), ('LTE' if t.network['cellular'])].compact.join('+').presence || 'none'}#{', VPN up' if t.network['vpn']}",
      "app says connection #{t.app_info['connection'] || '?'}",
      "last driver #{t.username || 'none'}",
      "problems: #{issues.any? ? issues.join('; ') : 'none found'}",
    ]
    unless short
      parts << "uptime #{(t.device['uptimeSec'].to_i / 3600.0).round(1)} h" if t.device["uptimeSec"]
      parts << "security patch #{t.device['securityPatch']}" if t.device["securityPatch"]
      parts << "other apps: #{Tablet::OTHER_APPS.select { |p, _| t.apps[p] }.values.join(', ').presence || 'none'}"
      parts << "hours used per day, last 7: #{t.hours_by_day(7).map(&:last).join(', ')}"
    end
    parts.join(" | ")
  end

  def self.ask_model(prompt, max_tokens)
    uri = URI("#{LLM_URL}/chat/completions")
    body = { model: LLM_MODEL, temperature: 0.2, max_tokens: max_tokens,
             messages: [{ role: "system", content: SYSTEM }, { role: "user", content: prompt }],
             chat_template_kwargs: { enable_thinking: false } }
    res = Net::HTTP.start(uri.host, uri.port, open_timeout: 5, read_timeout: 60) do |http|
      http.post(uri.path, body.to_json, "Content-Type" => "application/json")
    end
    raise "#{res.code} #{res.body.to_s.first(200)}" unless res.is_a?(Net::HTTPSuccess)
    JSON.parse(res.body).dig("choices", 0, "message", "content").to_s.strip
  rescue StandardError => e
    Rails.logger.warn("[tablet assistant] #{e.class}: #{e.message}")
    nil
  end
end

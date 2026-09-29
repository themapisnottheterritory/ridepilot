# Watches for trouble while RidePilot works, for the I.T. trouble board
# (TroubleBoard, /trouble_board). Three kinds, each counted by screen:
#
#   error    an action blew up (the person saw an error page or a failed save)
#   message  a form or dispatch refused something and said why ("Trip schedule
#            does not fit in run schedule"), on a save, not on a page view
#   slow     a page took SLOW_MS or more (help#ask and Optimize Route are slow
#            by design and not counted)
#
# No user, IP address, parameters or page contents are kept: only the screen,
# the agency, the controller action and the scrubbed message. Kept 90 days.
module TroubleWatch
  SLOW_MS = 4000
  SLOW_EXEMPT = %w[help#ask runs#optimize].freeze
  IT_EMAILS = ENV.fetch("IT_EMAILS", "philz@gcrpc.org,andrewv@gcrpc.org,ronaldm@gcrpc.org")
                 .split(",").map { |e| e.strip.downcase }.reject(&:blank?).freeze
  CONTEXT = :trouble_watch_context

  # first part of the controller path (or the page path) -> the tab or menu name
  SCREENS = {
    "dispatchers" => "Dispatch", "recurring_dispatchers" => "Dispatch (subscriptions)",
    "trips" => "Trips", "runs" => "Runs", "customers" => "Customers", "fare_accounts" => "Fare Cards",
    "drivers" => "Drivers", "vehicles" => "Vehicles", "reporting" => "Reports", "reports" => "Reports",
    "providers" => "Provider settings", "users" => "Users", "addresses" => "Addresses", "admin" => "Admin",
    "home" => "Admin", "whats_new" => "What's new", "repeating_trips" => "Subscription trips",
    "repeating_runs" => "Subscription runs", "cad_avl" => "CAD/AVL", "help" => "Ask RidePilot",
    "suggestions" => "Suggestions", "trouble_board" => "Trouble board", "api" => "Driver tablet",
    "devise" => "Sign-in", "sessions" => "Sign-in", "passwords" => "Sign-in", "fixed_runs" => "Driver tablet"
  }.freeze

  module_function

  def can_view?(user)
    return false unless user
    user.super_admin? || IT_EMAILS.include?(user.email.to_s.downcase)
  end

  def screen_for_path(path)
    parts = path.to_s.split("?").first.to_s.split("/").reject(&:blank?)
    parts.shift if parts.first =~ /\A[a-z]{2}\z/   # locale
    return nil if parts.empty?
    SCREENS[parts.first] || parts.first.humanize
  end

  def screen_for_controller(controller_path)
    first = controller_path.to_s.split("/").first
    SCREENS[first] || first.to_s.humanize
  end

  # ApplicationController wraps each request: messages found while it runs are
  # held and written at the end, outside any transaction that might roll back.
  def watch(controller)
    Thread.current[CONTEXT] = {
      provider_id: (controller.send(:current_provider)&.id rescue nil),
      action: "#{controller.controller_path}##{controller.action_name}",
      screen: screen_for_controller(controller.controller_path),
      saving: !controller.request.get? && !controller.request.head?,
      messages: []
    }
    yield
  ensure
    context = Thread.current[CONTEXT]
    Thread.current[CONTEXT] = nil
    if context
      alert = (controller.flash[:alert] rescue nil)
      context[:messages] << alert if context[:saving] && alert.is_a?(String)
      write_messages(context)
    end
  end

  # messages the person was shown, e.g. TripScheduler's reasons
  def messages(list)
    context = Thread.current[CONTEXT]
    context[:messages].concat(Array(list).map(&:to_s)) if context && context[:saving]
  end

  def validation_failed(record)
    messages(record.errors.full_messages) if record.errors.any?
  end

  # ActiveSupport::Notifications "process_action.action_controller"
  def action_processed(event)
    payload = event.payload
    controller_path = payload[:controller].to_s.underscore.sub(/_controller\z/, "")
    action = "#{controller_path}##{payload[:action]}"
    base = { screen: screen_for_controller(controller_path), action: action, provider_id: payload[:trouble_provider_id] }
    if (error = payload[:exception_object])
      return if error.is_a?(ActionController::RoutingError)
      record(base.merge(kind: "error", detail: "#{error.class}: #{error.message}"))
    elsif event.duration >= SLOW_MS && !SLOW_EXEMPT.include?(action)
      record(base.merge(kind: "slow", duration_ms: event.duration.round))
    end
  end

  def write_messages(context)
    context[:messages].map { |m| TroubleEvent.scrub(m) }.reject(&:blank?).uniq.each do |detail|
      record(kind: "message", screen: context[:screen], action: context[:action], provider_id: context[:provider_id], detail: detail)
    end
  end

  def record(attrs)
    attrs[:detail] = TroubleEvent.scrub(attrs[:detail]) if attrs[:detail]
    TroubleEvent.create!(attrs)
    prune_now_and_then
  rescue StandardError => e   # watching must never be the trouble
    Rails.logger.warn("TroubleWatch could not record #{attrs[:kind]}: #{e.class}: #{e.message}")
  end

  def prune_now_and_then
    return if @pruned_at && @pruned_at > 1.hour.ago
    @pruned_at = Time.current
    TroubleEvent.prune!
  end
end

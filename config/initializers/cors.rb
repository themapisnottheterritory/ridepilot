# Cross-Origin Resource Sharing (CORS)
#
# The RideAVL driver tablet app is a Capacitor WebView app: its origin is
# http(s)://localhost, so every call to this API is cross-origin and the WebView
# fires a preflight OPTIONS request first. The driver routes are POST/GET only
# (no OPTIONS route), so the preflight died at the router with a RoutingError and
# the app never sent the real request ("Sign in failed").
#
# rack-cors handles the preflight at the middleware level (before routing) and adds
# the response headers. The driver/booking APIs authenticate by TOKEN HEADERS, not
# cookies, so a wildcard origin is safe (no credentialed requests).
Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins "*"
    resource "/api/*",
      headers: :any,
      methods: [:get, :post, :put, :patch, :delete, :options, :head],
      credentials: false
  end
end

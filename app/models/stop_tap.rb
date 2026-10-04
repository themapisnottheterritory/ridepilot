# One stop tap from the driver tablet: when it was made, when it arrived, and where
# the tablet was (CreateStopTaps). Written alongside the tap; never stops it.
class StopTap < ActiveRecord::Base
  ACTIONS = %w[depart arrive pickup dropoff noshow].freeze
  ONLINE_WITHIN = 2.minutes

  def self.record(itin, action, params)
    return unless itin && ACTIONS.include?(action)
    at = params[:at].present? ? (Time.zone.parse(params[:at].to_s) rescue nil) : nil
    lat = Float(params[:lat], exception: false)
    lon = Float(params[:lon], exception: false)
    lat = lon = nil unless lat && lon && lat.between?(25, 37) && lon.between?(-107, -93)
    acc = Float(params[:accuracy], exception: false)
    fix = lat && params[:fix_at].present? ? (Time.zone.parse(params[:fix_at].to_s) rescue nil) : nil
    create!(itinerary_id: itin.id, action: action, tapped_at: at, received_at: Time.current,
            latitude: lat, longitude: lon, accuracy_m: acc&.round&.clamp(0, 100_000), fix_at: fix,
            app_version: params[:app].to_s.first(20).presence)
  rescue StandardError => e
    Rails.logger.warn("[stop tap] #{e.class}")
    nil
  end

  # Seconds between the GPS fix and the tap; nil when either time is missing.
  def fix_age = (fix_at && tapped_at) ? (tapped_at - fix_at).abs : nil

  # The tablet's position counts only from a good fix taken close enough to the tap.
  def position_within?(seconds, accuracy: 50) = latitude.present? && accuracy_m.to_i.between?(1, accuracy) && fix_age.to_i <= seconds && !fix_age.nil?

  # Made online: the app gave its tap time and it arrived within two minutes.
  def online? = tapped_at.present? && (received_at - tapped_at).abs <= ONLINE_WITHIN
end

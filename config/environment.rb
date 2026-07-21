# Load the Rails application.
require_relative "application"

Rails.application.routes.default_url_options[:host] = ENV['RIDEPILOT_HOST']

I18n.available_locales = ["en"]

TRIP_VERIFICATION_DISPLAY_OPTIONS = ["All Trips", "Cab Trips", "Not Cab Trips"].freeze

BUSINESS_HOURS = {
  :start => 0,
  :end => 24,
}.freeze

PER_PAGE = 30

STATE_NAME_TO_POSTAL_ABBREVIATION = {
  "ALABAMA" => "AL",
  "ALASKA" => "AK",
  "AMERICAN SAMOA" => "AS",
  "ARIZONA" => "AZ",
  "ARKANSAS" => "AR",
  "CALIFORNIA" => "CA",
  "COLORADO" => "CO",
  "CONNECTICUT" => "CT",
  "DELAWARE" => "DE",
  "DISTRICT OF COLUMBIA" => "DC",
  "FEDERATED STATES O MICRONESIA" => "FM",
  "FLORIDA" => "FL",
  "GEORGIA" => "GA",
  "GUAM" => "GU",
  "HAWAII" => "HI",
  "IDAHO" => "ID",
  "ILLINOIS" => "IL",
  "INDIANA" => "IN",
  "IOWA" => "IA",
  "KANSAS" => "KS",
  "KENTUCKY" => "KY",
  "LOUISIANA" => "LA",
  "MAINE" => "ME",
  "MARSHALL ISLANDS" => "MH",
  "MARYLAND" => "MD",
  "MASSACHUSETTS" => "MA",
  "MICHIGAN" => "MI",
  "MINNESOTA" => "MN",
  "MISSISSIPPI" => "MS",
  "MISSOURI" => "MO",
  "MONTANA" => "MT",
  "NEBRASKA" => "NE",
  "NEVADA" => "NV",
  "NEW HAMPSHIRE" => "NH",
  "NEW JERSEY" => "NJ",
  "NEW MEXICO" => "NM",
  "NEW YORK" => "NY",
  "NORTH CAROLINA" => "NC",
  "NORTH DAKOTA" => "ND",
  "NORTHERN MARIANA ISLANDS" => "MP",
  "OHIO" => "OH",
  "OKLAHOMA" => "OK",
  "OREGON" => "OR",
  "PALAU" => "PW",
  "PENNSYLVANIA" => "PA",
  "PUERTO RICO" => "PR",
  "RHODE ISLAND" => "RI",
  "SOUTH CAROLINA" => "SC",
  "SOUTH DAKOTA" => "SD",
  "TENNESSEE" => "TN",
  "TEXAS" => "TX",
  "UTAH" => "UT",
  "VERMONT" => "VT",
  "VIRGIN ISLANDS" => "VI",
  "VIRGINIA" => "VA",
  "WASHINGTON" => "WA",
  "WEST VIRGINIA" => "WV",
  "WISCONSIN" => "WI",
  "WYOMING" => "WY"
}.freeze

GOOGLE_MAP_DEFAULTS = {
  bounds: {
    north: 42.0,
    west:  -114.0,
    south: 37.0,
    east:  -109.0    
  },
  viewport: {
    center_lat: 40.77,
    center_lng: -111.9,
    zoom: 11
  }
}.freeze


# Initialize the Rails application.
Rails.application.initialize!

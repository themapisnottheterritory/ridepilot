# Be sure to restart your server when you modify this file.

# Version of your assets, change this if you want to expire all your assets.
Rails.application.config.assets.version = "1.0"

# Fix for Sprockets 4 compatibility with gems using regex in precompile
# Some older gems (like bootstrap-editable-rails) register assets with regex patterns
# which are not compatible with Sprockets 4's stricter URI validation
# Must run after_initialize because gems add their patterns during initialization
Rails.application.config.after_initialize do
  Rails.application.config.assets.precompile.reject! { |entry| entry.is_a?(Regexp) }
end

# Add additional assets to the asset load path.
# Rails.application.config.assets.paths << Emoji.images_path

# Precompile additional assets.
# application.js, application.css, and all non-JS/CSS in app/assets folder are already added.
Rails.application.config.assets.precompile += %w( leaflet_map.js leaflet.js leaflet.markercluster.js leaflet.rotatedMarker.js leaflet.css MarkerCluster.css MarkerCluster.Default.css jquery.jstree.js jquery.layout.js dispatcher.js jstree-apple/* jquery-layout-default.css *.png v1_theme.css v1_theme_split2.css reports_print.css pdf.css)

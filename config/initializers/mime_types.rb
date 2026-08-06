# Be sure to restart your server when you modify this file.

# Add new mime types for use in respond_to blocks:
# Mime::Type.register "text/richtext", :rtf

# Reports respond to :xlsx (see ReportsController#apply_v2_response). Rails does
# not register xlsx by default, so without this every V2 report 500s while
# building its respond_to block ("register it as a MIME type first") — even for
# an html request.
Mime::Type.register "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", :xlsx

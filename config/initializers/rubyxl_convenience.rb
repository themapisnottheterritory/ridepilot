# RubyXL 3.x moved its convenience API -- Cell#change_contents, Worksheet#add_cell,
# Workbook#stream, the [] accessors, etc. -- into a separate require. The app uses
# these (NtdReport builds the NTD workbook with change_contents; ReportsController
# streams it via @workbook.stream) but only did `require 'rubyXL'`, so
# change_contents raised NoMethodError and the NTD xlsx export 500'd.
#
# Load the convenience methods so RubyXL exposes the pre-3.x API app-wide.
require 'rubyXL'
require 'rubyXL/convenience_methods'

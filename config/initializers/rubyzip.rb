# Excel files are zips. rubyzip 3 writes them as ZIP64 by default, which
# LibreOffice 6.x (and older Excel) refuse to open ("source file could not be
# loaded"); none of our files come near ZIP64's 4 GB limit (2026-10-01).
require "zip"
Zip.write_zip64_support = false

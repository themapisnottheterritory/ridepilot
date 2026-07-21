begin
  require 'wicked_pdf'
  
  # WickedPDF Global Configuration
  WickedPdf.config = {
    # Path to the wkhtmltopdf executable: This usually isn't needed if using
    # one of the wkhtmltopdf-binary family of gems.
    # exe_path: '/usr/local/bin/wkhtmltopdf',
    
    # Layout file to be used for all PDFs
    layout: 'pdf.html', 
    orientation: 'Landscape'     
  }
rescue LoadError => e
  # WickedPdf not available
  puts "WickedPdf not available: #{e.message}"
end
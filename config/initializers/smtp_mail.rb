
# No SMTP_MAIL_USER_NAME -> no login: GCRPC's internal relay (10.0.0.10) is open
# and rejects credentials, and a blank ENV value would otherwise still log in.
smtp_user = ENV['SMTP_MAIL_USER_NAME'].presence
ActionMailer::Base.smtp_settings = {
  :address              => ENV['SMTP_MAIL_ADDR'],
  :port                 => ENV['SMTP_MAIL_PORT'],
  :domain               => ENV['SMTP_MAIL_DOMAIN'],
  :user_name            => smtp_user,
  :password             => smtp_user && ENV['SMTP_MAIL_PASSWORD'].presence,
  :authentication       => (smtp_user ? 'plain' : nil),
  :enable_starttls_auto => 'true',
  :openssl_verify_mode => 'none'
}

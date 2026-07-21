Paperclip::Attachment.default_options[:hash_secret] = Rails.application.secrets.secret_key_base

if Rails.env.test?
  Paperclip::Attachment.default_options[:storage] = :filesystem
  Paperclip::Attachment.default_options[:path]    = ":rails_root/tmp/test_files/:class/:attachment/:id/:style/:filename"
elsif ENV['AWS_REGION'] && ENV['AWS_KEY_ID'] && ENV['AWS_ACCESS_KEY']
  Paperclip::Attachment.default_options[:storage] = :fog
  Paperclip::Attachment.default_options[:fog_credentials] = {
    provider: 'AWS',
    aws_access_key_id: ENV['AWS_KEY_ID'],
    aws_secret_access_key: ENV['AWS_ACCESS_KEY'],
    region: ENV['AWS_REGION'],
    scheme: 'https'
  }
  Paperclip::Attachment.default_options[:fog_directory] = ENV['AWS_BUCKET']
  Paperclip::Attachment.default_options[:fog_file] = {
    'Cache-Control' => 'max-age=315576000',
    'Expires'       => 10.years.from_now.httpdate
  }
else
  Paperclip::Attachment.default_options[:storage] = :filesystem
end
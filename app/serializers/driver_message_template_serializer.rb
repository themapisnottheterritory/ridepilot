class DriverMessageTemplateSerializer
  include FastJsonapi::ObjectSerializer
  set_type :driver_message_template

  attribute :id, :message
end

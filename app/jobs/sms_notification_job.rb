class SmsNotificationJob < ApplicationJob
  queue_as :default
  retry_on StandardError, wait: 2.minutes, attempts: 3

  def perform(customer_id, template, **vars)
    customer = Customer.find(customer_id)
    SmsNotificationService.send_notification(customer: customer, template: template.to_sym, **vars)
  end
end

class Message < ApplicationRecord
  belongs_to :provider
  belongs_to :sender, class_name: 'User', foreign_key: :sender_id
  belongs_to :reader, class_name: 'User', foreign_key: :reader_id, optional: true
  belongs_to :driver
  belongs_to :run

  scope :for_today, -> { where(created_at: Date.today.beginning_of_day..Date.today.end_of_day) }
end

class Message < ApplicationRecord
  belongs_to :provider
  belongs_to :sender, class_name: 'User', foreign_key: :sender_id
  belongs_to :reader, class_name: 'User', foreign_key: :reader_id, optional: true
  belongs_to :handled_by, class_name: 'User', foreign_key: :handled_by_id, optional: true
  belongs_to :driver
  belongs_to :run

  # "Today" in Central time; Date.today is the server's (UTC) date, which
  # dropped the evening's messages at 7 PM.
  scope :for_today, -> { where(created_at: Time.zone.now.all_day) }

  # Written by the driver (from the tablet), not by a dispatcher.
  scope :from_drivers, -> { joins(:driver).where("messages.sender_id = drivers.user_id") }
  scope :unhandled, -> { where(handled_at: nil) }

  def from_driver?
    driver.present? && sender_id == driver.user_id
  end

  # The driver's run today: the one the tablet named, else the started and
  # unfinished one, else any run today. A message can't be saved without a run.
  def self.run_for(driver, run_id = nil)
    return nil unless driver
    Run.find_by(id: run_id, driver_id: driver.id) ||
      Run.where(driver_id: driver.id, date: Time.zone.today).where.not(start_odometer: nil).where(end_odometer: nil).first ||
      Run.where(driver_id: driver.id, date: Time.zone.today).first
  end
end

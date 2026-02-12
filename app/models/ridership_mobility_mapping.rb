class RidershipMobilityMapping < ApplicationRecord
  after_initialize :set_defaults
  belongs_to :mobility, optional: true

  validates :capacity, presence: true, 
                    numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :default_order, -> { joins(:mobility).order("mobilities.name") }

  scope :has_capacity, -> { where("capacity > 0") }

  RIDERSHIP_LIST = {
    1 => 'Customer',
    2 => 'Guest',
    3 => 'Attendant',
    4 => 'Service Animal'
  }


  private

  def set_defaults
    self.capacity = 0 if self.capacity.blank?
  end
end

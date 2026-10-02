class AddressGroup < ApplicationRecord

  validates :name, uniqueness: { case_insensitive: true }, presence: true

  normalize_attribute :name, :with => [ :strip ]

  # Saved places are shared by everyone; a rider's home goes on the rider (Philz 2026-10-02).
  validate do
    if HomeAddressCheck.home_name?(name)
      errors.add(:name, "can't be a home: a rider's home goes on the rider's record (Customers, the rider, Addresses)")
    end
  end

  UNKNOWN_TYPE = 'Needs Update'

  def self.default_address_group
    find_by_name UNKNOWN_TYPE
  end
end

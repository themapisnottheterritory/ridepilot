class CustomerCommonAddress < Address

  #validates :customer, presence: true

  # A rider's home pinned or moved: their trips' area follows (ServiceArea).
  after_save :retag_service_area, if: :saved_change_to_the_geom?

  def retag_service_area
    c = customer_id && Customer.find_by(id: customer_id, address_id: id)
    ServiceArea.retag_upcoming!(c) if c
  rescue StandardError => e
    Rails.logger.warn("[service area] address #{id}: #{e.class}: #{e.message}")
  end
end

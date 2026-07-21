class AddProviderIdToFundingSources < ActiveRecord::Migration[4.2]
  def change
    add_reference :funding_sources, :provider, index: true
  end
end

require "rails_helper"

# The customer form sends the rider's addresses as a list. Before 2026-10-06
# editing an address's street in the dialog added a second row for the same
# address, so the list held it twice; saving wrote it twice and the second
# write failed (StaleObjectError, customer 80340, five tries on 2026-10-05).
RSpec.describe Customer, "#edit_addresses" do
  let(:customer) { create(:customer) }
  let!(:home) do
    CustomerCommonAddress.create!(customer: customer, provider: customer.provider, name: "Home", address: "510 S Front St",
                                  city: "Hallettsville", state: "TX", zip: "77964", the_geom: Address.compute_geom(29.4436, -96.9411))
  end
  let!(:clinic) do
    CustomerCommonAddress.create!(customer: customer, provider: customer.provider, name: "Clinic", address: "100 N Main St",
                                  city: "Hallettsville", state: "TX", zip: "77964", the_geom: Address.compute_geom(29.4440, -96.9420))
  end

  # what the page sends for an address row
  def row(address, changes = {})
    JSON.parse(address.as_json.to_json, symbolize_names: true).merge(changes)
  end

  it "saves an address listed twice once, with the edited copy" do
    list = [row(home), row(clinic), row(home, address: "510 South Front Street", phone_number: "")]
    customer.edit_addresses(list, 0)
    customer.save!
    expect(home.reload.address).to eq "510 South Front Street"
    expect(home.lock_version).to eq 1
    expect(customer.reload.address).to eq home
    expect(customer.addresses.where(deleted_at: nil)).to contain_exactly(home, clinic)
  end

  it "keeps the mailing address when the edited copy is the one ticked" do
    list = [row(home), row(clinic), row(home, address: "510 South Front Street")]
    customer.edit_addresses(list, 2)
    customer.save!
    expect(customer.reload.address).to eq home
  end

  it "still refuses an address someone else changed since the page opened" do
    stale = row(home, address: "510 South Front Street")
    home.update!(notes: "gate code 1234")   # another person's save
    expect { customer.edit_addresses([stale, row(clinic)], 0) }.to raise_error(ActiveRecord::StaleObjectError)
  end
end

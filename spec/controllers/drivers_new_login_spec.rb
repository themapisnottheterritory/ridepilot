require "rails_helper"

RSpec.describe DriversController, "create a login for this driver", type: :controller do
  login_admin_as_current_user
  let(:provider) { @current_user.current_provider }

  def driver_attrs(new_user)
    attributes_for(:driver, phone_number: '(801)4567890').merge(
      address_attributes: attributes_for(:driver_address, provider_id: provider.id),
      new_user: new_user
    )
  end

  it "creates the user, the role and the driver together and shows the password once" do
    expect {
      post :create, params: { driver: driver_attrs(mode: "new", first_name: "Elmer", last_name: "Street", username: "", email: "") }
    }.to change(Driver, :count).by(1).and change(User, :count).by(1)
    driver = Driver.last
    user = driver.user
    expect(user.username).to eq "elmers"
    expect(user.email).to eq "elmers@drivers.gcrpc.org"
    expect(user.first_name).to eq "Elmer"
    expect(driver.name).to eq user.name
    expect(user.current_provider).to eq provider
    expect(user.roles.where(provider: provider).first.level).to eq Role::USER_LEVEL
    expect(flash[:driver_password]).to be_present
    expect(user.valid_password?(flash[:driver_password])).to be true
    expect(response).to redirect_to(driver_path(driver))
  end

  it "keeps a typed username and a real email" do
    post :create, params: { driver: driver_attrs(mode: "new", first_name: "Thalia", last_name: "Acosta", username: "TAcosta", email: "thalia@example.com") }
    user = Driver.last.user
    expect(user.username).to eq "tacosta"
    expect(user.email).to eq "thalia@example.com"
  end

  it "picks the next free username when the convention collides" do
    create(:user, username: "elmers", email: "x@example.com")
    post :create, params: { driver: driver_attrs(mode: "new", first_name: "Elmer", last_name: "Street") }
    expect(Driver.last.user.username).to eq "elmers2"
  end

  it "saves nothing when the user is invalid" do
    expect {
      post :create, params: { driver: driver_attrs(mode: "new", first_name: "", last_name: "Street") }
    }.not_to change(Driver, :count)
    expect(User.where(last_name: "Street")).to be_empty
    expect(response).to render_template(:new)
  end

  it "still accepts an existing login" do
    user = create(:user, current_provider: provider)
    create(:role, user: user, provider: provider, level: Role::USER_LEVEL)
    post :create, params: { driver: driver_attrs(mode: "existing").merge(user_id: user.id) }
    expect(Driver.last.user).to eq user
    expect(User.count).to eq User.count   # no new user
  end

  it "resets the tablet password from the driver page" do
    post :create, params: { driver: driver_attrs(mode: "new", first_name: "Elmer", last_name: "Street") }
    driver = Driver.last
    old = flash[:driver_password]
    post :reset_password, params: { id: driver.id }
    expect(response).to redirect_to(driver_path(driver))
    expect(flash[:driver_password]).to be_present
    expect(flash[:driver_password]).not_to eq old
    expect(driver.user.reload.valid_password?(flash[:driver_password])).to be true
  end
end

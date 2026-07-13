require "rails_helper"

RSpec.describe Driver, type: :model do

  it "requires a provider" do
    driver = build :driver, provider: nil
    expect(driver.valid?).to be_falsey
    expect(driver.errors.keys).to include :provider
  end

  it "requires a user" do
    driver = build :driver, user: nil
    expect(driver.valid?).to be_falsey
    expect(driver.errors.keys).to include :user
  end

  it "cannot be linked to the same user as another driver" do
    driver_1 = create :driver
    driver_2 = build :driver, user: driver_1.user
    expect(driver_2.valid?).to be_falsey
    expect(driver_2.errors.keys).to include :user_id

    driver_2.user = create :user
    expect(driver_2.valid?).to be_truthy
  end

  it "must have a valid email when specified" do
    driver = build :driver, email: "m@"
    expect(driver.valid?).to be_falsey
    expect(driver.errors.keys).to include :email

    driver.email = "m@m.m"
    expect(driver.valid?).to be_truthy
  end

  it "can find drivers for a given provider" do
    driver_1 = create :driver
    driver_2 = create :driver
    drivers = Driver.for_provider driver_1.provider
    expect(drivers).to include driver_1
    expect(drivers).not_to include driver_2
  end

  it "can find drivers who are not assigned to a device pool" do
    provider = create :provider
    driver_1 = create :driver, provider: provider
    driver_2 = create :driver, provider: provider
    create :device_pool_driver, driver: driver_1, device_pool: create(:device_pool, provider: provider)
    unassigned = Driver.unassigned provider
    expect(unassigned).not_to include driver_1
    expect(unassigned).to include driver_2
  end

  describe "available?" do
    before do
      @driver = create :driver
      @day_of_week = 0
      @date = Date.today.sunday
      @time_of_day = "15:30"
    end

    it "returns false if no operating hours are defined" do
      expect(@driver.available?).to be_falsey
    end

    it "returns false if operating hours are defined, but not for that day" do
      create :operating_hour, operatable: @driver, day_of_week: @day_of_week 
      expect(@driver.available?(@date + 1.day, @time_of_day)).to be_falsey
    end

    it "returns true if the driver is available 24 hours" do
      create :operating_hour, operatable: @driver, day_of_week: @day_of_week, is_all_day: true
      expect(@driver.available?(@date, @time_of_day)).to be_truthy
    end

    it "returns false if the driver is not available that day" do
      create :operating_hour, operatable: @driver, day_of_week: @day_of_week, is_unavailable: true
      expect(@driver.available?(@date, @time_of_day)).to be_falsey
    end

    it "can check against regular hours" do
      hours = create :operating_hour, operatable: @driver, day_of_week: @day_of_week, start_time: "12:00", end_time: "16:00"
      expect(@driver.available?(@date, @time_of_day)).to be_truthy

      hours.update end_time: "15:00"
      expect(@driver.available?(@date, @time_of_day)).to be_falsey
    end
  end

  describe "driver_histories" do
    before do
      @driver = create :driver
    end

    it "destroys driver histories when the driver is destroyed" do
      3.times { create :driver_history, driver: @driver }
      expect {
        @driver.destroy
      }.to change(DriverHistory, :count).by(-3)
    end
  end

  describe "driver_compliances" do
    before do
      @driver = create :driver
    end

    it "destroys driver compliances when the driver is destroyed" do
      3.times { create :driver_compliance, driver: @driver }
      expect {
        @driver.destroy
      }.to change(DriverCompliance, :count).by(-3)
    end
  end

  describe "compliant?" do
    before do
      @driver = create :driver
    end

    it "returns true when a driver has no compliance entries" do
      expect(@driver.compliant?).to be_truthy
    end

    it "returns true when a driver's compliance entries are all complete" do
      create :driver_compliance, driver: @driver, due_date: Date.current.yesterday, compliance_date: Date.current
      expect(@driver.compliant?).to be_truthy
    end

    it "returns true when a driver's incomplete compliance entries are all due in the future" do
      create :driver_compliance, driver: @driver, due_date: Date.current.tomorrow
      expect(@driver.compliant?).to be_truthy
    end

    it "returns false when a driver has over due compliance entries" do
      create :driver_compliance, driver: @driver, due_date: Date.current.yesterday
      expect(@driver.compliant?).to be_falsey
    end
  end

  describe "documents" do
    before do
      @driver = create :driver
    end

    it "destroys documents when the driver is destroyed" do
      3.times { create :document, documentable: @driver }
      expect {
        @driver.destroy
      }.to change(Document, :count).by(-3)
    end
  end

  describe "driver hours" do

    # Set time to a Wednesday to avoid spec weirdness with the beginning of the week.
    before do
      Timecop.freeze(Time.parse("2017-05-10 16:00").in_time_zone)
    end

    after do
      Timecop.return
    end

    it 'returns total completed run hours for the week' do

      driver = create(:driver)
      complete_run_yesterday = create(:run, :completed, :yesterday, driver: driver)
      complete_run_two_days_ago = create(:run, :completed, :two_days_ago, driver: driver)
      complete_run_last_week = create(:run, :completed, :last_week, driver: driver)
      incomplete_run_today = create(:run, :scheduled_morning, driver: driver)
      incomplete_run_next_week = create(:run, :scheduled_morning, :next_week, driver: driver)

      # Only the completed runs this week should add to the hours
      expect(driver.run_hours).to eq(
        case Date.today.in_time_zone.wday
        when 1
          0
        when 2
          complete_run_yesterday.hours_scheduled
        else
          complete_run_yesterday.hours_scheduled + complete_run_two_days_ago.hours_scheduled
        end
      )
    end

  end

end

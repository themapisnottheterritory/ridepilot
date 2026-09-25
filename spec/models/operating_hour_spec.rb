require 'rails_helper'

RSpec.describe OperatingHour, type: :model do
  it "requires a day of the week" do
    hours = build :operating_hour, day_of_week: nil
    expect(hours.valid?).to be_falsey
    expect(hours.errors.attribute_names).to include :day_of_week
  end

  it "requires a operatable object" do
    hours = build :operating_hour, operatable: nil
    expect(hours.valid?).to be_falsey
    expect(hours.errors.attribute_names).to include :operatable
  end
  
  it "orders records by day_of_week" do
    hours_5 = create :operating_hour, day_of_week: 5
    hours_1 = create :operating_hour, day_of_week: 1
    hours_3 = create :operating_hour, day_of_week: 3
    hours_0 = create :operating_hour, day_of_week: 0
    
    expect(OperatingHour.all.to_a).to eql [hours_0, hours_1, hours_3, hours_5]
  end
  
  it "does not allow overnight hours" do
    hours = build :operating_hour, start_time: "01:00", end_time: "00:59"
    expect(hours.valid?).to be_falsey
    expect(hours.errors.attribute_names).to include :end_time

    hours.end_time = "00:00"
    expect(hours.valid?).to be_truthy
  end
  
  it "can be unavailable" do
    hours = build :operating_hour, is_unavailable: true
    expect(hours.valid?).to be_truthy
    expect(hours.is_unavailable?).to be_truthy
  end
  
  it "can be available 24 hours" do
    hours = build :operating_hour, is_all_day: true
    expect(hours.valid?).to be_truthy
    expect(hours.is_all_day?).to be_truthy
  end
  
  it "can make itself unavailable" do
    hours = build :operating_hour
    expect(hours.is_unavailable?).to be_falsey
    hours.make_unavailable
    expect(hours.is_unavailable?).to be_truthy
  end
  
  it "can make itself available 24 hours" do
    hours = build :operating_hour
    expect(hours.is_all_day?).to be_falsey
    hours.make_all_day
    expect(hours.is_all_day?).to be_truthy
  end
  
  it "defines START_OF_DAY as string representation of 00:00 am" do
    expect(OperatingHour::START_OF_DAY).to be_a String
    expect(Time.zone.parse(OperatingHour::START_OF_DAY).hour).to eq 0
    expect(Time.zone.parse(OperatingHour::START_OF_DAY).min).to eq 0
  end

  describe ".available_start_times" do
    before do
      @start_times = OperatingHour.available_start_times
    end
      
    it "returns an array" do
      expect(@start_times).to be_an Array
    end
    
    it "contains time values as strings" do
      expect(@start_times.first).to be_a String
    end
    
    it "starts at 00:00 am" do
      expect(@start_times.first).to eq "00:00:00"
    end

    it "defaults to 30 minute intervals" do
      expect(Time.zone.parse(@start_times.second) - Time.zone.parse(@start_times.first)).to eq 30.minutes
    end
  
    it "can accept an optional interval argument" do
      times = OperatingHour.available_start_times(interval: 1.hour)
      expect(Time.zone.parse(times.second) - Time.zone.parse(times.first)).to eq 1.hour
    end
        
    it "ends at 00:00am" do
      expect(@start_times.last).to eq "00:00:00"
    end
  end
  
  describe ".available_end_times" do
    before do
      @end_times = OperatingHour.available_end_times
    end
      
    it "returns an array" do
      expect(@end_times).to be_an Array
    end

    it "contains time values as strings" do
      expect(@end_times[0]).to be_a String
    end
    
    it "starts at 00:00 am" do
      expect(@end_times.first).to eq "00:00:00"
    end

    it "defaults to 30 minute intervals" do
      expect(Time.zone.parse(@end_times.second) - Time.zone.parse(@end_times.first)).to eq 30.minutes
    end
  
    it "can accept an optional interval argument" do
      times = OperatingHour.available_end_times(interval: 1.hour)
      expect(Time.zone.parse(times.second) - Time.zone.parse(times.first)).to eq 1.hour
    end
        
    it "ends at 00:00am by default, which is the midnight" do
      expect(@end_times.last).to eq "00:00:00"
      expect(@end_times).to include "00:00:00"
    end
  end
end

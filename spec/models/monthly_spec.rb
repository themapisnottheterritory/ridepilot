require "rails_helper"

RSpec.describe Monthly do
  describe "provider_id" do
    it "should be an integer field" do
      m = Monthly.new
      expect(m).to respond_to(:provider_id)
      m.provider_id = "1"
      expect(m.provider_id).to eq 1
      m.provider_id = "0"
      expect(m.provider_id).to eq 0
    end
  end

  describe "funding_source_id" do
    it "should be an integer field" do
      m = Monthly.new
      expect(m).to respond_to(:funding_source_id)
      m.funding_source_id = "1"
      expect(m.funding_source_id).to eq 1
      m.funding_source_id = "0"
      expect(m.funding_source_id).to eq 0
    end
  end

  describe "start_date" do
    it "should be a date field" do
      m = Monthly.new
      expect(m).to respond_to(:start_date)
      m.start_date = "1"
      expect(m.start_date).to be_nil
      m.start_date = "2013-06-01"
      expect(m.start_date).to eq Date.new(2013, 6, 1)
    end
  end

  describe "volunteer_admin_hours" do
    it "should be an integer" do
      m = Monthly.new
      expect(m).to respond_to(:volunteer_admin_hours)
      m.volunteer_admin_hours = "1"
      expect(m.volunteer_admin_hours).to eq 1
      m.volunteer_admin_hours = "0"
      expect(m.volunteer_admin_hours).to eq 0
    end
    
    it "should only allow integers greater than or equal to 0" do
      m = Monthly.new
      m.volunteer_admin_hours = -1
      m.valid?
      expect(m.errors.attribute_names.include?(:volunteer_admin_hours)).to be_truthy
      expect(m.errors[:volunteer_admin_hours]).to include "must be greater than or equal to 0"
      
      m.volunteer_admin_hours = 0
      m.valid?
      expect(m.errors.attribute_names.include?(:volunteer_admin_hours)).not_to be_truthy
    end
  end

  describe "volunteer_escort_hours" do
    it "should be an integer" do
      m = Monthly.new
      expect(m).to respond_to(:volunteer_escort_hours)
      m.volunteer_escort_hours = "1"
      expect(m.volunteer_escort_hours).to eq 1
      m.volunteer_escort_hours = "0"
      expect(m.volunteer_escort_hours).to eq 0
    end
    
    it "should only allow integers greater than or equal to 0" do
      m = Monthly.new
      m.volunteer_escort_hours = -1
      m.valid?
      expect(m.errors.attribute_names.include?(:volunteer_escort_hours)).to be_truthy
      expect(m.errors[:volunteer_escort_hours]).to include "must be greater than or equal to 0"
      
      m.volunteer_escort_hours = 0
      m.valid?
      expect(m.errors.attribute_names.include?(:volunteer_escort_hours)).not_to be_truthy
    end
  end
  
  describe "uniqueness" do
    before do
      @p1 = create :provider
      @p2 = create :provider
      
      @f1 = create(:funding_source, name: "FS1")
      @f2 = create(:funding_source, name: "FS2")
    end
    
    it "should validate start_date uniqueness based on provider_id and funding_source_id" do
      start_date = Date.today
      m1 = Monthly.new(start_date: start_date, provider: @p1, funding_source: @f1, volunteer_escort_hours: 0, volunteer_admin_hours: 0)
      expect(m1.save).to be_truthy
      
      m2 = Monthly.new(start_date: start_date, provider: @p1, funding_source: @f1, volunteer_escort_hours: 0, volunteer_admin_hours: 0)
      expect(m2.valid?).to be_falsey
      expect(m2.errors.attribute_names).to include(:start_date)
      expect(m2.errors[:start_date]).to include "has already been used for the given provider and funding source"
      
      m2.provider = @p2
      m2.funding_source = @f1
      expect(m2.valid?).to be_truthy
      expect(m2.errors.attribute_names).not_to include(:start_date)
      
      m2.provider = @p1
      m2.funding_source = @f2
      expect(m2.valid?).to be_truthy
      expect(m2.errors.attribute_names).not_to include(:start_date)
      
      m2.provider = @p1
      m2.funding_source = @f1
      m2.start_date = start_date + 1.day
      expect(m2.valid?).to be_truthy
      expect(m2.errors.attribute_names).not_to include(:start_date)
      
      expect(m2.save).to be_truthy
    end
  end
end
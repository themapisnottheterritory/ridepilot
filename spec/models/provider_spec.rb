require "rails_helper"

RSpec.describe Provider do
  describe "#fields_required_for_run_completion" do
    it "is a serialized text field" do
      provider = build :provider
      expect(provider.fields_required_for_run_completion).to be_an Array
    end
  end
  
  describe "reimbursement rates" do
    describe "oaa3b_per_ride_reimbursement_rate" do
      it "should be an integer field" do
        p = build(:provider)
        expect(p).to respond_to(:oaa3b_per_ride_reimbursement_rate)
        p.oaa3b_per_ride_reimbursement_rate = "1"
        expect(p.oaa3b_per_ride_reimbursement_rate).to eq 1.0
        p.oaa3b_per_ride_reimbursement_rate = "0.12"
        expect(p.oaa3b_per_ride_reimbursement_rate).to eq 0.12
      end
    
      it "should only allow values greater than 0" do
        p = build(:provider, :oaa3b_per_ride_reimbursement_rate => 0)
        expect(p.valid?).to_not be_truthy
        expect(p.errors.attribute_names.include?(:oaa3b_per_ride_reimbursement_rate)).to be_truthy
        expect(p.errors[:oaa3b_per_ride_reimbursement_rate]).to include "must be greater than 0"
      
        p.oaa3b_per_ride_reimbursement_rate = 1
        expect(p.valid?).to be_truthy
        expect(p.errors.attribute_names.include?(:oaa3b_per_ride_reimbursement_rate)).not_to be_truthy
      end
    end

    describe "ride_connection_per_ride_reimbursement_rate" do
      it "should be an integer field" do
        p = build(:provider)
        expect(p).to respond_to(:ride_connection_per_ride_reimbursement_rate)
        p.ride_connection_per_ride_reimbursement_rate = "1"
        expect(p.ride_connection_per_ride_reimbursement_rate).to eq 1.0
        p.ride_connection_per_ride_reimbursement_rate = "0.12"
        expect(p.ride_connection_per_ride_reimbursement_rate).to eq 0.12
      end
    
      it "should only allow values greater than 0" do
        p = build(:provider, :ride_connection_per_ride_reimbursement_rate => 0)
        expect(p.valid?).to_not be_truthy
        expect(p.errors.attribute_names.include?(:ride_connection_per_ride_reimbursement_rate)).to be_truthy
        expect(p.errors[:ride_connection_per_ride_reimbursement_rate]).to include "must be greater than 0"
      
        p.ride_connection_per_ride_reimbursement_rate = 1
        expect(p.valid?).to be_truthy
        expect(p.errors.attribute_names.include?(:ride_connection_per_ride_reimbursement_rate)).not_to be_truthy
      end
    end

    describe "trimet_per_ride_reimbursement_rate" do
      it "should be an integer field" do
        p = build(:provider)
        expect(p).to respond_to(:trimet_per_ride_reimbursement_rate)
        p.trimet_per_ride_reimbursement_rate = "1"
        expect(p.trimet_per_ride_reimbursement_rate).to eq 1.0
        p.trimet_per_ride_reimbursement_rate = "0.12"
        expect(p.trimet_per_ride_reimbursement_rate).to eq 0.12
      end
    
      it "should only allow values greater than 0" do
        p = build(:provider, :trimet_per_ride_reimbursement_rate => 0)
        expect(p.valid?).to_not be_truthy
        expect(p.errors.attribute_names.include?(:trimet_per_ride_reimbursement_rate)).to be_truthy
        expect(p.errors[:trimet_per_ride_reimbursement_rate]).to include "must be greater than 0"
      
        p.trimet_per_ride_reimbursement_rate = 1
        expect(p.valid?).to be_truthy
        expect(p.errors.attribute_names.include?(:trimet_per_ride_reimbursement_rate)).not_to be_truthy
      end
    end

    describe "stf_van_per_ride_reimbursement_rate" do
      it "should be an integer field" do
        p = build(:provider)
        expect(p).to respond_to(:stf_van_per_ride_reimbursement_rate)
        p.stf_van_per_ride_reimbursement_rate = "1"
        expect(p.stf_van_per_ride_reimbursement_rate).to eq 1.0
        p.stf_van_per_ride_reimbursement_rate = "0.12"
        expect(p.stf_van_per_ride_reimbursement_rate).to eq 0.12
      end
    
      it "should only allow values greater than 0" do
        p = build(:provider)
        p.stf_van_per_ride_reimbursement_rate = 0
        expect(p.valid?).to_not be_truthy
        expect(p.errors.attribute_names.include?(:stf_van_per_ride_reimbursement_rate)).to be_truthy
        expect(p.errors[:stf_van_per_ride_reimbursement_rate]).to include "must be greater than 0"
      
        p.stf_van_per_ride_reimbursement_rate = 1
        expect(p.valid?).to be_truthy
        expect(p.errors.attribute_names.include?(:stf_van_per_ride_reimbursement_rate)).not_to be_truthy
      end
    end

    describe "stf_taxi_per_ride_administrative_fee" do
      it "should be an integer field" do
        p = build(:provider)
        expect(p).to respond_to(:stf_taxi_per_ride_administrative_fee)
        p.stf_taxi_per_ride_administrative_fee = "1"
        expect(p.stf_taxi_per_ride_administrative_fee).to eq 1.0
        p.stf_taxi_per_ride_administrative_fee = "0.12"
        expect(p.stf_taxi_per_ride_administrative_fee).to eq 0.12
      end
    
      it "should only allow values greater than 0" do
        p = build(:provider, :stf_taxi_per_ride_administrative_fee => 0)
        expect(p.valid?).to_not be_truthy
        expect(p.errors.attribute_names.include?(:stf_taxi_per_ride_administrative_fee)).to be_truthy
        expect(p.errors[:stf_taxi_per_ride_administrative_fee]).to include "must be greater than 0"
      
        p.stf_taxi_per_ride_administrative_fee = 1
        expect(p.valid?).to be_truthy
        expect(p.errors.attribute_names.include?(:stf_taxi_per_ride_administrative_fee)).not_to be_truthy
      end
    end

    describe "stf_taxi_per_ride_ambulatory_load_fee" do
      it "should be an integer field" do
        p = build(:provider)
        expect(p).to respond_to(:stf_taxi_per_ride_ambulatory_load_fee)
        p.stf_taxi_per_ride_ambulatory_load_fee = "1"
        expect(p.stf_taxi_per_ride_ambulatory_load_fee).to eq 1.0
        p.stf_taxi_per_ride_ambulatory_load_fee = "0.12"
        expect(p.stf_taxi_per_ride_ambulatory_load_fee).to eq 0.12
      end
    
      it "should only allow values greater than 0" do
        p = build(:provider, :stf_taxi_per_ride_ambulatory_load_fee => 0)
        expect(p.valid?).to_not be_truthy
        expect(p.errors.attribute_names.include?(:stf_taxi_per_ride_ambulatory_load_fee)).to be_truthy
        expect(p.errors[:stf_taxi_per_ride_ambulatory_load_fee]).to include "must be greater than 0"
      
        p.stf_taxi_per_ride_ambulatory_load_fee = 1
        expect(p.valid?).to be_truthy
        expect(p.errors.attribute_names.include?(:stf_taxi_per_ride_ambulatory_load_fee)).not_to be_truthy
      end
    end

    describe "stf_taxi_per_ride_wheelchair_load_fee" do
      it "should be an integer field" do
        p = build(:provider)
        expect(p).to respond_to(:stf_taxi_per_ride_wheelchair_load_fee)
        p.stf_taxi_per_ride_wheelchair_load_fee = "1"
        expect(p.stf_taxi_per_ride_wheelchair_load_fee).to eq 1.0
        p.stf_taxi_per_ride_wheelchair_load_fee = "0.12"
        expect(p.stf_taxi_per_ride_wheelchair_load_fee).to eq 0.12
      end
    
      it "should only allow values greater than 0" do
        p = build(:provider, :stf_taxi_per_ride_wheelchair_load_fee => 0)
        expect(p.valid?).to_not be_truthy
        expect(p.errors.attribute_names.include?(:stf_taxi_per_ride_wheelchair_load_fee)).to be_truthy
        expect(p.errors[:stf_taxi_per_ride_wheelchair_load_fee]).to include "must be greater than 0"
      
        p.stf_taxi_per_ride_wheelchair_load_fee = 1
        expect(p.valid?).to be_truthy
        expect(p.errors.attribute_names.include?(:stf_taxi_per_ride_wheelchair_load_fee)).not_to be_truthy
      end
    end

    describe "stf_taxi_per_mile_ambulatory_reimbursement_rate" do
      it "should be an integer field" do
        p = build(:provider)
        expect(p).to respond_to(:stf_taxi_per_mile_ambulatory_reimbursement_rate)
        p.stf_taxi_per_mile_ambulatory_reimbursement_rate = "1"
        expect(p.stf_taxi_per_mile_ambulatory_reimbursement_rate).to eq 1.0
        p.stf_taxi_per_mile_ambulatory_reimbursement_rate = "0.12"
        expect(p.stf_taxi_per_mile_ambulatory_reimbursement_rate).to eq 0.12
      end
    
      it "should only allow values greater than 0" do
        p = build(:provider, :stf_taxi_per_mile_ambulatory_reimbursement_rate => 0)
        expect(p.valid?).to_not be_truthy
        expect(p.errors.attribute_names.include?(:stf_taxi_per_mile_ambulatory_reimbursement_rate)).to be_truthy
        expect(p.errors[:stf_taxi_per_mile_ambulatory_reimbursement_rate]).to include "must be greater than 0"
      
        p.stf_taxi_per_mile_ambulatory_reimbursement_rate = 1
        expect(p.valid?).to be_truthy
        expect(p.errors.attribute_names.include?(:stf_taxi_per_mile_ambulatory_reimbursement_rate)).not_to be_truthy
      end
    end

    describe "stf_taxi_per_mile_wheelchair_reimbursement_rate" do
      it "should be an integer field" do
        p = build(:provider)
        expect(p).to respond_to(:stf_taxi_per_mile_wheelchair_reimbursement_rate)
        p.stf_taxi_per_mile_wheelchair_reimbursement_rate = "1"
        expect(p.stf_taxi_per_mile_wheelchair_reimbursement_rate).to eq 1.0
        p.stf_taxi_per_mile_wheelchair_reimbursement_rate = "0.12"
        expect(p.stf_taxi_per_mile_wheelchair_reimbursement_rate).to eq 0.12
      end
    
      it "should only allow values greater than 0" do
        p = build(:provider)
        p.stf_taxi_per_mile_wheelchair_reimbursement_rate = 0
        expect(p.valid?).to_not be_truthy
        expect(p.errors.attribute_names.include?(:stf_taxi_per_mile_wheelchair_reimbursement_rate)).to be_truthy
        expect(p.errors[:stf_taxi_per_mile_wheelchair_reimbursement_rate]).to include "must be greater than 0"
      
        p.stf_taxi_per_mile_wheelchair_reimbursement_rate = 1
        expect(p.valid?).to be_truthy
        expect(p.errors.attribute_names.include?(:stf_taxi_per_mile_wheelchair_reimbursement_rate)).not_to be_truthy
      end
    end

    describe ".active?" do
      context "when inactived_date is set" do 
        it "is not active" do 
          p = build(:provider, inactivated_date: Date.yesterday)

          expect(p.active?).to_not be_truthy
        end
      end

      
      context "when inactived_date is not set" do 
        it "is active" do 
          p = build(:provider, inactivated_date: nil)

          expect(p.active?).to be_truthy
        end
      end
    end
  end
end

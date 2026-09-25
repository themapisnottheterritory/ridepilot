require "rails_helper"

RSpec.describe Customer do
  describe "service_level_id" do
    it "should be an integer field" do
      c = Customer.new
      expect(c).to respond_to(:service_level_id)
      c.service_level_id = "1"
      expect(c.service_level_id).to eq 1
      c.service_level_id = "0"
      expect(c.service_level_id).to eq 0
    end
  end
  
  describe "default_funding_source_id" do
    it "should be an integer field" do
      c = Customer.new
      expect(c).to respond_to(:default_funding_source_id)
      c.default_funding_source_id = "1"
      expect(c.default_funding_source_id).to eq 1
      c.default_funding_source_id = "0"
      expect(c.default_funding_source_id).to eq 0
    end
  end
  
  describe "ada_eligible" do
    it "should be a boolean field" do
      c = Customer.new
      expect(c).to respond_to(:ada_eligible)
      c.ada_eligible = "1"
      expect(c.ada_eligible).to be_truthy
      c.ada_eligible = "0"
      expect(c.ada_eligible).to be_falsey
    end
  end
  
  describe "medicaid_eligible" do
    it "should be a boolean field" do
      c = Customer.new
      expect(c).to respond_to(:medicaid_eligible)
      c.medicaid_eligible = "1"
      expect(c.medicaid_eligible).to be_truthy
      c.medicaid_eligible = "0"
      expect(c.medicaid_eligible).to be_falsey
    end
  end
  
  describe "prime_number" do
    it "should be a string field" do
      c = Customer.new
      expect(c).to respond_to(:prime_number)
      c.prime_number = "abc"
      expect(c.prime_number).to eq("abc")
    end
  end
  
  describe "replace_with!" do
    context "when no customer id" do
      attr_reader :customer
      
      before do
        @customer = create :customer
      end
      
      it "is false" do
        expect(@customer.replace_with!("")).not_to be
      end
    end
    
    context "when invalid customer id" do
      attr_reader :customer
      
      before do
        @customer = create :customer
      end
      
      it "is false" do
        expect(@customer.replace_with!(-1)).not_to be
      end
    end
    
    context "when valid customer id" do
      context "when customer has trips" do
        attr_reader :customer, :trips, :other

        before do
          @customer = create :customer
          @trips    = (1..5).map { create :trip, :customer => customer }
          @other    = create :customer
          
          customer.replace_with!(other.id)
        end
        
        it "destroys self" do
          expect(Customer.exists?(customer.id)).not_to be
        end

        it "moves self's trips to other customer" do
          for trip in trips
            expect(trip.reload.customer).to eq(other)
          end
        end
      end
      
      context "when customer has no trips" do
        attr_reader :customer

        before do
          @customer = create :customer
        end
        
        it "destroys self" do

        end
      end
      
      context "when other_customer_id is the same as customer.id" do
        before do
          @customer = create :customer
          @other_customer = create :customer
        end
        
        it "should return false" do
          expect(@customer.replace_with!(@customer.id)).to be_falsey
          expect(@customer.replace_with!(@other_customer.id)).not_to be_falsey
        end
      end
    end
  end
  
  describe 'travel_trainings' do
    let(:customer) { create(:customer) }
    let(:customer_w_trainings) { create(:customer, :with_travel_trainings) }
    
    it 'has many travel trainings' do
      tt_count = customer.travel_trainings.count
      customer.travel_trainings << create(:travel_training)
      expect(customer.travel_trainings.count).to eq(tt_count + 1)
      customer.travel_trainings << create(:travel_training)      
      expect(customer.travel_trainings.count).to eq(tt_count + 2)      
    end
    
    it 'edits travel trainings via hash' do
      original_trainings = customer_w_trainings.travel_trainings
      expect(customer_w_trainings.travel_trainings.count).to eq(3)
      
      # new trainings array consists of one new training, and two of the original
      # ones. One old training is left out.
      new_trainings_hash = [
        { date: Date.today, comment: "new comment"},
        original_trainings[0].attributes.with_indifferent_access,
        original_trainings[1].attributes.with_indifferent_access
      ]
      
      customer_w_trainings.edit_travel_trainings(new_trainings_hash)
      customer_w_trainings.reload
      new_trainings = customer_w_trainings.travel_trainings
      
      # Expect two of the old trainings and the one new one to be present
      expect(new_trainings.pluck(:id).include?(original_trainings[0].id)).to be true
      expect(new_trainings.pluck(:id).include?(original_trainings[1].id)).to be true
      expect(new_trainings.pluck(:id).include?(original_trainings[2].id)).to be false
      expect(new_trainings.where(comment: "new comment").count).to eq(1)
      
    end
  end

  describe 'funding_authorization_numbers' do
    let(:customer) { create(:customer) }
    let(:customer_w_funding_numbers) { create(:customer, :with_funding_authorization_numbers) }
    
    it 'has many funding authorization numbers' do
      fn_count = customer.funding_authorization_numbers.count
      customer.funding_authorization_numbers << create(:funding_authorization_number)
      expect(customer.funding_authorization_numbers.count).to eq(fn_count + 1)
      customer.funding_authorization_numbers << create(:funding_authorization_number)      
      expect(customer.funding_authorization_numbers.count).to eq(fn_count + 2)      
    end
    
    it 'edits funding authorization numbers via hash' do
      original_numbers = customer_w_funding_numbers.funding_authorization_numbers
      expect(customer_w_funding_numbers.funding_authorization_numbers.count).to eq(3)
      
      # new numbers array consists of one new funding number, and two of the original
      # ones. One old number is left out.
      new_funding_numbers_hash = [
        { number: 'test number', funding_source_id: FundingSource.first.id, contact_info: 'test contact info'},
        original_numbers[0].attributes.with_indifferent_access,
        original_numbers[1].attributes.with_indifferent_access
      ]
      
      customer_w_funding_numbers.edit_funding_authorization_numbers(new_funding_numbers_hash)
      customer_w_funding_numbers.reload
      new_funding_numbers = customer_w_funding_numbers.funding_authorization_numbers
      
      # Expect two of the old funding numbers and the one new one to be present
      expect(new_funding_numbers.pluck(:id).include?(original_numbers[0].id)).to be true
      expect(new_funding_numbers.pluck(:id).include?(original_numbers[1].id)).to be true
      expect(new_funding_numbers.pluck(:id).include?(original_numbers[2].id)).to be false
      expect(new_funding_numbers.where(contact_info: 'test contact info').count).to eq(1)
      
    end
  end
  
end

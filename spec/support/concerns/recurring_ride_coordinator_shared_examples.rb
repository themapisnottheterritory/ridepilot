require 'spec_helper'

# For model specs
RSpec.shared_examples "a recurring ride coordinator" do
  describe "instance" do
    before do
      @described_class_factory = described_class.name.underscore.to_sym

      @occurrence_scheduler_class = described_class
      @occurrence_scheduler_class_factory = @described_class_factory
      @occurrence_scheduler_association_id = "#{@occurrence_scheduler_class_factory}_id"

      # Set @scheduled_instance_class in the described class
      fail "@scheduled_instance_class instance variable required" unless defined? @scheduled_instance_class

      # Set @occurrence_date_attribute in the described class
      fail "@occurrence_date_attribute instance variable required" unless defined? @occurrence_date_attribute
      
      # Set @scheduler_date_attribute in the described class
      fail "@scheduler_date_attribute instance variable required" unless defined? @scheduler_date_attribute

    end

    describe "DAYS_OF_WEEK" do
      it "contains a list of the days of the week" do
        expect(described_class::DAYS_OF_WEEK).to include "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"
      end
    
      it "defines a method that checks whether it repeats for each given day of the week" do
        coordinator = build @described_class_factory
        expect(coordinator).to respond_to :repeats_sundays
        expect(coordinator).to respond_to :repeats_sundays=
        expect(coordinator).to respond_to :repeats_mondays
        expect(coordinator).to respond_to :repeats_mondays=
        expect(coordinator).to respond_to :repeats_tuesdays
        expect(coordinator).to respond_to :repeats_tuesdays=
        expect(coordinator).to respond_to :repeats_wednesdays
        expect(coordinator).to respond_to :repeats_wednesdays=
        expect(coordinator).to respond_to :repeats_thursdays
        expect(coordinator).to respond_to :repeats_thursdays=
        expect(coordinator).to respond_to :repeats_fridays
        expect(coordinator).to respond_to :repeats_fridays=
        expect(coordinator).to respond_to :repeats_saturdays
        expect(coordinator).to respond_to :repeats_saturdays=
      end
    end

    describe "#repetition_interval=" do
      before do
        @coordinator = build @described_class_factory
      end

      it "sets the repetition_interval in schedule_attributes" do
        old_schedule_interval = @coordinator.schedule_attributes[:interval]
        @coordinator.repetition_interval = old_schedule_interval + 1
        expect(@coordinator.schedule_attributes[:interval]).to eq(old_schedule_interval + 1)
      end

      it "converts values to integers" do
        @coordinator.repetition_interval = "5"
        expect(@coordinator.repetition_interval).to eq 5
      end
    end

    describe "#repetition_interval" do
      before do
        @coordinator = build @described_class_factory
      end
    
      it "returns the scheduler's schedule_attributes interval" do
        old_repetition_interval = @coordinator.repetition_interval
        @coordinator.send "schedule_attributes=", {
          repeat: 1, interval: old_repetition_interval + 1, interval_unit: "day"
        }

        expect(@coordinator.repetition_interval).to eq(old_repetition_interval + 1)
      end
    end  

    describe "after validation with repetition" do
      before do
        @driver = create :driver
        @vehicle = create :vehicle, default_driver: @driver
      end
      
      describe "when creating a coordinator with repetition data" do
        before do
          # Freeze date at Sun, 30 Aug 2015, 12:00 PM
          Timecop.freeze(Time.parse("2015-08-30 12:00").in_time_zone)
        
          @coordinator = create @described_class_factory,
            # Schedule first occurrence on Mon, 31 Sep 2015
            @scheduler_date_attribute => Time.parse("2015-08-31 12:00").in_time_zone,
            :repeats_mondays => true, 
            :repeats_tuesdays => false,
            :repeats_wednesdays => false,
            :repeats_thursdays => false,
            :repeats_fridays => false,
            :repeats_saturdays => false,
            :repeats_sundays => false,
            :vehicle_id => @vehicle.id,
            :driver_id => @driver.id,
            :repetition_interval => 1
        end
      
        after do
          Timecop.return
        end

        it "should instantiate coordinators for 21 (default) days out" do
          # Time is still frozen at Sun, 30 Aug 2015. 3 weeks out is
          # Sun, 20 Sep 2015. With weekly repeats on Mondays, beginning Mon, 31 
          # Aug 2015, this gives us:
          #   2015-08-31
          #   2015-09-07
          #   2015-09-14
          @coordinator.save
          # The occurrence we just created, plus 2 more
          expect(@scheduled_instance_class.where(@occurrence_scheduler_association_id => @coordinator.id).count).to eq 3
        end
      end

      describe "when updating a future coordinator with repetition data" do
        before do
          # Freeze date at Sun, 30 Aug 2015, 12:00 PM
          Timecop.freeze(Time.parse("2015-08-30 12:00").in_time_zone)

          @coordinator = create @described_class_factory,
            # Schedule first occurrence on Mon, 31 Sep 2015
            # With weekly repeats on Mondays, this gives us:
            #   2015-08-31
            #   2015-09-07
            #   2015-09-14
            @scheduler_date_attribute => Time.parse("2015-08-31 12:00").in_time_zone,
            :repeats_mondays => true, 
            :repeats_tuesdays => false,
            :repeats_wednesdays => false,
            :repeats_thursdays => false,
            :repeats_fridays => false,
            :repeats_saturdays => false,
            :repeats_sundays => false,
            :vehicle_id => @vehicle.id,
            :driver_id => @driver.id,
            :repetition_interval => 1
            
          @old_scheduled_through_date = @coordinator.try(:scheduled_through) 
          @coordinator.repeats_mondays = false
          @coordinator.repeats_tuesdays = true
          @coordinator.save
          @coordinator.reload
        end
      
        after do
          Timecop.return
        end

        it "should have the correct repeating coordinator attributes" do
          expect(@coordinator.schedule_attributes.monday).to be_nil
          expect(@coordinator.schedule_attributes.tuesday).to eq 1
        end

        it "should not have new child coordinators on the new day" do
          # Time is still frozen at Sun, 30 Aug 2015. 3 weeks out is
          # Sun, 20 Sep 2015. Upon save, the scheduler should have scheduled 
          # new occurrences on Tuesdays starting at the date the scheduler
          # left off before the coordinator was last saved, through the end of
          # the schedule window, but scheduled NO new occurrences before then.
          expect(
            @scheduled_instance_class.where(
              @occurrence_scheduler_association_id => @coordinator.id
            ).where("#{@occurrence_date_attribute} <= ?", @old_scheduled_through_date)
            .select{ |c| c.send(@occurrence_date_attribute).wday == 2 }.size
          ).to eq 0
        end

        it "should still have child coordinators on the old day" do
          # We should see only the original (which was created on a Monday).
          # Subscription trips withdraw the future trips on a day that is
          # unticked (RepeatingTrip#withdraw_future_trips_on!, 2026-10-05);
          # subscription runs keep theirs.
          expect(
            @scheduled_instance_class.where(
              @occurrence_scheduler_association_id => @coordinator.id
            ).select{ |c| c.send(@occurrence_date_attribute).strftime("%u") == "1" }.size
          ).to eq(@withdraws_removed_days ? 0 : 3)
        end

        it "should tell me the correct repetition data when reloading the coordinator" do
          @coordinator.reload
          expect(@coordinator.repeats_mondays).to be_falsey
          expect(@coordinator.repeats_tuesdays).to be_truthy
          expect(@coordinator.vehicle_id).to eq @vehicle.id
          expect(@coordinator.driver_id).to eq @driver.id
        end
      end
   
      describe "when updating a past coordinator with repetition data," do
        before do
          # Freeze date at Sun, 30 Aug 2015, 12:00 PM
          Timecop.freeze(Time.parse("2015-08-30 12:00").in_time_zone) do
            @coordinator = create @described_class_factory,
              # Schedule first occurrence on Mon, 31 Sep 2015
              # With weekly repeats on Mondays, this gives us:
              #   2015-08-31
              #   2015-09-07
              #   2015-09-14
              @scheduler_date_attribute => Time.parse("2015-08-31 12:00").in_time_zone,
              :repeats_mondays => true, 
              :repeats_tuesdays => false,
              :repeats_wednesdays => false,
              :repeats_thursdays => false,
              :repeats_fridays => false,
              :repeats_saturdays => false,
              :repeats_sundays => false,
              :vehicle_id => @vehicle.id,
              :driver_id => @driver.id,
              :repetition_interval => 1
              
          end
          
          # Now advance time two weeks, to Sun, 13 Sep 2015
          Timecop.freeze(Time.parse("2015-09-13 12:00").in_time_zone)
  
          @old_scheduled_through_date = @coordinator.try(:scheduled_through)          
          @coordinator.repeats_mondays = false
          @coordinator.repeats_tuesdays = true
          @coordinator.save
          @coordinator.reload
          
        end

        after do
          Timecop.return
        end

        it "should have the correct repeating coordinator attributes" do
          expect(@coordinator.schedule_attributes.monday).to be_nil
          expect(@coordinator.schedule_attributes.tuesday).to eq 1
        end

        it "should not have new child coordinators on the new day" do
          # Time is still frozen at Sun, 13 Sep 2015. 3 weeks out is
          # Sun, 04 Oct 2015. Upon save, the scheduler should have scheduled 
          # new occurrences on Tuesdays starting at the date the scheduler
          # left off before the coordinator was last saved, through the end of
          # the schedule window, but scheduled NO new occurrences before then.
          expect(
            @scheduled_instance_class.where(
              @occurrence_scheduler_association_id => @coordinator.id
            ).where("#{@occurrence_date_attribute} <= ?", @old_scheduled_through_date)
            .select{ |c| c.send(@occurrence_date_attribute).wday == 2 }.size
          ).to eq 0
        end

        it "should still have child coordinators on the old day beyond Sun, 13 Sep 2015" do
          expect(
            @scheduled_instance_class.after_today.where(
              @occurrence_scheduler_association_id => @coordinator.id
            ).select{ |c| c.send(@occurrence_date_attribute).strftime("%u") == "1" }.size
          ).to eq(@withdraws_removed_days ? 0 : 1)   # see above: subscription trips withdraw them
        end

        it "should retain child coordinators on the old day on or before Sun, 13 Sep 2015" do
          expect(
            @scheduled_instance_class.today_and_prior.where(
              @occurrence_scheduler_association_id => @coordinator.id
            ).select{ |c| c.send(@occurrence_date_attribute).strftime("%u") == "1" }.size
          ).to eq 2
        end

        it "should tell me the correct repeating trip data when reloading the trip" do
          @coordinator.reload
          expect(@coordinator.repeats_mondays).to be_falsey
          expect(@coordinator.repeats_tuesdays).to be_truthy
          expect(@coordinator.vehicle_id).to eq @vehicle.id
          expect(@coordinator.driver_id).to eq @driver.id
        end
      end

      describe "when I clear out the repetition data" do
        before do
          # Freeze date at Sun, 30 Aug 2015, 12:00 PM
          Timecop.freeze(Time.parse("2015-08-30 12:00").in_time_zone) do
            @coordinator = create @described_class_factory,
              # Schedule first occurrence on Mon, 31 Sep 2015
              # With weekly repeats on Mondays, this gives us:
              #   2015-08-31
              #   2015-09-07
              #   2015-09-14
              @scheduler_date_attribute => Time.parse("2015-08-31 12:00").in_time_zone,
              :repeats_mondays => true, 
              :repeats_tuesdays => false,
              :repeats_wednesdays => false,
              :repeats_thursdays => false,
              :repeats_fridays => false,
              :repeats_saturdays => false,
              :repeats_sundays => false,
              :vehicle_id => @vehicle.id,
              :driver_id => @driver.id,
              :repetition_interval => 1
          end
          
          # Now advance time two weeks, to Sun, 13 Sep 2015
          Timecop.freeze(Time.parse("2015-09-13 12:00").in_time_zone)
                    
          @coordinator.repeats_mondays = false
          @coordinator.save
          
        end

        after do
          Timecop.return
        end

        it "should retain child coordinators on or before Sun, 13 Sep 2015" do
          expect(
            @scheduled_instance_class.today_and_prior.where(
              @occurrence_scheduler_association_id => @coordinator.id
            ).select{ |c| c.send(@occurrence_date_attribute).strftime("%u") == "1" }.size
          ).to eq 2
        end
      end
      
      describe 'after the child coordinators have been destroyed' do
        before do
          # Freeze date at Sun, 30 Aug 2015, 12:00 PM
          Timecop.freeze(Time.parse("2015-08-30 12:00").in_time_zone)
          
        
          @coordinator = create @described_class_factory,
            # Schedule first occurrence on Mon, 31 Sep 2015
            # With weekly repeats on Mondays, this gives us:
            #   2015-08-31
            #   2015-09-07
            #   2015-09-14
            @scheduler_date_attribute => Time.parse("2015-08-31 12:00").in_time_zone,
            :repeats_mondays => true, 
            :repeats_tuesdays => false,
            :repeats_wednesdays => false,
            :repeats_thursdays => false,
            :repeats_fridays => false,
            :repeats_saturdays => false,
            :repeats_sundays => false,
            :vehicle_id => @vehicle.id,
            :driver_id => @driver.id,
            :repetition_interval => 1
          
          # Now, destroy the child coordinators and re-save the coordinator
          child_coordinators = @scheduled_instance_class.where(
            @occurrence_scheduler_association_id => @coordinator.id
          )          
          child_coordinators.destroy_all
          
          @coordinator.save
          
        end
        
        after do
          Timecop.return
        end
        
        it 'has not created new child coordinators' do
          child_coordinators = @scheduled_instance_class.where(
            @occurrence_scheduler_association_id => @coordinator.id
          )
          expect(child_coordinators.count).to eq(0)
        end
        
      end
    end
  end
end

require "rails_helper"

# Summing actual_end_time - actual_start_time gives a Duration in Rails 7, not an
# "hh:mm:ss" string: Service Summary crashed and Vehicles Monthly showed seconds
# as hours (2026-10-05).
RSpec.describe ReportsController do
  let(:controller) { ReportsController.new }

  it "turns a summed interval (Duration) into hours" do
    expect(controller.send(:hms_to_hours, 68.hours + 49.minutes + 56.seconds)).to be_within(0.001).of(68.832)
  end

  it "still reads the old hh:mm:ss form and zero" do
    expect(controller.send(:hms_to_hours, "2:30:00")).to eq 2.5
    expect(controller.send(:hms_to_hours, 0)).to eq 0
    expect(controller.send(:hms_to_hours, nil)).to eq 0
  end

  it "sums real run times into hours" do
    run = create(:run, date: Date.current)
    run.update_columns(actual_start_time: 3.hours.ago, actual_end_time: 30.minutes.ago)
    total = Run.where(id: run.id).sum("actual_end_time - actual_start_time")
    expect(controller.send(:hms_to_hours, total)).to be_within(0.01).of(2.5)
  end
end

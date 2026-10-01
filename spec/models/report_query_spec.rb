require "rails_helper"

# Report date boxes: day 31 is offered for every month.
ReportsController   # Query is defined in reports_controller.rb
RSpec.describe Query do
  def dates(y, m, d)
    { "start_date(1i)" => y.to_s, "start_date(2i)" => m.to_s, "start_date(3i)" => "1",
      "before_end_date(1i)" => y.to_s, "before_end_date(2i)" => m.to_s, "before_end_date(3i)" => d.to_s }
  end

  it "reads Sep 31 as Sep 30 instead of failing" do
    q = Query.new(dates(2026, 9, 31))
    expect(q.before_end_date).to eq Date.new(2026, 9, 30)
    expect(q.end_date).to eq Date.new(2026, 10, 1)
  end

  it "reads Feb 30 as the last day of February, in a leap year too" do
    expect(Query.new(dates(2026, 2, 30)).before_end_date).to eq Date.new(2026, 2, 28)
    expect(Query.new(dates(2028, 2, 31)).before_end_date).to eq Date.new(2028, 2, 29)
  end

  it "leaves a real date alone" do
    expect(Query.new(dates(2026, 10, 31)).before_end_date).to eq Date.new(2026, 10, 31)
  end
end

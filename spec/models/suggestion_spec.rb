require "rails_helper"

RSpec.describe Suggestion do
  it "names the screen from the page it was sent from" do
    expect(Suggestion.new(page_path: "/en/dispatchers").screen).to eq "Dispatch"
    expect(Suggestion.new(page_path: "/en/trips/5/edit?x=1").screen).to eq "Trips"
    expect(Suggestion.new(page_path: nil).screen).to be_nil
  end
end

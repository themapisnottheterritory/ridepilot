# Stop times typed from a paper manifest on "Fix from paper" (RunPaperFix), not
# tapped on the tablet: who typed them and when (2026-10-13).
class AddTimesTypedToItineraries < ActiveRecord::Migration[7.1]
  def change
    add_column :itineraries, :times_typed_by, :string
    add_column :itineraries, :times_typed_at, :datetime
  end
end

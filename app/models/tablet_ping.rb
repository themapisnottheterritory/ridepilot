# One report from a tablet (Tablet.record!): battery, connection and who was
# signed in, about every ten minutes while the app is open. Kept 90 days
# (tablets:prune).
class TabletPing < ActiveRecord::Base
  belongs_to :tablet
end

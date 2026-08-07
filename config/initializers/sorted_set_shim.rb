# Ruby 3.0 removed SortedSet from the stdlib `set` library, leaving only a stub
# named SortedSet that raises "The SortedSet class has been extracted..." on use.
#
# ice_cube 0.6.14 (pinned `~> 0.6.8` in the Gemfile) still uses SortedSet in
# Schedule#occurrences_between / #find_occurrences to keep recurrence dates in
# order -- so recurring-trip scheduling blows up under Ruby 3. Rather than pull
# the native `sorted_set` gem or force a risky ice_cube major upgrade (which
# changes schedule serialization) before the September cutover, provide a
# minimal Set subclass that returns/yields its elements in sorted order, which
# is all ice_cube relies on.
#
# We must REPLACE the raising stub (it is `defined?`), not guard against it.
require 'set'

Object.send(:remove_const, :SortedSet) if defined?(SortedSet)

class SortedSet < Set
  def each(&block)
    return to_a.each unless block_given?
    to_a.each(&block)
    self
  end

  def to_a
    super.sort
  end
end

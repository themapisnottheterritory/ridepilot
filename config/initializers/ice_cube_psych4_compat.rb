# ice_cube 0.6.14 deserializes schedules with YAML::load (IceCube::Schedule.from_yaml
# and IceCube::Rule.from_yaml). Under Ruby 3.1+/Psych 4+, YAML.load IS safe_load,
# which rejects the Symbol keys (and serialized Time) in ice_cube's schedule YAML
# with Psych::DisallowedClass -- breaking RepeatingTrips#show and any read of a
# stored recurrence schedule.
#
# schedule_yaml is app-generated and trusted: it is only ever written server-side
# by ScheduleAttributes#schedule_attributes= (@schedule.to_yaml), never from
# user-supplied raw YAML. So restore the pre-Psych-4 behavior with unsafe_load,
# scoped to ice_cube's own deserialization.
require 'ice_cube'

module IceCube
  class Schedule
    def self.from_yaml(str, hash_options = {})
      from_hash(YAML.unsafe_load(str), hash_options)
    end
  end

  class Rule
    def self.from_yaml(str)
      from_hash(YAML.unsafe_load(str))
    end
  end
end

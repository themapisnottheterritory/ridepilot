# Seeds GCRPC's pre/post-trip inspection item library (idempotent — safe to re-run).
# Mirrors dvir-inspection-app/CHECKLIST-master.md.
# Run:  docker compose exec app bundle exec rake dvir:seed
#
# Numeric captures (odometer, lift cycle count, gallons) are columns on
# vehicle_inspection_reports, NOT checklist items, so they're not seeded here.
namespace :dvir do
  desc "Seed/refresh GCRPC vehicle inspection checklist items (idempotent)"
  task seed: :environment do
    provider = Provider.first   # GCRPC — single provider on this instance. Adjust if needed.
    abort("Aborting: no Provider found.") unless provider

    # One-time rename (Phase 1, G9): "Bloodborne Kit" -> "Biohazard Kit" so re-seeding
    # updates the existing row in place instead of leaving a stale duplicate.
    VehicleInspection.where(provider_id: provider.id, description: "Bloodborne Kit")
                     .update_all(description: "Biohazard Kit")

    # [category, default_phase, items]
    # item = [description, opts]; opts: crit (=>flagged), mech (=>mechanical), cdl (=>cdl_only), phase (override)
    data = [
      ["Engine / Fluid", "both", [
        ["Oil"], ["Belts"], ["Coolant"], ["Brake Fluid"], ["Wiper Fluid"],
        ["Transmission"], ["Power Steering"],
        ["Alternator", { mech: true }],
        ["Air Compressor", { crit: true, mech: true, cdl: true }],
      ]],
      ["Brakes", "both", [
        ["Parking Brake Test", { crit: true, mech: true }],
        ["Service Brake Test", { crit: true, mech: true }],
        ["Air / Low-Air Warning", { crit: true, mech: true, cdl: true }],
        ["Brake Hoses & Lines", { crit: true, mech: true }],
        ["Slack Adjuster", { crit: true, mech: true, cdl: true }],
      ]],
      ["Steering & Suspension", "both", [
        ["Steering Linkage", { crit: true, mech: true }],
        ["Springs", { mech: true }], ["Shocks", { mech: true }], ["Airbags", { mech: true }],
      ]],
      ["Lights", "both", [
        ["Headlights (Hi / Lo)"], ["Tail"], ["Brake"], ["Signal"], ["Flashers"], ["Clearance"],
      ]],
      ["Exterior", "both", [
        ["Body Inspection", { crit: true }], ["Tire Inflation"], ["Tire Condition"],
        ["Lug Nuts & Rims", { mech: true }], ["Mirrors (L / R)"], ["Wipers"],
        ["Destination Sign"], ["DOT Inspection"], ["Bike Rack"],
      ]],
      ["Interior", "both", [
        ["Interior Condition", { crit: true }], ["Seats", { crit: true }], ["Seat Belts"],
        ["PA System"], ["Stop Request"], ["Interior Lighting", { crit: true }],
        ["Mirror", { crit: true }], ["Floor Condition"], ["AC / Heater"], ["DVR Camera"], ["Insurance"],
      ]],
      ["Signage", "both", [
        ["No Smoking / Eating", { crit: true }], ["Seat Belt", { crit: true }], ["No Weapons", { crit: true }],
      ]],
      ["Safety", "both", [
        ["Fire Extinguisher", { crit: true }], ["Triangles", { crit: true }], ["Horn"],
        ["Back-up Alarm"], ["Oxygen Tank Straps"], ["First Aid Kit", { crit: true }],
        ["Biohazard Kit", { crit: true }], ["Disposal Gloves / Bags"], ["Brush"],
        ["Disinfectant"], ["Deodorizer"],
      ]],
      ["Wheelchair", "both", [
        ["Operations", { crit: true, mech: true }],
        ["Lift / Ramp Device Inspection", { crit: true, mech: true }],
        ["Straps / Belts", { crit: true, phase: "pre" }],
        ["Stowed Securements", { crit: true, phase: "post" }],
      ]],
      ["End of Service", "post", [
        ["Windows Closed"], ["Bus Cleaned"], ["W/C Door Locked"],
      ]],
    ]

    created = updated = 0
    pos = 0
    data.each do |category, default_phase, items|
      items.each do |(desc, opts)|
        opts ||= {}
        pos += 1
        rec = VehicleInspection.where(provider_id: provider.id, description: desc, category: category).first_or_initialize
        new_record = rec.new_record?
        rec.assign_attributes(
          phase:      opts[:phase] || default_phase,
          flagged:    !!opts[:crit],
          mechanical: !!opts[:mech],
          cdl_only:   !!opts[:cdl],
          position:   pos,
        )
        rec.save!
        new_record ? (created += 1) : (updated += 1)
      end
    end

    puts "DVIR seed complete for provider ##{provider.id} (#{provider.try(:name)}): #{created} created, #{updated} updated."
    puts "Tip: set cdl_only items to show only for air-brake/CDL vehicle types once confirmed."
  end
end

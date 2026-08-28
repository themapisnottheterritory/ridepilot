# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the rake db:seed (or created alongside the db with db:setup).
#
# Examples:
#
#   cities = City.create([{ name: 'Chicago' }, { name: 'Copenhagen' }])
#   Mayor.create(name: 'Emanuel', city: cities.first)

ApplicationRecord.transaction do
  puts "Seeding..."

  puts "Creating first provider and system admin..."
  if !Provider.first.present?
    puts "Creating first Provider..."
    provider = Provider.new(:name => 'Victoria Transit GCRPC', :dispatch => true)
    provider.logo = File.open(Rails.root.join("public", "gcrpc-logo.png"))
    provider.save!

    puts "Creating first User..."
    email = Rails.application.secrets.system_admin_email
    username = Rails.application.secrets.system_admin_username || email.split('@').first
    password = Rails.application.secrets.system_admin_password
    first_name = Rails.application.secrets.system_admin_first_name || "Admin"
    last_name = Rails.application.secrets.system_admin_last_name || "User"

    user = User.create!(
      :email => email,
      :username => username,
      :password => password,
      :password_confirmation => password,
      :current_provider => provider,
      :first_name => first_name,
      :last_name => last_name
    )

    puts "Setting first user up as a super admin..."
    Role.create!(
      :user => user,
      :provider => provider,
      :level => 200
    )
  end

  puts "Seeding translations"
  Rake::Task["ridepilot:load_locales"].invoke

  puts "Creating lookup tables..."
  Rake::Task["ridepilot:seed_lookup_tables"].invoke

  puts "Seeding eligibilities"
  Rake::Task["ridepilot:seed_eligibilities"].invoke

  puts "Seeding address groups"
  Rake::Task["ridepilot:seed_address_groups"].invoke

  puts "Seeding custom reports"
  Rake::Task["ridepilot:seed_custom_reports"].invoke

  #puts "Seeding supporting reporting filter types"
  #Rake::Task["ridepilot:seed_reporting_filter_types"].invoke

  puts "Done seeding"

end

namespace :ridepilot do

  desc 'Seed default lookup table configurations and each associated table data'
  task :seed_lookup_tables => :environment do
    puts 'trip purposes...'
    seed_file = File.join(Rails.root, 'db', 'tasks', 'seed_trip_purposes.rb')
    load(seed_file) if File.exist?(seed_file)
    puts 'Finished seeding trip purposes'

    puts 'trip results...'
    seed_file = File.join(Rails.root, 'db', 'tasks', 'seed_trip_results.rb')
    load(seed_file) if File.exist?(seed_file)
    puts 'Finished seeding trip results'

    puts 'service levels...'
    seed_file = File.join(Rails.root, 'db', 'tasks', 'seed_service_levels.rb')
    load(seed_file) if File.exist?(seed_file)
    puts 'Finished seeding service levels'

    puts 'mobilities...'
    seed_file = File.join(Rails.root, 'db', 'tasks', 'seed_mobilities.rb')
    load(seed_file) if File.exist?(seed_file)
    puts 'Finished seeding mobilities'

    puts 'ethnicities...'
    seed_file = File.join(Rails.root, 'db', 'tasks', 'seed_ethnicities.rb')
    load(seed_file) if File.exist?(seed_file)
    puts 'Finished seeding ethnicities'

    puts 'customer address codes...'
    seed_file = File.join(Rails.root, 'db', 'tasks', 'seed_customer_address_codes.rb')
    load(seed_file) if File.exist?(seed_file)
    puts 'Finished customer address codes'

    puts 'lookup table configurations...'
    seed_file = File.join(Rails.root, 'db', 'tasks', 'seed_lookup_table_configurations.rb')
    load(seed_file) if File.exist?(seed_file)
    puts 'Finished seeding lookup table configurations'

    puts 'provider lookup table configurations...'
    seed_file = File.join(Rails.root, 'db', 'tasks', 'seed_provider_lookup_table_configurations.rb')
    load(seed_file) if File.exist?(seed_file)
    puts 'Finished seeding provider lookup table configurations'
  end

  desc 'Seed list of supporting custom reports'
  task :seed_custom_reports => :environment do
    seed_file = File.join(Rails.root, 'db', 'tasks', 'seed_custom_reports.rb')
    load(seed_file) if File.exist?(seed_file)
    puts 'Finished seeding supporting custom reports'
  end

  desc 'Seed list of eligibility factors'
  task :seed_eligibilities => :environment do
    seed_file = File.join(Rails.root, 'db', 'tasks', 'seed_eligibilities.rb')
    load(seed_file) if File.exist?(seed_file)
    puts 'Finished seeding eligibilities'
  end

  desc 'Seed address groups'
  task :seed_address_groups => :environment do
    seed_file = File.join(Rails.root, 'db', 'tasks', 'seed_address_groups.rb')
    load(seed_file) if File.exist?(seed_file)
    puts 'Finished seeding'
  end

  desc 'Update lookup configs for ethnicities'
  task :update_ethnicity_lookup_config => :environment do
    config = LookupTable.find_by_name('provider_ethnicities')
    config.update(name: 'ethnicities', caption: 'Ethnicity') if config
  end

  desc 'Seed some fake data for testing'
  task :seed_test_data => :environment do

    for index in 1..5
      customer = Customer.new
      customer.first_name = "Customer_first_name_#{index}"
      customer.last_name = "Customer_last_name_#{index}"
      customer.address = Address.first
      customer.provider = Provider.first
      puts customer.save!
    end
    for index in 1..5
      provider = Provider.find_or_create_by(:name => "provider_name_#{index}")
      puts provider.save!
    end
    for index in 1..5
      #assign to a random provider
      offset = rand(Provider.count)
      random_provider = Provider.offset(offset).first
      provider_id = 
      user = User.find_or_create_by(:email => "abromley#{index}@camsys.com")
      user.password = "welcome1!"
      user.current_provider_id = random_provider.id
      user.save!
      role = Role.new
      role.user_id = user.id
      role.provider_id = random_provider.id
      role.level = 100
      puts role.save!
    end
  end

  desc "Seed supported filter types in reporting engine "
  task seed_reporting_filter_types: :environment do

    %w(
      eq not_eq 
      matches does_not_match 
      lt gt 
      lteq gteq 
      in not_in 
      cont not_cont 
      cont_any not_cont_any 
      i_cont i_not_cont
      start not_start
      end not_end
      true not_true
      false not_false
      present blank
      null not_null
      range
      select
      multi_select
      ).each do |type|
      Reporting::FilterType.where(name: type).first_or_create
    end
    puts 'Finished seeding reporting filter types.'

  end # task

  desc "mark addresses if associated with a driver"
  task mark_address_if_driver_associated: :environment do
    Driver.includes(:address).each do |driver|
      driver.address.update(is_driver_associated: true) if driver.address
    end
  end

  desc "Generate customer token"    
  task generate_customer_token: :environment do    
    Customer.where(token: nil).each do |customer|    
      customer.update_attribute(:token, SecureRandom.hex(5))   
    end    
  end

  desc 'Seed lookup tables configurations'
  task :seed_lookup_table_configurations => :environment do
    seed_file = File.join(Rails.root, 'db', 'tasks', 'seed_lookup_table_configurations.rb')
    load(seed_file) if File.exist?(seed_file)
    puts 'Finished seeding lookup table configurations'
  end

  desc 'Add driver manifest report'
  task :add_driver_manifest_report => :environment do
    report = CustomReport.where(name: "driver_manifest").first_or_create 
    report.update(redirect_to_results: false, title: "Driver Manifest")
    puts 'Driver manifest report added'
  end

  desc 'Update trip results'
  task :update_trip_results => :environment do
    seed_file = File.join(Rails.root, 'db', 'tasks', 'seed_trip_results.rb')
    load(seed_file) if File.exist?(seed_file)
    puts 'Finished seeding trip results'
  end
  
   desc 'Update translation labels'
  task :update_translations => :environment do
    new_trans = {
      application_cabs_link_text: 'Cabs',
      application_admin_link_text: "System Admin",
      current_provider_settings_link_text: "Provider Settings",
      application_trips_runs_link_text: 'Dispatch',
      trips_runs: 'Dispatch',
      new_password_form_heading: 'Enter your Username',
      no_verification_questions_set: "You have not set up any security questions. Please contact your administrator to reset your password.",
      verification_question_incorrect_answer: "That answer is not correct. Please try again or contact your administrator to reset your password.",
      customer_inactive_for_trip_date: "is not active on the trip scheduled date.",
      vehicle_maintenance_compliances_heading: "Preventive Maintenance Logs (PM)",
      provider_form_fields_required_for_run_completion: "Fields required for a run to be considered completed",
      vehicle_maintenance_compliances_empty: "No compliance events exist for this vehicle",
      cancel_run: "Cancel",
      unavailable_driver_for_run_time_range_warning: "Driver is not available within the run scheduled time range."
    }

    en_locale = Locale.find_by_name 'en'
    if en_locale.present?
      new_trans.each do |k, v|
        key = TranslationKey.find_by_name k 
        if key.present?
          t = Translation.where(locale: en_locale, translation_key: key).first
          t.update(value: v) if v.present?
        end
      end 
    end
  end

  desc 'Migrate addresses to specific sub categories'
  task :categorize_addresses => :environment do
    seed_file = File.join(Rails.root, 'db', 'tasks', 'categorize_addresses.rb')
    load(seed_file) if File.exist?(seed_file)
    puts 'Finished'
  end

  desc 'Migrate existing users to have username as login'
  task :migrate_usernames => :environment do
    User.transaction do 
      User.unscoped.each do |user|
        next if user.username.present?

        user.update_attribute(:username, user.email) # user email as default username
        user.update_attribute(:first_name, user.email.split('@').first) # default first name
        user.update_attribute(:last_name, 'User') # default last name
      end
    end
  end

  desc 'Seed provider lookup tables configurations'
  task :seed_provider_lookup_table_configurations => :environment do
    seed_file = File.join(Rails.root, 'db', 'tasks', 'seed_provider_lookup_table_configurations.rb')
    load(seed_file) if File.exist?(seed_file)
    puts 'Finished seeding provider lookup table configurations'
  end

  desc 'Migrate inactive customers'
  task :migrate_inactive_customers => :environment do
    Customer.unscoped.where(inactivated_date: nil).update_all(active: true)
    Customer.unscoped.where.not(inactivated_date: nil).update_all(active: false)
    puts 'Finished inactive customer data migration'
  end

  desc 'Migrate existing provider common address with default type'
  task :migrate_provider_common_addresses => :environment do
    default_group_id = AddressGroup.default_address_group.try(:id)
    ProviderCommonAddress.unscoped.type_unknown.update_all(address_group_id: default_group_id) if default_group_id
    puts 'Finished migration'
  end

  desc "Move documents in production to new path due to paperclip storage option changes"
  task :move_production_documents => :environment do
    Document.find_each do |attachment|
      file_name = attachment.document_file_name
      unless file_name.blank?
        ext_name = File.extname(file_name)

        legacy_filename = File.join(
          File.dirname(attachment.document.path),
          attachment.document.hash_key,
          ext_name
        )

        if File.exist? legacy_filename
          File.rename(legacy_filename, attachment.document.path)
        end
      end
    end
  end

  desc 'Remove outdated eligibilities'
  task :remove_outdated_eligibilities => :environment do
    ada_elig = Eligibility.find_by_code 'ada_eligible'
    if ada_elig
      CustomerEligibility.where(eligibility: ada_elig).each do |el|
        customer = el.customer
        next unless customer
        customer.ada_eligible = el.eligible 
        customer.ada_ineligible_reason = el.ineligible_reason
        customer.save(validate: false)
      end
    end

    Eligibility.where(code: ['age_eligible', 'ada_eligible']).delete_all
    puts 'Finished cleanup'
  end

  desc 'Seed user data'
  task :seed_user_data => :environment do
    # File format:
    # first row is header/column names
    # data row: First Name, Last Name, email
    csv_file_path = ENV["CSV_PATH"]
    if csv_file_path
      begin
        row_count = 0
        CSV.foreach(csv_file_path) do |row|
          row_count += 1

          # skip header 
          next if row_count == 1

          first_name = row[0]
          last_name = row[1]
          email = row[2]

          if email
            user = User.find_by_email(email)
            if user
              user.first_name = first_name
              user.last_name = last_name
              user.save(validate: false)
            end
          end          
        end

        puts 'Seeded'
      rescue Exception
        puts "file invalid"
      end
    else
      puts "please specifiy file path following: rails ridepilot:seed_user_data CSV_PATH=xxx"
    end
  end

  desc 'Add capacity type lookup table'
  task :add_capacity_type_lookup_table => :environment do
    config_data = {
      name: 'capacity_types',
      caption: 'Capacity Type',
      value_column_name: 'name'
    }
    config = LookupTable.find_by(name: config_data[:name])
    if config 
      config.update(config_data)
    else
      LookupTable.create(config_data)
    end

    p_config = ProviderLookupTable.find_by(name: config_data[:name])
    if p_config 
      p_config.update(config_data)
    else
      ProviderLookupTable.create(config_data)
    end
  end

  desc 'Add new custom reports'
  task :add_v2_custom_reports => :environment do
    # flag previous reports as v1
    CustomReport.where(version: nil).update_all(version: '1')

    # seed v2 reports
    seed_file = File.join(Rails.root, 'db', 'tasks', 'seed_v2_custom_reports.rb')
    load(seed_file) if File.exist?(seed_file)
    puts 'Finished seeding supporting version 2 custom reports'
  end

  desc 'Remove provider-specific capacity types'
  task :remove_provider_specific_capacity_types => :environment do
    ct_table = ProviderLookupTable.find_by_name "capacity_types"
    if ct_table
      ct_table.delete
      CapacityType.where.not(provider_id: nil).destroy_all
    end
    puts 'Finished removal'
  end

  desc 'Migrate trip size fields'
  task :migrate_trip_size_fields => :environment do
    Trip.where(customer_space_count: nil).update_all(customer_space_count: 1)
    Trip.where(guest_count: nil).update_all(guest_count: 0)
    Trip.where(attendant_count: nil).update_all(attendant_count: 0)
    Trip.where(service_animal_space_count: nil).update_all(service_animal_space_count: 0)

    RepeatingTrip.where(customer_space_count: nil).update_all(customer_space_count: 1)
    RepeatingTrip.where(guest_count: nil).update_all(guest_count: 0)
    RepeatingTrip.where(attendant_count: nil).update_all(attendant_count: 0)
    RepeatingTrip.where(service_animal_space_count: nil).update_all(service_animal_space_count: 0)
  end

  desc 'Migrate operating hours to update values for is_unavailable and is_all_day fields'
  task :migrate_operating_hours => :environment do
    OperatingHour.where("start_time is NULL and end_time is NULL and is_all_day = ?", false).update_all(is_unavailable: true)
    
    all_day_ids = []
    OperatingHour.where.not(is_unavailable: true).pluck(:id, :start_time, :end_time).each do |config|
      if config[1].try(:to_s, :time_utc) == '00:00:00' and config[2].try(:to_s, :time_utc) == '00:00:00'
        all_day_ids << config[0]
      end
    end
    OperatingHour.where(id: all_day_ids).update_all(is_all_day: true)
  end

  desc 'Update runs scheduled time string'
  task :migrate_runs_scheduled_time_string => :environment do
    Run.unscoped.where('scheduled_start_time_string is NULL or scheduled_end_time_string is NULL').find_each do |r|
      r.scheduled_start_time_string = r.scheduled_start_time.try(:to_s, :time_utc)
      r.scheduled_end_time_string = r.scheduled_end_time.try(:to_s, :time_utc)
      r.save(validate: false)
    end

    RepeatingRun.unscoped.where('scheduled_start_time_string is NULL or scheduled_end_time_string is NULL').find_each do |r|
      r.scheduled_start_time_string = r.scheduled_start_time.try(:to_s, :time_utc)
      r.scheduled_end_time_string = r.scheduled_end_time.try(:to_s, :time_utc)
      r.save(validate: false)
    end
  end

  desc 'Update runs scheduled time string'
  task :mark_today_future_manifest_changed => :environment do
    run_ids = Run.today_and_future.where(manifest_changed: [nil, false]).pluck(:id)
    has_trip_itin_run_ids = Itinerary.revenue.where(run_id: run_ids).pluck(:run_id)
    published_run_ids = PublicItinerary.where(run_id: run_ids).pluck(:run_id)

    # these runs has itineraries, but not published, so need to mark as manifest changed
    Run.where(id: (has_trip_itin_run_ids - published_run_ids)).update_all(manifest_changed: true)
  end

  desc "re-create repeating run itineraries"
  task :recreate_legacy_repeating_run_itins => :environment do
    RepeatingRun.all.each do |r|
      (0..6).each do |wday|
        itins = r.repeating_itineraries.for_wday(wday)
        # has trips assigned, but no itineraries created
        if itins.empty? && r.weekday_assignments.for_wday(wday).any?
          r.reset_itineraries!(wday)
        end
      end
    end
  end
end

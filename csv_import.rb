require 'csv'
require_relative 'config/environment'

def clean_phone(phone)
  return nil if phone.nil? || phone.strip.empty?
  # Remove any non-digit characters
  digits = phone.gsub(/\D/, '')
  # Add area code if needed (assuming Texas, default to 361 if missing)
  digits = "361#{digits}" if digits.length == 7
  # Format consistently
  digits.gsub(/(\d{3})(\d{3})(\d{4})/, '\1-\2-\3')
end

def create_address_from_row(row)
  address_line = [row['address'], row['suite']].compact.join(' ').strip
  
  Address.create!(
    name: 'Home',
    address: address_line,
    city: row['city'],
    state: row['state'] || 'TX',
    zip: row['zip'],
    notes: "County: #{row['county']}",
    type: "CustomerCommonAddress"
  )
end

def map_funding_source(source_text)
  # You'll need to adjust these mappings based on your actual funding sources
  funding_map = {
    'Zcan Seat - Victoria' => 1,
    'Elderly / Disabled / Youth' => 2,
    'Zambulatory - Victoria' => 3
    # Add more mappings as needed
  }
  
  funding_map.each do |key, value|
    return value if source_text&.include?(key)
  end
  
  1 # Default funding source ID
end

# Set default values for required fields
DEFAULT_VALUES = {
  mobility_id: 1,          # Default mobility type
  service_level_id: 1,     # Default service level
  provider_id: 1,          # Default provider
  group: false,
  medicaid_eligible: false,
  ada_eligible: false,
  active: true
}

puts "Starting customer import..."
successful_imports = 0
failed_imports = 0

CSV.foreach('clients.csv', headers: true) do |row|
  begin
    # Skip if it looks like a facility (contains 'HOME' or other facility keywords)
#    next if row['first_name'].to_s.upcase.include?('HOME') || 
#            row['last_name'].to_s.upcase.include?('HOME')
    
    # Create address first
    address = create_address_from_row(row)
    row['last_name'] = row['last_name'].to_s.downcase.capitalize unless row['last_name'].nil?
    row['first_name'] = row['first_name'].to_s.downcase.capitalize unless row['first_name'].nil?
    # Create customer with the new address
    customer = Customer.create!(
      last_name: row['last_name'],
      first_name: row['first_name'],
      middle_initial: row['middle_initial'],
      phone_number_1: clean_phone(row['phone_number_1']),
      phone_number_2: clean_phone(row['phone_number_2']),
      address_id: address.id,
      default_funding_source_id: map_funding_source(row['funding_source']),
      **DEFAULT_VALUES,
      ethnicity: '',  # Set appropriate default
      message: "Imported from legacy system",
      public_notes: "Original funding source: #{row['funding_source']}"
    )
    
    # Update address with customer reference
    address.update(customer_id: customer.id)
    
    successful_imports += 1
    puts "Successfully imported #{customer.first_name} #{customer.last_name}"
  rescue StandardError => e
    failed_imports += 1
    puts "Error importing row: #{row['first_name']} #{row['last_name']}"
    puts "Error: #{e.message}"
    puts e.backtrace.first(5)
  end
end

puts "\nImport completed!"
puts "Successfully imported: #{successful_imports} customers"
puts "Failed imports: #{failed_imports}"
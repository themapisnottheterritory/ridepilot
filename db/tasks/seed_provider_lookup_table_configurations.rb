[
  {
    name: 'funding_sources',
    caption: 'Funding Source',
    value_column_name: 'name'
  },
  {
    name: 'vehicle_warranty_templates',
    caption: 'Vehicle Warranty',
    value_column_name: 'name'
  },
  {
    name: 'ada_questions',
    caption: 'ADA Eligibility Question (yes/no)',
    value_column_name: 'name'
  },
  {
    name: 'vehicle_inspections',
    caption: 'Vehicle Inspection (yes/no question)',
    value_column_name: 'description'
  },
  {
    name: 'dispatcher_message_templates',
    caption: 'Common Dispatcher Message',
    value_column_name: 'message'
  },
  {
    name: 'driver_message_templates',
    caption: 'Common Driver Message',
    value_column_name: 'message'
  }
].each do | config_data|
  config = ProviderLookupTable.find_by(name: config_data[:name])
  if config 
    config.update(config_data)
  else
    ProviderLookupTable.create(config_data)
  end
end
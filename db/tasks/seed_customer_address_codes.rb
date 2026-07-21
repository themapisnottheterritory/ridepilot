[
  {
    code: 'CH',
    name: 'Customer Home'
  },
  {
    code: 'CW',
    name: 'Customer Work'
  },
  {
    code: 'CD',
    name: 'Customer Doctor'
  },
  {
    code: 'CS',
    name: 'Customer School'
  },
  {
    code: 'CC',
    name: 'Customer Church'
  },
].each do |addr_type|
  item = CustomerAddressType.where(code: addr_type[:code]).first_or_create
  item.update name: addr_type[:name]
end
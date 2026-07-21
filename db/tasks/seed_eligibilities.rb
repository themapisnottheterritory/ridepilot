[
  {
    code: 'veteran',
    description: 'Veteran'
  },
  {
    code: 'disabled',
    description: 'Disabled'
  }, 
  {
    code: 'low_income',
    description: 'Low Income'
  }, 
  {
    code: 'nemt_eligible',
    description: 'Medicaid'
  }
].each do |eligible_data|
  item = Eligibility.where(code: eligible_data[:code]).first_or_create
  item.update description: eligible_data[:description]
end
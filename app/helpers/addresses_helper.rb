module AddressesHelper
  # What every row of a provider common address table needs that doesn't depend on the row.
  def provider_common_address_row_context
    {
      can_edit_common: can?(:edit, ProviderCommonAddress),
      can_edit_address: can?(:edit, Address),
      unspecified: translate_helper("unspecified"),
      in_district: translate_helper("in_district"),
      out_of_district: translate_helper("out_of_district"),
      edit: translate_helper("edit")
    }
  end
end

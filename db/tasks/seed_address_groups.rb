# Address groups (categories) for the provider common-address book.
#
# The default/unknown bucket (AddressGroup::UNKNOWN_TYPE = "Needs Update") MUST
# exist -- ProviderCommonAddress validates address_group_id presence and the
# loader falls back to it. The remaining categories reflect actual GCRPC trip
# patterns so curated destinations land in a meaningful group instead of all
# piling into "Needs Update".
#
# Idempotent: first_or_create keys on the (case-insensitive) unique name.
[
  AddressGroup::UNKNOWN_TYPE,        # "Needs Update" -- default fallback, keep first
  "Dialysis",
  "Medical",
  "Retail & Grocery",
  "Employment",
  "Government & Social Services",
  "Education",
  "Senior Center",
  "Transit"
].each do |group_name|
  AddressGroup.where(name: group_name).first_or_create
end

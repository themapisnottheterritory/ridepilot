# The address check (AddressScan) for the agencies this user works in, with a
# link to fix each one. The same list goes to GCRPC I.T. each morning
# (rake addresses:scan), new items only.
class AddressChecksController < ApplicationController
  def index
    authorize! :read, Run
    ids = current_user.super_admin? ? nil : current_user.roles.pluck(:provider_id)
    @by_kind = AddressScan.new(ids).by_kind
    @providers = Provider.pluck(:id, :name).to_h
  end
end

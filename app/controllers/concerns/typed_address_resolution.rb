# Turning what a dispatcher typed into an address, for the trip form and the
# subscription form (TripsController, RepeatingTripsController#process_address):
# match the rider's saved addresses and the agency's common addresses, else
# geocode the text (relaxing it when the local map lacks the house number),
# optionally save it to the rider ("Save to this customer's addresses"), and
# replace the misleading "can't be blank / must exist" when nothing matched.
# Works on @trip, whichever kind it is.
module TypedAddressResolution
  extend ActiveSupport::Concern

  private

    # "Save to this customer" — when the dispatcher ticks the box on the trip form,
    # persist a freshly-entered address as a reusable CustomerCommonAddress for the
    # customer (instead of a throwaway TempAddress), so it autocompletes on future
    # trips. No-op without a customer or a geocoded location, and never duplicates
    # an address the dispatcher picked from the saved list — that path keeps its
    # *_address_id and skips this whole block. Returns the address to attach.
    def promote_to_customer_common_address(address, name)
      return address unless address && address.the_geom.present?
      return address if address.is_a?(CustomerCommonAddress) && address.persisted?
      customer = @trip.customer || Customer.find_by_id(params[:customer_id])
      return address unless customer

      cca = CustomerCommonAddress.new(
        address:     address.address,
        city:        address.city,
        state:       address.state,
        zip:         address.zip,
        name:        name.presence,
        customer_id: customer.id,
        provider_id: current_provider_id
      )
      cca.the_geom = address.the_geom
      cca
    end

    # When a dispatcher typed an address we could not geocode, the belongs_to
    # "must exist" + presence "can't be blank" errors are misleading — the field
    # wasn't blank, we just couldn't locate it. Replace them with an actionable
    # message so the dispatcher fixes the spelling, picks a suggestion, or drops a
    # pin instead of hunting for an empty box. Called from the create/update error
    # branch after validation has populated @trip.errors.
    def clarify_unresolved_address_errors
      [[:pickup_address, @pickup_address_unresolved, "Pickup address"],
       [:dropoff_address, @dropoff_address_unresolved, "Dropoff address"]].each do |assoc, unresolved, _label|
        next unless unresolved
        @trip.errors.delete(assoc)
        @trip.errors.add(assoc, "couldn't be located — check the spelling, pick a match from the suggestions list, or switch on Lat/Lon to enter coordinates")
      end
    end

    # Fallback address resolution for the dispatcher trip form.
    #
    # The place picker only writes the hidden id/data/lat-lng fields on
    # `typeahead:selected`, and CLEARS them on every `input` event. So a dispatcher
    # who selects a saved place (e.g. "Home (205 King St, Cuero, TX 77954)") and then
    # touches the field again — or hits a browser re-render that fires `input` after
    # the select — submits with a visibly-filled box but blank hidden fields, and the
    # typed address was silently dropped → "Dropoff address must exist / can't be
    # blank". (Reported via Erika, customer Irene Spence.)
    #
    # This resolves the VISIBLE text the same two ways the picker's dropdown does:
    #   1. match one of the customer's saved common addresses (same scope + geom/active
    #      filters as addresses#trippable_autocomplete), else
    #   2. geocode the free text via Nominatim (same source as the picker suggestions).
    # Returns nil when nothing resolves, leaving the existing presence validation to
    # fire so genuinely-empty/bad input still errors.
    def resolve_typed_address(text)
      # Punctuation-insensitive: the picker displays saved places as
      # "Home (205 King St, Cuero, TX 77954)" while Address#text is
      # "Home\n 205 King St \nCuero, TX 77954" — collapse all non-alphanumerics so
      # the parens/commas/newlines don't defeat the match.
      normalize = ->(s) { s.to_s.downcase.gsub(/[^a-z0-9]+/, ' ').strip }
      normalized = normalize.call(text)
      return nil if normalized.blank?

      customer = @trip.customer || Customer.find_by_id(params[:customer_id])

      scope = Address.where.not(the_geom: nil).where('inactive is NULL or inactive != ?', true)
      candidates = []
      if customer
        candidates += scope.where(customer_id: customer.id, type: 'CustomerCommonAddress').to_a
        candidates += scope.where(provider_id: customer.authorized_provider_ids, type: 'ProviderCommonAddress').to_a
      else
        candidates += scope.where(provider_id: current_provider_id, type: 'ProviderCommonAddress').to_a
      end

      match = candidates.find { |a| normalize.call(a.text) == normalized } ||
              candidates.find { |a| normalize.call(a.address_text) == normalized }
      return match if match

      begin
        geo = geocode_relaxed(text)
        if geo
          new_temp_addr = TempAddress.new(geo.select { |k, _| TempAddress.allowable_params.include?(k) })
          new_temp_addr.the_geom = Address.compute_geom(geo['lat'], geo['lon'])
          return new_temp_addr
        end
      rescue => e
        Rails.logger.warn("resolve_typed_address geocode failed for #{text.inspect}: #{e.message}")
      end

      nil
    end

    # Geocode free-typed address text, progressively relaxing the query when the
    # self-hosted Nominatim (Texas OSM) can't match it exactly. Rural TX addresses
    # frequently have no house-number node in OSM — and dispatchers sometimes
    # mistype the ZIP — so an exact "210 Foo St, Cuero, TX 77854" returns nothing
    # even though the street exists. We fall back to street level (drop the house
    # number, then the ZIP, then the state) and re-attach the dispatcher's house
    # number to the matched street, so the trip still saves with a routable
    # location instead of being rejected. (Regression surfaced after the
    # Google -> self-hosted Nominatim migration; Google had house numbers
    # everywhere, the local OSM extract does not.) Returns a stringified attrs
    # hash (address/city/state/zip/lat/lon) or nil.
    def geocode_relaxed(text)
      RelaxedGeocoder.call(text, current_provider)   # shared with the rider's address dialog
    end
end

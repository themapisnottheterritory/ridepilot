// initialize a place picker to query saved places and Nominatim suggestions
function init_place_picker(dom_selector, query_bounds, query_restrictions) {
  var saved_places = new Bloodhound({
    datumTokenizer: function(d) {
     return  Bloodhound.tokenizers.whitespace(d.value);
    },
    queryTokenizer: Bloodhound.tokenizers.whitespace,
    remote: {
      url: '/trip_address_autocomplete.json?',
      rateLimitWait: 600,
      replace: function(url, query) {
        url = url + '&customer_id=' + $("input.trip-customer-id").val() + '&term=' + query;
        return url;
      }
    },
    limit: 10
  });

  saved_places.initialize();

  // Nominatim-based suggestion source. Goes through geocode_suggest, which
  // applies the provider viewbox and retries via Nominatim's structured search
  // when free text finds nothing (see AddressesController#geocode_suggest);
  // query_bounds is now applied server-side.
  var nominatim_places = new Bloodhound({
    datumTokenizer: Bloodhound.tokenizers.whitespace,
    queryTokenizer: Bloodhound.tokenizers.whitespace,
    remote: {
      url: '/addresses/geocode_suggest?q=%QUERY',
      rateLimitWait: 300,
      filter: function(results) {
        return results.map(function(r) {
          r.description = r.display_name;
          return r;
        });
      }
    }
  });

  nominatim_places.initialize();

  $(dom_selector).typeahead({
    highlight: true
  },
    {
      name: 'saved_places',
      displayKey: "label",
      source: saved_places.ttAdapter(),
      templates: {
        header: '<h4>Saved Addresses</h4>',
        suggestion: saved_place_suggestion
      }
    },
    {
      name: 'nominatim_places',
      displayKey: "description",
      source: nominatim_places.ttAdapter(),
      templates: {
        header: '<h4>Address Suggestions</h4>',
        suggestion: Handlebars.compile([
          '<a>{{description}}</a>'
        ].join(''))
      }
    });
}

// One saved place in the picker: its name, the street under it, and its town
// as a badge on the right (AddressesController#in_riders_town_first): green
// for the rider's own town, amber for another town with the miles from home.
// Several places share a name across towns (Walmart, Dialysis, the senior
// center), and the town at the end of a long line was easy to miss.
function saved_place_suggestion(place) {
  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, function(c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }
  var name = place.name || place.address || place.label;
  var street = place.name ? place.address : '';
  var badge = '';
  if (place.town) {
    var kind = place.home_town === true ? ' pp-home' : (place.home_town === false ? ' pp-away' : '');
    badge = '<span class="pp-town' + kind + '">' + esc(place.town) + '</span>';
    if (place.home_town === false && place.miles_from_home != null) {
      badge += '<span class="pp-dist">about ' + esc(place.miles_from_home) + ' mi from home</span>';
    }
  }
  return '<div class="pp-row"><div class="pp-main"><span class="pp-name">' + esc(name) + '</span>' +
    (street ? '<span class="pp-street">' + esc(street) + '</span>' : '') + '</div>' +
    (badge ? '<div class="pp-side">' + badge + '</div>' : '') + '</div>';
}

function process_nominatim_address(addr, type) {
  var parsed = nominatimToAddress(addr);
  $('input.trip_' + type + '_address_data').val(JSON.stringify(parsed));
}

// Wire one address box (pickup or dropoff) to its hidden fields.
//
// The box shows a label -- "Home (2501 E Mockingbird Ln APT 3502 Victoria, TX
// 77904)" -- while the address the trip actually saves lives in a hidden field
// that is only set by clicking a suggestion. Typing has to drop that binding,
// or an edited box would submit the address that was there before.
//
// What it must not do is make an accidental edit unrecoverable, and it used to.
// Backspacing the closing bracket unbound the address; typing the bracket back
// left the box looking correct with nothing behind it, and the label does not
// geocode, so re-picking from the dropdown was the only way out. A dispatcher
// who does not spot that abandons the form and starts the trip again, which is
// how one rider ended up with three identical standing trips. Restoring the
// binding when the text returns to what was loaded costs nothing and removes
// the trap.
function bind_address_field(type) {
  var $text = $('#' + type + '_address');
  if (!$text.length) { return; }

  var $id    = $('input.trip_' + type + '_address_id');
  var $data  = $('input.trip_' + type + '_address_data');
  var $notes = $('#' + type + '_address_notes');
  var $lat   = $('#trip_' + type + '_lat');
  var $lon   = $('#trip_' + type + '_lon');

  // The text the box was loaded with, and the binding that belongs to it.
  var bound = {};
  function remember() {
    bound = {text: $text.val(), id: $id.val(), data: $data.val(), notes: $notes.val()};
  }
  function unbind() {
    $id.val('');
    $data.val('');
    $notes.val('');
  }
  remember();

  $text.on('input', function() {
    $lat.val('');
    $lon.val('');
    if ($text.val() === bound.text) {
      $id.val(bound.id);
      $data.val(bound.data);
      $notes.val(bound.notes);
    } else {
      unbind();
    }
  });

  $lat.add($lon).on('input', unbind);

  $text.on('typeahead:selected', function(e, addr, source) {
    // Clear first: switching from a saved address to a geocoded one otherwise
    // leaves the old id set, and the server prefers the id over the new data.
    unbind();
    if (source == 'saved_places') {
      $id.val(addr.id);
      $notes.val(addr.notes);
      if (type === 'dropoff') { $('.trip_purpose_id').val(addr.trip_purpose_id); }
    } else if (source == 'nominatim_places') {
      process_nominatim_address(addr, type);
    }
    // A fresh pick is the new thing to restore to. Deferred because typeahead
    // writes the box's value around this event, not before it.
    setTimeout(remember, 0);
  });
}

$(function() {
  bind_address_field('pickup');
  bind_address_field('dropoff');
});

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

  // Nominatim-based suggestion source
  var nominatim_url = $('meta[name="nominatim-url"]').attr('content') || 'http://10.0.0.18:8088';
  var viewboxParam = '';
  if (query_bounds && query_bounds.min_lat) {
    viewboxParam = '&viewbox=' + query_bounds.min_lon + ',' + query_bounds.max_lat + ',' + query_bounds.max_lon + ',' + query_bounds.min_lat + '&bounded=1';
  }

  var nominatim_places = new Bloodhound({
    datumTokenizer: Bloodhound.tokenizers.whitespace,
    queryTokenizer: Bloodhound.tokenizers.whitespace,
    remote: {
      url: nominatim_url + '/search?format=json&addressdetails=1&countrycodes=us&limit=5&q=%QUERY' + viewboxParam,
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
        suggestion: Handlebars.compile([
          '<a>{{label}}</a>'
        ].join(''))
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

function process_nominatim_address(addr, type) {
  var parsed = nominatimToAddress(addr);
  $('input.trip_' + type + '_address_data').val(JSON.stringify(parsed));
}

$(function() {
  $('#pickup_address').on('input', function() {
    $('#trip_pickup_lat').val('');
    $('#trip_pickup_lon').val('');
    $('input.trip_pickup_address_id').val('');
    $('input.trip_pickup_address_data').val('');
    $('#pickup_address_notes').val('');
  });

  $('#trip_pickup_lat, #trip_pickup_lon').on('input', function() {
    $('input.trip_pickup_address_id').val('');
    $('input.trip_pickup_address_data').val('');
    $('#pickup_address_notes').val('');
  });

  $('#pickup_address').on('typeahead:selected', function(e, addr, data) {
    if(data == 'saved_places') {
      $('input.trip_pickup_address_id').val(addr.id);
      $('#pickup_address_notes').val(addr.notes);
    } else if (data == 'nominatim_places') {
      process_nominatim_address(addr, 'pickup');
    }
  });

  $('#dropoff_address').on('input', function() {
    $('#trip_dropoff_lat').val('');
    $('#trip_dropoff_lon').val('');
    $('input.trip_dropoff_address_id').val('');
    $('input.trip_dropoff_address_data').val('');
    $('#dropoff_address_notes').val('');
  });

  $('#trip_dropoff_lat, #trip_dropoff_lon').on('input', function() {
    $('input.trip_dropoff_address_id').val('');
    $('input.trip_dropoff_address_data').val('');
    $('#dropoff_address_notes').val('');
  });

  $('#dropoff_address').on('typeahead:selected', function(e, addr, data) {
    $('input.trip_dropoff_address_id').val('');
    $('input.trip_dropoff_address_data').val('');
    if(data == 'saved_places') {
      $('input.trip_dropoff_address_id').val(addr.id);
      $('.trip_purpose_id').val(addr.trip_purpose_id);
      $('#dropoff_address_notes').val(addr.notes);
    } else if (data == 'nominatim_places') {
      process_nominatim_address(addr, 'dropoff');
    }
  });
});

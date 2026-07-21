// Nominatim-based address autocomplete replacing Google geocomplete
// Provides $.fn.nominatimComplete() and nominatimToAddress() utility

(function($) {
  var NOMINATIM_URL = $('meta[name="nominatim-url"]').attr('content') || 'http://10.0.0.18:8088';

  // Parse a Nominatim result into RidePilot address format
  // (same output shape as googlePlaceParser)
  function nominatimToAddress(result) {
    if (!result) return {};

    var addr = result.address || {};
    var streetNumber = addr.house_number || '';
    var road = addr.road || '';
    var streetAddress = (streetNumber + ' ' + road).trim();
    if (!streetAddress && result.display_name) {
      streetAddress = result.display_name.split(',')[0];
    }

    return {
      address: streetAddress,
      city: addr.city || addr.town || addr.village || addr.hamlet || '',
      state: addr.state ? stateAbbrev(addr.state) : '',
      zip: addr.postcode || '',
      lat: parseFloat(result.lat),
      lon: parseFloat(result.lon)
    };
  }

  // US state name to 2-letter abbreviation
  var STATE_ABBREVS = {
    'ALABAMA':'AL','ALASKA':'AK','ARIZONA':'AZ','ARKANSAS':'AR','CALIFORNIA':'CA',
    'COLORADO':'CO','CONNECTICUT':'CT','DELAWARE':'DE','DISTRICT OF COLUMBIA':'DC',
    'FLORIDA':'FL','GEORGIA':'GA','HAWAII':'HI','IDAHO':'ID','ILLINOIS':'IL',
    'INDIANA':'IN','IOWA':'IA','KANSAS':'KS','KENTUCKY':'KY','LOUISIANA':'LA',
    'MAINE':'ME','MARYLAND':'MD','MASSACHUSETTS':'MA','MICHIGAN':'MI','MINNESOTA':'MN',
    'MISSISSIPPI':'MS','MISSOURI':'MO','MONTANA':'MT','NEBRASKA':'NE','NEVADA':'NV',
    'NEW HAMPSHIRE':'NH','NEW JERSEY':'NJ','NEW MEXICO':'NM','NEW YORK':'NY',
    'NORTH CAROLINA':'NC','NORTH DAKOTA':'ND','OHIO':'OH','OKLAHOMA':'OK','OREGON':'OR',
    'PENNSYLVANIA':'PA','RHODE ISLAND':'RI','SOUTH CAROLINA':'SC','SOUTH DAKOTA':'SD',
    'TENNESSEE':'TN','TEXAS':'TX','UTAH':'UT','VERMONT':'VT','VIRGINIA':'VA',
    'WASHINGTON':'WA','WEST VIRGINIA':'WV','WISCONSIN':'WI','WYOMING':'WY'
  };

  function stateAbbrev(name) {
    if (!name) return '';
    var upper = name.toUpperCase().trim();
    // Already abbreviated?
    if (upper.length === 2) return upper;
    return STATE_ABBREVS[upper] || name;
  }

  // Debounce helper
  function debounce(fn, delay) {
    var timer;
    return function() {
      var ctx = this, args = arguments;
      clearTimeout(timer);
      timer = setTimeout(function() { fn.apply(ctx, args); }, delay);
    };
  }

  // jQuery plugin: replaces $.fn.geocomplete()
  $.fn.nominatimComplete = function(options) {
    options = options || {};

    return this.each(function() {
      var $input = $(this);
      var $dropdown = $('<ul class="nominatim-dropdown"></ul>');
      $input.after($dropdown);
      $input.css('position', 'relative');

      // Build viewbox query param from bounds
      var viewboxParam = '';
      if (options.bounds) {
        var b = options.bounds;
        viewboxParam = '&viewbox=' + b.min_lon + ',' + b.max_lat + ',' + b.max_lon + ',' + b.min_lat + '&bounded=1';
      }

      var fetchResults = debounce(function() {
        var query = $input.val();
        if (query.length < 3) {
          $dropdown.hide().empty();
          return;
        }

        var url = NOMINATIM_URL + '/search?format=json&addressdetails=1&countrycodes=us&limit=5&q=' + encodeURIComponent(query) + viewboxParam;

        $.getJSON(url, function(results) {
          $dropdown.empty();
          if (!results || results.length === 0) {
            $dropdown.hide();
            return;
          }

          results.forEach(function(result) {
            var $li = $('<li></li>').text(result.display_name).data('result', result);
            $dropdown.append($li);
          });
          $dropdown.show();
        }).fail(function() {
          $dropdown.hide().empty();
        });
      }, 300);

      $input.on('input', fetchResults);

      // Handle selection
      $dropdown.on('click', 'li', function() {
        var result = $(this).data('result');
        $input.val(result.display_name);
        $dropdown.hide().empty();

        var addressData = nominatimToAddress(result);
        $input.trigger('geocode:result', [addressData]);
      });

      // Keyboard navigation
      $input.on('keydown', function(e) {
        var $items = $dropdown.find('li');
        var $active = $dropdown.find('li.active');
        var idx = $items.index($active);

        if (e.keyCode === 40) { // down
          e.preventDefault();
          $items.removeClass('active');
          idx = (idx + 1) % $items.length;
          $items.eq(idx).addClass('active');
        } else if (e.keyCode === 38) { // up
          e.preventDefault();
          $items.removeClass('active');
          idx = idx <= 0 ? $items.length - 1 : idx - 1;
          $items.eq(idx).addClass('active');
        } else if (e.keyCode === 13) { // enter
          if ($active.length) {
            e.preventDefault();
            $active.trigger('click');
          }
        } else if (e.keyCode === 27) { // escape
          $dropdown.hide().empty();
        }
      });

      // Hide dropdown on outside click
      $(document).on('click', function(e) {
        if (!$(e.target).closest($input.add($dropdown)).length) {
          $dropdown.hide().empty();
        }
      });
    });
  };

  // Export for global use
  window.nominatimToAddress = nominatimToAddress;
  window.NOMINATIM_URL = NOMINATIM_URL;

})(jQuery);

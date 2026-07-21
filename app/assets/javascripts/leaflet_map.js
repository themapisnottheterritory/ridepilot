function LeafletMap(map_container, unparsed_bounds, unparsed_viewport) {
  var self = this;
  this.map_container = map_container;
  this.map = null;
  this.bounds = null;
  this.viewport = null;
  this.errors = [];

  this.init = function (unparsed_bounds, unparsed_viewport) {
    // Validate bounds options
    if (unparsed_bounds.north < unparsed_bounds.south) self.errors.push('North latitude must be greater than south.');
    if (unparsed_bounds.east < unparsed_bounds.west) self.errors.push('East longitude must be greater than west.');
    if (Math.abs(unparsed_bounds.north) > 90) self.errors.push('North latitude is invalid.');
    if (Math.abs(unparsed_bounds.west) > 180) self.errors.push('West longitude is invalid.');
    if (Math.abs(unparsed_bounds.south) > 90) self.errors.push('South latitude is invalid.');
    if (Math.abs(unparsed_bounds.east) > 180) self.errors.push('East longitude is invalid.');

    // Validate viewport options
    if (Math.abs(unparsed_viewport.center_lat) > 90) self.errors.push('Center latitude is invalid.');
    if (Math.abs(unparsed_viewport.center_lng) > 180) self.errors.push('Center longitude is invalid.');
    if (unparsed_viewport.zoom < 0 || unparsed_viewport.zoom >= 20) self.errors.push('Zoom must be between 0 and 19.');

    if (self.errors.length === 0) {
      self.bounds = L.latLngBounds(
        L.latLng(unparsed_bounds.south, unparsed_bounds.west),
        L.latLng(unparsed_bounds.north, unparsed_bounds.east)
      );
      self.viewport = {
        center: L.latLng(unparsed_viewport.center_lat, unparsed_viewport.center_lng),
        zoom: unparsed_viewport.zoom
      };
    } else {
      console.log(self.errors);
    }
  };

  this.create_map = function (center, zoom) {
    var opts = {};
    if (center) opts.center = center;
    if (zoom) opts.zoom = zoom;
    self.map = L.map(self.map_container[0], opts);
    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
      attribution: '&copy; OpenStreetMap contributors',
      maxZoom: 19
    }).addTo(self.map);
  };

  // Display a map region
  this.display_region = function () {
    if (self.errors.length > 0) return self.errors;
    self.create_map();
    self.map.fitBounds(self.bounds);
    L.rectangle(self.bounds, {
      color: '#598FEF',
      weight: 2,
      fillColor: '#E5F2FF',
      fillOpacity: 0.3
    }).addTo(self.map);

    return null;
  };

  this.display_viewport = function () {
    if (self.errors.length > 0) return self.errors;
    self.create_map(self.viewport.center, self.viewport.zoom);
    self.map.panTo(self.viewport.center);
    this.add_marker(self.viewport.center);

    return null;
  };

  this.add_marker = function (center) {
    var marker = L.marker(center).addTo(self.map);
    return marker;
  };

  this.init(unparsed_bounds, unparsed_viewport);
}

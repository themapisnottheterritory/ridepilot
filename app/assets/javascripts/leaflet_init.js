// Fix Leaflet default marker icon paths for Rails asset pipeline
if (typeof L !== 'undefined') {
  delete L.Icon.Default.prototype._getIconUrl;
  L.Icon.Default.mergeOptions({
    iconRetinaUrl: '/assets/marker-icon-2x.png',
    iconUrl: '/assets/marker-icon.png',
    shadowUrl: '/assets/marker-shadow.png'
  });
}

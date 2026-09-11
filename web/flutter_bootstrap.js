{{flutter_js}}
{{flutter_build_config}}

// Disable service worker so updates are instant and never served from stale cache
_flutter.loader.load({
  serviceWorkerSettings: null
});

{{flutter_js}}
{{flutter_build_config}}

// Append timestamp cache-buster to mainJsPath so browser NEVER caches stale Dart JS
if (window._flutter && window._flutter.buildConfig && window._flutter.buildConfig.builds) {
  window._flutter.buildConfig.builds.forEach(function(b) {
    if (b.mainJsPath) {
      b.mainJsPath = b.mainJsPath + '?v=' + new Date().getTime();
    }
  });
}

// Disable service worker so updates are instant and never served from stale cache
_flutter.loader.load({
  serviceWorkerSettings: null
});

{{flutter_js}}
{{flutter_build_config}}

(function () {
  var stamp = window.__PMCHAT_BUILD_STAMP || Date.now().toString();
  var buildConfig = window._flutter && window._flutter.buildConfig;

  if (buildConfig && Array.isArray(buildConfig.builds)) {
    buildConfig.builds = buildConfig.builds.map(function (build) {
      if (!build) return build;
      var versioned = Object.assign({}, build);
      if (build.mainJsPath === 'main.dart.js') {
        versioned.mainJsPath = 'main.dart.js?v=' + encodeURIComponent(stamp);
      }
      if (build.mainWasmPath === 'main.dart.wasm') {
        versioned.mainWasmPath = 'main.dart.wasm?v=' + encodeURIComponent(stamp);
      }
      if (build.jsSupportRuntimePath === 'main.dart.mjs') {
        versioned.jsSupportRuntimePath = 'main.dart.mjs?v=' +
          encodeURIComponent(stamp);
      }
      return versioned;
    });
  }

  _flutter.loader.load();
})();

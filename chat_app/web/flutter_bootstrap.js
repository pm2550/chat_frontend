{{flutter_js}}
{{flutter_build_config}}

(function () {
  var stamp = window.__PMCHAT_BUILD_STAMP || Date.now().toString();
  var buildConfig = window._flutter && window._flutter.buildConfig;

  if (buildConfig && Array.isArray(buildConfig.builds)) {
    buildConfig.builds = buildConfig.builds.map(function (build) {
      if (!build || build.mainJsPath !== 'main.dart.js') return build;
      return Object.assign({}, build, {
        mainJsPath: 'main.dart.js?v=' + encodeURIComponent(stamp),
      });
    });
  }

  _flutter.loader.load();
})();

#!/usr/bin/env bash
set -euo pipefail

cache_dir="${PUB_CACHE:-$HOME/.pub-cache}"
shopt -s nullglob

for plugin_dir in "$cache_dir"/hosted/pub.dev/flutter_sound-*/linux; do
  cmake_file="$plugin_dir/CMakeLists.txt"
  include_dir="$plugin_dir/include/flutter_sound"
  header_file="$include_dir/flutter_sound_plugin.h"

  if [[ ! -f "$cmake_file" ]]; then
    continue
  fi

  # flutter_sound 9.x declares FlutterSoundPlugin in pubspec.yaml, while the
  # Linux CMake target and exported header are named taudio_plugin. Flutter's
  # generated_plugins.cmake expects flutter_sound_plugin, so normalize the
  # plugin cache before desktop CI builds.
  perl -0pi -e 's/set\(PLUGIN_NAME "taudio_plugin"\)/set(PLUGIN_NAME "flutter_sound_plugin")/' "$cmake_file"
  perl -0pi -e 's/set\(taudio_bundled_libraries/set(flutter_sound_bundled_libraries/' "$cmake_file"

  mkdir -p "$include_dir"
  cat > "$header_file" <<'EOF'
#ifndef FLUTTER_PLUGIN_FLUTTER_SOUND_PLUGIN_H_
#define FLUTTER_PLUGIN_FLUTTER_SOUND_PLUGIN_H_

#include <taudio/taudio_plugin.h>

#define flutter_sound_plugin_register_with_registrar \
  taudio_plugin_register_with_registrar

#endif  // FLUTTER_PLUGIN_FLUTTER_SOUND_PLUGIN_H_
EOF
done

#!/usr/bin/env bash
# 检查按 ABI 拆出来的 APK：每个包只带一套原生库、versionCode 就是 pubspec 的版本号
# （不带 Flutter 默认的 +1000/+2000 偏移，App 要拿它和服务器的 latestVersionCode 比），
# 并且放得进服务器的上传上限。打印大小和 versionCode，构建日志里能直接看到。
#
# 用法: check_split_apks.sh <expected-version-code> <apk>...
set -euo pipefail

expected_code="$1"
shift

# nginx client_max_body_size 100m
max_bytes=$((100 * 1024 * 1024))

sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
aapt2=""
if [ -n "$sdk" ] && [ -d "$sdk/build-tools" ]; then
  latest="$(ls "$sdk/build-tools" | sort -V | tail -n 1)"
  if [ -x "$sdk/build-tools/$latest/aapt2" ]; then
    aapt2="$sdk/build-tools/$latest/aapt2"
  fi
fi
if [ -z "$aapt2" ]; then
  echo "::error::aapt2 not found under \$ANDROID_HOME/build-tools; cannot verify APK versionCode"
  exit 1
fi

status=0
for apk in "$@"; do
  name="$(basename "$apk")"
  size="$(stat -c %s "$apk")"
  code="$("$aapt2" dump badging "$apk" | sed -n "s/.*versionCode='\([0-9]*\)'.*/\1/p" | head -n 1)"
  abis="$(unzip -Z1 "$apk" | sed -n 's#^lib/\([^/]*\)/.*#\1#p' | sort -u | tr '\n' ' ')"
  echo "APK ${name}: ${size} bytes ($((size / 1024 / 1024)) MiB), versionCode=${code}, native ABIs: ${abis}"

  case "$name" in
    pm-chat-android-arm64-v8a-*) want_abi="arm64-v8a" ;;
    pm-chat-android-armeabi-v7a-*) want_abi="armeabi-v7a" ;;
    *) echo "::error::unexpected APK name ${name}"; status=1; continue ;;
  esac

  if [ "$code" != "$expected_code" ]; then
    echo "::error::${name} has versionCode ${code}, expected ${expected_code} (the split-per-abi offset must be overridden)"
    status=1
  fi
  if [ "$(echo "$abis" | xargs)" != "$want_abi" ]; then
    echo "::error::${name} should only contain lib/${want_abi}, found: ${abis}"
    status=1
  fi
  if [ "$size" -gt "$max_bytes" ]; then
    echo "::error::${name} is ${size} bytes, over the 100 MiB upload limit"
    status=1
  fi
done
exit "$status"

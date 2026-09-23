#!/usr/bin/env bash
# 在模拟器里跑：装 APK → 写登录态 → 启动 → 检查常驻服务 → 切后台 → 让对方发消息/来电 → 检查系统通知。
set -uo pipefail
PKG=com.pm2550.chat
OUT=smoke-out
FAIL=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; FAIL=1; fi; }

adb wait-for-device
adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb shell pm grant $PKG android.permission.POST_NOTIFICATIONS
adb shell pm grant $PKG android.permission.RECORD_AUDIO
# 真机上 App 会自己弹系统框申请；这里预先加白名单，避免系统框挡住自动化。
adb shell dumpsys deviceidle whitelist +$PKG

adb push $OUT/FlutterSharedPreferences.xml /data/local/tmp/pmchat_prefs.xml
adb shell "run-as $PKG sh -c 'mkdir -p shared_prefs && cat /data/local/tmp/pmchat_prefs.xml > shared_prefs/FlutterSharedPreferences.xml'"

adb logcat -c
adb shell monkey -p $PKG -c android.intent.category.LAUNCHER 1
sleep 45

check "App 进程在运行" "adb shell pidof $PKG >/dev/null"
adb shell dumpsys activity services $PKG > $OUT/services.txt
check "后台常驻服务已启动" "grep -q 'ForegroundService' $OUT/services.txt"
adb shell dumpsys notification --noredact > $OUT/notifications-1.txt
check "常驻通知已显示" "grep -q 'PM chat 正在后台运行' $OUT/notifications-1.txt"

# 切到后台（按 Home 键），前台连接会断开，服务器改走后台连接
adb shell input keyevent KEYCODE_HOME
sleep 8
MSG="CI后台通知$(date +%s)"
python3 scripts/ci/android_smoke_peer.py send-message "$MSG"
sleep 12
adb shell dumpsys notification --noredact > $OUT/notifications-2.txt
check "切后台后收到新消息通知" "grep -q '$MSG' $OUT/notifications-2.txt"

python3 scripts/ci/android_smoke_peer.py call &
sleep 10
adb shell dumpsys notification --noredact > $OUT/notifications-3.txt
check "切后台后收到来电通知" "grep -q '来电' $OUT/notifications-3.txt"
wait

adb logcat -d > $OUT/logcat.txt
check "没有崩溃" "! grep -q 'FATAL EXCEPTION' $OUT/logcat.txt"
check "App 仍在运行" "adb shell pidof $PKG >/dev/null"

exit $FAIL

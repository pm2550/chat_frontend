#!/usr/bin/env bash
# 在模拟器里跑：装 APK → 写登录态 → 启动 → 检查常驻服务 → 切后台 → 让对方发消息/来电 → 检查系统通知。
set -uo pipefail
PKG=com.pm2550.chat
OUT=smoke-out
FAIL=0
# 模拟器偶尔会卡死，adb 命令都加超时，别把整个任务拖到 45 分钟上限
ADB_BIN=$(command -v adb)
adb() { timeout 180 "$ADB_BIN" "$@"; }
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

# 回到前台再测保存别人发的图片（放在最后：CI 模拟器偶尔中途掉线，别连累前面的通知检查）：
adb shell monkey -p $PKG -c android.intent.category.LAUNCHER 1
sleep 8
# 对方发图 → 进聊天 → 点开大图 → 点"保存图片" → 系统相册里应出现这张图
IMG="cisave$(date +%s)"
python3 scripts/ci/android_smoke_peer.py send-image "$IMG"
sleep 8
python3 scripts/ci/android_smoke_ui.py dump $OUT/ui-chatlist.txt
check "聊天列表能加载" "! grep -q '加载失败' $OUT/ui-chatlist.txt"
PEER=$(python3 -c "import json;print(json.load(open('$OUT/smoke.json'))['peer_name'])")
python3 scripts/ci/android_smoke_ui.py tap-text "$PEER"
sleep 10
python3 scripts/ci/android_smoke_ui.py dump $OUT/ui-chat.txt
python3 scripts/ci/android_smoke_ui.py tap-image
sleep 6
python3 scripts/ci/android_smoke_ui.py dump $OUT/ui-preview.txt
python3 scripts/ci/android_smoke_ui.py tap-text "保存图片"
sleep 2
python3 scripts/ci/android_smoke_ui.py dump $OUT/ui-after-save.txt
sleep 3
adb shell content query --uri content://media/external/images/media --projection _display_name:relative_path > $OUT/media.txt
check "别人发的图片能保存到相册" "grep -q '$IMG' $OUT/media.txt"
# 提示条只显示几秒，读界面树又慢，这里只记录不判失败（位置由组件测试保证）
grep -q '已保存到相册' $OUT/ui-after-save.txt && echo "INFO  看到了已保存到相册提示" || echo "INFO  没抓到保存提示（可能已消失）"
adb shell input keyevent KEYCODE_BACK
sleep 2
adb shell input keyevent KEYCODE_BACK
sleep 2

adb logcat -d > $OUT/logcat.txt
check "没有崩溃" "! grep -q 'FATAL EXCEPTION' $OUT/logcat.txt"
check "App 仍在运行" "adb shell pidof $PKG >/dev/null"

exit $FAIL

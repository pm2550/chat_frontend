#!/usr/bin/env python3
"""用 uiautomator 读 Flutter 的无障碍树，按文字/描述点界面元素。

用法:
  android_smoke_ui.py tap-text <正则>     点第一个 text 或 content-desc 匹配的节点
  android_smoke_ui.py tap-image           点消息区里最大的一块可点击区域（聊天图片）
  android_smoke_ui.py dump <文件>          保存当前界面树
"""
import re
import subprocess
import sys
import time
import xml.etree.ElementTree as ET


def dump():
    for _ in range(5):
        xml = subprocess.run(["adb", "exec-out", "uiautomator", "dump", "/dev/tty"],
                             capture_output=True, text=True).stdout
        xml = xml[: xml.rfind(">") + 1] if ">" in xml else ""
        if xml.startswith("<?xml"):
            return ET.fromstring(xml)
        time.sleep(2)
    raise SystemExit("uiautomator dump failed")


def bounds(node):
    x1, y1, x2, y2 = map(int, re.findall(r"\d+", node.get("bounds")))
    return x1, y1, x2, y2


def tap(node):
    x1, y1, x2, y2 = bounds(node)
    x, y = (x1 + x2) // 2, (y1 + y2) // 2
    subprocess.run(["adb", "shell", "input", "tap", str(x), str(y)], check=True)
    print(f"tap {x},{y} {node.get('text')!r} {node.get('content-desc')!r}")


def main():
    cmd = sys.argv[1]
    if cmd == "dump":
        root = dump()
        with open(sys.argv[2], "w") as f:
            f.write(ET.tostring(root, encoding="unicode"))
        return
    for attempt in range(6):
        root = dump()
        nodes = list(root.iter("node"))
        if cmd == "tap-text":
            pattern = re.compile(sys.argv[2])
            hit = [n for n in nodes if pattern.search(n.get("text") or "")
                   or pattern.search(n.get("content-desc") or "")]
            if hit:
                tap(hit[-1] if len(sys.argv) > 3 and sys.argv[3] == "last" else hit[0])
                return
        elif cmd == "tap-image":
            screen = bounds(root.find("node"))
            height = screen[3] - screen[1]
            width = screen[2] - screen[0]
            candidates = []
            for n in nodes:
                if n.get("clickable") != "true":
                    continue
                x1, y1, x2, y2 = bounds(n)
                w, h = x2 - x1, y2 - y1
                # 图片气泡：够大，但不是整屏/整列表；在标题栏下、输入框上
                if w < width * 0.3 or h < height * 0.1 or h > height * 0.7:
                    continue
                if y1 < height * 0.08 or y2 > height * 0.92:
                    continue
                if (n.get("text") or n.get("content-desc")):
                    continue
                candidates.append((w * h, n))
            if candidates:
                tap(max(candidates, key=lambda c: c[0])[1])
                return
        time.sleep(3)
    raise SystemExit(f"{cmd} {sys.argv[2:]} not found")


main()

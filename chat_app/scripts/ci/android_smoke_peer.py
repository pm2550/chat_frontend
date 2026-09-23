#!/usr/bin/env python3
"""对方（B）的动作：send-message 发一条消息；call 发一个来电邀请。"""
import asyncio
import json
import sys

import requests
import websockets

WEB = "https://gateway.chat.pm2550.com"
cfg = json.load(open("smoke-out/smoke.json"))
action, text = sys.argv[1], (sys.argv[2] if len(sys.argv) > 2 else "")

if action == "send-message":
    r = requests.post(f"{WEB}/api/v1/messages", json={"chatRoomId": cfg["room_id"], "content": text},
                      headers={"Authorization": f"Bearer {cfg['peer_token']}"}, timeout=30)
    print("send-message", r.status_code)
elif action == "send-image":
    # text = 文件名（不含扩展名），用来在系统相册里找它
    import io
    import struct
    import zlib

    def png(w, h, rgb):
        raw = b"".join(b"\x00" + bytes(rgb) * w for _ in range(h))
        def chunk(tag, data):
            return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data))
        return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))

    r = requests.post(f"{WEB}/api/v1/messages/file",
                      data={"chatRoomId": str(cfg["room_id"]), "messageType": "IMAGE"},
                      files={"file": (f"{text}.png", png(640, 480, (30, 140, 220)), "image/png")},
                      headers={"Authorization": f"Bearer {cfg['peer_token']}"}, timeout=60)
    print("send-image", r.status_code)
elif action == "call":
    async def call():
        async with websockets.connect(f"wss://gateway.chat.pm2550.com/api/ws?token={cfg['peer_token']}") as ws:
            await ws.send(json.dumps({"type": "call", "action": "join", "chatRoomId": cfg["room_id"],
                                      "callId": "ci-smoke-call", "mediaType": "AUDIO"}))
            await ws.send(json.dumps({"type": "call", "action": "invite", "chatRoomId": cfg["room_id"],
                                      "callId": "ci-smoke-call", "toUserId": cfg["app_user_id"],
                                      "mediaType": "AUDIO"}))
            await asyncio.sleep(12)
    asyncio.run(call())
    print("call sent")

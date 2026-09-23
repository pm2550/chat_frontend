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

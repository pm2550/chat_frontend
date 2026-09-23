#!/usr/bin/env python3
"""冒烟测试用的两个账号：A 装在模拟器里（写好登录态），B 负责给 A 发消息、打电话。"""
import json
import os
import uuid

import requests

WEB = "https://gateway.chat.pm2550.com"
OUT = "smoke-out"


def post(path, body=None, token=None):
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    return requests.post(f"{WEB}{path}", json=body, headers=headers, timeout=30)


def account(tag):
    suffix = uuid.uuid4().hex[:8]
    username, password = f"ci{tag}_{suffix}", "CiSmoke1234"
    post("/api/auth/register", {"username": username, "password": password,
                                "email": f"{username}@t.com", "displayName": f"CI{tag}{suffix[:4]}"})
    return post("/api/auth/login", {"username": username, "password": password}).json()["data"]


os.makedirs(OUT, exist_ok=True)
a, b = account("a"), account("b")
room = post(f"/api/v1/chat-rooms/private/{a['user']['id']}", None, b["accessToken"]).json()
room_id = ((room.get("data") or {}).get("chatRoom") or room.get("chatRoom") or room.get("data"))["id"]


def xml_escape(text):
    return (text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
            .replace('"', "&quot;"))


prefs = f"""<?xml version='1.0' encoding='utf-8' standalone='yes' ?>
<map>
    <string name="flutter.access_token">{xml_escape(a['accessToken'])}</string>
    <string name="flutter.refresh_token">{xml_escape(a['refreshToken'])}</string>
    <string name="flutter.user_data">{xml_escape(json.dumps(a['user']))}</string>
</map>
"""
with open(f"{OUT}/FlutterSharedPreferences.xml", "w") as f:
    f.write(prefs)
with open(f"{OUT}/smoke.json", "w") as f:
    json.dump({"room_id": room_id, "peer_token": b["accessToken"], "app_user_id": a["user"]["id"],
               "peer_name": b["user"].get("displayName") or b["user"]["username"]}, f)
print(f"room={room_id} app_user={a['user']['id']} peer={b['user']['id']}")

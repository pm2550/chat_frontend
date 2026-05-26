#!/usr/bin/env python3
import json
import os
import pathlib
import subprocess
import sys


def run(args):
    return subprocess.check_output(args, text=True)


def required_env(name):
    value = os.environ.get(name)
    if not value:
        raise SystemExit(f"Missing required environment variable: {name}")
    return value


def login(api_base, username, password):
    body = json.dumps({"username": username, "password": password})
    response = run(
        [
            "curl",
            "-fsS",
            "-X",
            "POST",
            f"{api_base}/api/auth/login",
            "-H",
            "Content-Type: application/json",
            "-d",
            body,
        ]
    )
    data = json.loads(response)
    return data["data"]["accessToken"]


def publish(api_base, token, platform, artifact, version_name, version_code, notes):
    metadata = json.dumps(
        {
            "platform": platform,
            "versionName": version_name,
            "versionCode": int(version_code),
            "forceUpdate": False,
            "releaseNotes": notes,
        },
        separators=(",", ":"),
    )
    subprocess.check_call(
        [
            "curl",
            "-fsS",
            "-X",
            "POST",
            f"{api_base}/api/v1/app/version/publish",
            "-H",
            f"Authorization: Bearer {token}",
            "-F",
            f"metadata={metadata};type=application/json",
            "-F",
            f"artifact=@{artifact}",
        ]
    )
    print(f"published {platform}: {artifact.name}")


def detect_platform(path):
    name = path.name
    if name.startswith("pm-chat-web-") and name.endswith(".zip"):
        return "WEB"
    if name.startswith("pm-chat-android-") and name.endswith(".apk"):
        return "ANDROID"
    if name.startswith("pm-chat-linux-") and name.endswith(".tar.gz"):
        return "LINUX"
    if name.startswith("pm-chat-windows-") and name.endswith(".zip"):
        return "WINDOWS"
    if name.startswith("pm-chat-macos-") and name.endswith(".zip"):
        return "MACOS"
    if name.startswith("pm-chat-ios-") and name.endswith(".ipa"):
        return "IOS"
    return None


def main():
    if len(sys.argv) != 2:
        raise SystemExit("usage: publish_app_versions.py <dist-dir>")

    api_base = required_env("PMCHAT_API_BASE_URL").rstrip("/")
    username = required_env("PMCHAT_ADMIN_USERNAME")
    password = required_env("PMCHAT_ADMIN_PASSWORD")
    version_name = required_env("VERSION_NAME")
    version_code = required_env("VERSION_CODE")
    notes = os.environ.get("RELEASE_NOTES", f"PM chat {version_name}")

    dist_dir = pathlib.Path(sys.argv[1])
    token = login(api_base, username, password)

    published = 0
    for artifact in sorted(dist_dir.rglob("*")):
        if not artifact.is_file():
            continue
        platform = detect_platform(artifact)
        if not platform:
            continue
        publish(api_base, token, platform, artifact, version_name, version_code, notes)
        published += 1

    if published == 0:
        raise SystemExit(f"No publishable artifacts found in {dist_dir}")


if __name__ == "__main__":
    main()

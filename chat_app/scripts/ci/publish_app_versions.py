#!/usr/bin/env python3
"""Mirror built installers to the PM chat server.

Usage: publish_app_versions.py <dist-dir>

Auth (one of):
  PMCHAT_PUBLISH_TOKEN                          -> POST /api/v1/app/version/publish-from-ci (CI)
  PMCHAT_ADMIN_USERNAME + PMCHAT_ADMIN_PASSWORD -> login, POST /api/v1/app/version/publish

Also needs PMCHAT_API_BASE_URL, VERSION_NAME, VERSION_CODE; RELEASE_NOTES is optional.

Android is published per CPU architecture: pm-chat-android-arm64-v8a-v<ver>-<code>.apk and
pm-chat-android-armeabi-v7a-v<ver>-<code>.apk become two ANDROID releases with the same
versionCode and abi=arm64-v8a / armeabi-v7a. A pre-split universal APK
(pm-chat-android-v<ver>-<code>.apk) is still published as ANDROID without abi.

Publishing is idempotent: the server upserts on (platform, versionCode, abi), so re-running
a release overwrites the same rows instead of adding new ones.
"""
import json
import os
import pathlib
import re
import subprocess
import sys

ANDROID_ABIS = ("arm64-v8a", "armeabi-v7a")

_ANDROID_APK = re.compile(
    r"^pm-chat-android-(?:(?P<abi>" + "|".join(re.escape(a) for a in ANDROID_ABIS) + r")-)?v.+\.apk$"
)


def run(args):
    return subprocess.check_output(args, text=True)


def required_env(name):
    value = os.environ.get(name)
    if not value:
        raise SystemExit(f"Missing required environment variable: {name}")
    return value


def detect_artifact(path):
    """Return (platform, abi) for a publishable artifact, or None.

    abi is only set for per-ABI Android APKs; everything else is (platform, None).
    """
    name = path.name
    if name.startswith("pm-chat-android-") and name.endswith(".apk"):
        match = _ANDROID_APK.match(name)
        if not match:
            # e.g. an x86_64 split: not shipped, and must not be served as a universal APK.
            return None
        return "ANDROID", match.group("abi")
    if name.startswith("pm-chat-web-") and name.endswith(".zip"):
        return "WEB", None
    if name.startswith("pm-chat-linux-") and name.endswith(".tar.gz"):
        return "LINUX", None
    if name.startswith("pm-chat-windows-") and name.endswith(".zip"):
        return "WINDOWS", None
    if name.startswith("pm-chat-macos-") and name.endswith(".zip"):
        return "MACOS", None
    if name.startswith("pm-chat-ios-") and name.endswith(".ipa"):
        return "IOS", None
    return None


def detect_platform(path):
    detected = detect_artifact(path)
    return detected[0] if detected else None


def build_metadata(platform, abi, version_name, version_code, notes):
    metadata = {
        "platform": platform,
        "versionName": version_name,
        "versionCode": int(version_code),
        "forceUpdate": False,
        "releaseNotes": notes,
    }
    if abi:
        metadata["abi"] = abi
    return json.dumps(metadata, separators=(",", ":"))


def collect_artifacts(dist_dir):
    """Publishable artifacts under dist_dir as (path, platform, abi), in a stable order.

    The arm64-v8a APK always goes before armeabi-v7a: it is what clients that do not
    report an ABI (<=1.1.51) get, so if anything stops half way it is the one that must
    already be live (see check_published_abi).
    """
    artifacts = []
    for artifact in sorted(pathlib.Path(dist_dir).rglob("*")):
        if not artifact.is_file():
            continue
        detected = detect_artifact(artifact)
        if detected:
            artifacts.append((artifact, detected[0], detected[1]))
    abi_order = {abi: index for index, abi in enumerate(ANDROID_ABIS)}
    artifacts.sort(key=lambda item: abi_order.get(item[2], -1))
    return artifacts


def check_published_abi(response_body, abi):
    """Refuse to go on when the server dropped the abi field.

    A server without per-ABI support ignores the unknown "abi" property and stores every
    APK as the one ANDROID release of that versionCode: publishing the 32-bit APK next
    would replace the 64-bit one for everybody. Stop after the first (arm64) upload instead.
    """
    if not abi:
        return
    try:
        stored = json.loads(response_body).get("version", {}).get("abi")
    except (ValueError, AttributeError):
        stored = None
    if stored != abi:
        raise SystemExit(
            f"Server stored the {abi} APK without an ABI; it does not support per-ABI "
            "Android releases yet. Deploy the backend first, then re-run this publish."
        )


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


def publish_command(api_base, endpoint, token, metadata, artifact):
    return [
        "curl",
        "--retry",
        "3",
        "--retry-delay",
        "5",
        "--fail-with-body",
        "-sSL",
        "-X",
        "POST",
        f"{api_base}{endpoint}",
        "-H",
        f"Authorization: Bearer {token}",
        "-F",
        f"metadata={metadata};type=application/json",
        "-F",
        f"artifact=@{artifact}",
    ]


def main(argv=None, call=run):
    argv = sys.argv if argv is None else argv
    if len(argv) != 2:
        raise SystemExit("usage: publish_app_versions.py <dist-dir>")

    api_base = required_env("PMCHAT_API_BASE_URL").rstrip("/")
    version_name = required_env("VERSION_NAME")
    version_code = required_env("VERSION_CODE")
    notes = os.environ.get("RELEASE_NOTES", f"PM chat {version_name}")

    publish_token = os.environ.get("PMCHAT_PUBLISH_TOKEN")
    if publish_token:
        endpoint = "/api/v1/app/version/publish-from-ci"
        token = publish_token
    else:
        endpoint = "/api/v1/app/version/publish"
        token = login(
            api_base,
            required_env("PMCHAT_ADMIN_USERNAME"),
            required_env("PMCHAT_ADMIN_PASSWORD"),
        )

    artifacts = collect_artifacts(argv[1])
    if not artifacts:
        raise SystemExit(f"No publishable artifacts found in {argv[1]}")

    for artifact, platform, abi in artifacts:
        metadata = build_metadata(platform, abi, version_name, version_code, notes)
        response = call(publish_command(api_base, endpoint, token, metadata, artifact))
        check_published_abi(response, abi)
        label = f"{platform} ({abi})" if abi else platform
        print(f"published {label}: {artifact.name} -> {response.strip()}", flush=True)


if __name__ == "__main__":
    main()

import json
import os
import pathlib
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

import publish_app_versions as pub  # noqa: E402


class DetectArtifactTest(unittest.TestCase):
    def detect(self, name):
        return pub.detect_artifact(pathlib.Path("dist") / name)

    def test_split_android_apks_carry_their_abi(self):
        self.assertEqual(
            self.detect("pm-chat-android-arm64-v8a-v1.1.52-11052.apk"),
            ("ANDROID", "arm64-v8a"),
        )
        self.assertEqual(
            self.detect("pm-chat-android-armeabi-v7a-v1.1.52-11052.apk"),
            ("ANDROID", "armeabi-v7a"),
        )

    def test_legacy_universal_apk_is_android_without_abi(self):
        self.assertEqual(
            self.detect("pm-chat-android-v1.1.51-11051.apk"), ("ANDROID", None)
        )

    def test_unshipped_abi_and_bundles_are_skipped(self):
        # x86_64 分包不发布，也绝不能被当成整包推给用户。
        self.assertIsNone(self.detect("pm-chat-android-x86_64-v1.1.52-11052.apk"))
        self.assertIsNone(self.detect("pm-chat-android-v1.1.52-11052.aab"))
        self.assertIsNone(self.detect("linux-android.log"))

    def test_desktop_platforms_are_unchanged(self):
        self.assertEqual(
            self.detect("pm-chat-windows-x64-v1.1.52-11052.zip"), ("WINDOWS", None)
        )
        self.assertEqual(self.detect("pm-chat-macos-v1.1.52-11052.zip"), ("MACOS", None))
        self.assertEqual(
            self.detect("pm-chat-linux-x64-v1.1.52-11052.tar.gz"), ("LINUX", None)
        )
        self.assertEqual(
            pub.detect_platform(pathlib.Path("pm-chat-android-armeabi-v7a-v1-2.apk")),
            "ANDROID",
        )


class MetadataTest(unittest.TestCase):
    def test_abi_only_sent_for_split_apks(self):
        split = json.loads(pub.build_metadata("ANDROID", "arm64-v8a", "1.1.52", "11052", "n"))
        self.assertEqual(split["abi"], "arm64-v8a")
        self.assertEqual(split["versionCode"], 11052)
        universal = json.loads(pub.build_metadata("WINDOWS", None, "1.1.52", "11052", "n"))
        self.assertNotIn("abi", universal)


class MainTest(unittest.TestCase):
    def test_publishes_both_android_abis_with_the_ci_token(self):
        with tempfile.TemporaryDirectory() as tmp:
            dist = pathlib.Path(tmp)
            (dist / "linux-android").mkdir()
            for name in [
                "linux-android/pm-chat-android-arm64-v8a-v1.1.52-11052.apk",
                "linux-android/pm-chat-android-armeabi-v7a-v1.1.52-11052.apk",
                "linux-android/pm-chat-android-v1.1.52-11052.aab",
                "linux-android/pm-chat-linux-x64-v1.1.52-11052.tar.gz",
                "pm-chat-windows-x64-v1.1.52-11052.zip",
            ]:
                (dist / name).write_bytes(b"x")

            calls = []

            def fake_curl(args):
                calls.append(args)
                metadata = next(a for a in args if a.startswith("metadata="))
                payload = json.loads(metadata[len("metadata="):].split(";type=")[0])
                return json.dumps({"version": {"abi": payload.get("abi")}})

            env = {
                "PMCHAT_API_BASE_URL": "https://chat.example/",
                "PMCHAT_PUBLISH_TOKEN": "secret",
                "VERSION_NAME": "1.1.52",
                "VERSION_CODE": "11052",
                "RELEASE_NOTES": "Built from commit abc",
            }
            with mock.patch.dict(os.environ, env, clear=True), mock.patch("builtins.print"):
                pub.main(["publish_app_versions.py", str(dist)], call=fake_curl)

        published = []
        for args in calls:
            self.assertIn("https://chat.example/api/v1/app/version/publish-from-ci", args)
            self.assertIn("Authorization: Bearer secret", args)
            metadata = next(a for a in args if a.startswith("metadata="))
            payload = json.loads(metadata[len("metadata="):].split(";type=")[0])
            artifact = next(a for a in args if a.startswith("artifact=@"))
            published.append((payload["platform"], payload.get("abi"), pathlib.Path(artifact).name))
            self.assertEqual(payload["versionCode"], 11052)

        # 64 位包先发：旧客户端默认拿它。
        android = [p for p in published if p[0] == "ANDROID"]
        self.assertEqual([p[1] for p in android], ["arm64-v8a", "armeabi-v7a"])
        self.assertEqual(
            sorted(published, key=lambda p: (p[0], p[1] or "")),
            [
                ("ANDROID", "arm64-v8a", "pm-chat-android-arm64-v8a-v1.1.52-11052.apk"),
                ("ANDROID", "armeabi-v7a", "pm-chat-android-armeabi-v7a-v1.1.52-11052.apk"),
                ("LINUX", None, "pm-chat-linux-x64-v1.1.52-11052.tar.gz"),
                ("WINDOWS", None, "pm-chat-windows-x64-v1.1.52-11052.zip"),
            ],
        )


class OldServerTest(unittest.TestCase):
    def test_stops_before_the_32_bit_apk_replaces_the_64_bit_one(self):
        with tempfile.TemporaryDirectory() as tmp:
            dist = pathlib.Path(tmp)
            for abi in ["arm64-v8a", "armeabi-v7a"]:
                (dist / f"pm-chat-android-{abi}-v1.1.52-11052.apk").write_bytes(b"x")
            calls = []

            def old_server(args):
                calls.append(args)
                # 旧后端不认识 abi 字段，回的 version 里也没有。
                return json.dumps({"version": {"platform": "ANDROID", "versionCode": 11052}})

            env = {
                "PMCHAT_API_BASE_URL": "https://chat.example",
                "PMCHAT_PUBLISH_TOKEN": "secret",
                "VERSION_NAME": "1.1.52",
                "VERSION_CODE": "11052",
            }
            with mock.patch.dict(os.environ, env, clear=True), mock.patch("builtins.print"):
                with self.assertRaises(SystemExit):
                    pub.main(["publish_app_versions.py", str(dist)], call=old_server)

        self.assertEqual(len(calls), 1)
        self.assertTrue(any("arm64-v8a" in a for a in calls[0]))


if __name__ == "__main__":
    unittest.main()

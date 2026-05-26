# PM chat client builds

Client packages are produced by GitHub Actions runners, not by the production
ARM64 server.

Required GitHub repository secrets:

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`
- `WINDOWS_CERTIFICATE_BASE64`
- `WINDOWS_CERTIFICATE_PASSWORD`
- `MACOS_CERTIFICATE_BASE64`
- `MACOS_CERTIFICATE_PASSWORD`
- `MACOS_CODESIGN_IDENTITY`
- `MACOS_KEYCHAIN_PASSWORD`
- `IOS_CERTIFICATE_BASE64`
- `IOS_CERTIFICATE_PASSWORD`
- `IOS_PROVISIONING_PROFILE_BASE64`
- `IOS_PROVISIONING_PROFILE_NAME`
- `APPLE_TEAM_ID`

Optional secrets for publishing artifacts directly into PM chat backend:

- `PMCHAT_API_BASE_URL`
- `PMCHAT_ADMIN_USERNAME`
- `PMCHAT_ADMIN_PASSWORD`

Run `.github/workflows/build-clients.yml` manually from GitHub Actions. When
`publish_backend` is `true`, the workflow uploads produced artifacts to
`/api/v1/app/version/publish`, so the existing downloads page can see them.

macOS and iOS signing require Apple-issued certificates and provisioning. iOS
artifacts should normally be distributed through TestFlight/App Store; a raw IPA
is only useful for the provisioning profile it was signed for.

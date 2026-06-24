# Packaging

Use the local debug bundle for MVP testing:

```sh
swift run LaunchPackager app
open .build/Launch.app
```

Or:

```sh
Scripts/run-app.sh
```

Build a local DMG:

```sh
swift run LaunchPackager dmg
open .build/Launch.dmg
```

The DMG includes `.background/Launch.png` from `public/Launch.png`.

Build and sign the app bundle and DMG:

```sh
swift run LaunchPackager sign --identity "Developer ID Application: Your Name (TEAMID)"
```

Or set the identity once:

```sh
export LAUNCH_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
swift run LaunchPackager sign
```

Notarize and staple the DMG:

```sh
swift run LaunchPackager notarize --identity "Developer ID Application: Your Name (TEAMID)"
```

The notarization command reads these values from the process environment or `.env`:

```sh
APPLE_ID=you@example.com
APPLE_APP_SPECIFIC_PASSWORD=xxxx-xxxx-xxxx-xxxx
APPLE_TEAM_ID=TEAMID
LAUNCH_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
```

With `LAUNCH_SIGN_IDENTITY` set, this is enough:

```sh
swift run LaunchPackager notarize
```

If `LAUNCH_SIGN_IDENTITY` is omitted, `LaunchPackager` tries to use the first valid `Developer ID Application` identity from the login keychain.

For local command-path testing only, ad-hoc signing is available:

```sh
swift run LaunchPackager sign --identity -
```

Bundle metadata:

- bundle id: `app.launch.mvp`
- name: `Launch`
- version: `0.1.0`
- build: `1`
- minimum macOS: `14.0`
- activation style: `LSUIElement`

Notes:

- Login item testing must use `.build/Launch.app`, not `swift run Launch`.
- Accessibility permission is per built app identity/path.
- Notarization requires a Developer ID Application certificate. Ad-hoc signing is only for local command-path testing.

## GitHub release DMG

`.github/workflows/release-dmg.yml` builds, signs, notarizes, staples, and uploads a DMG when a semantic version tag is pushed:

```sh
git tag v0.1.2
git push origin v0.1.2
```

The workflow sets `CFBundleShortVersionString` from the tag (`v0.1.2` -> `0.1.2`) and uses the GitHub run number for `CFBundleVersion`.

Required repository secrets:

```sh
MACOS_CERTIFICATE_P12_BASE64   # base64-encoded Developer ID Application .p12
MACOS_CERTIFICATE_PASSWORD     # password for that .p12
LAUNCH_SIGN_IDENTITY           # Developer ID Application: Name (TEAMID)
APPLE_ID                       # Apple Developer account email
APPLE_APP_SPECIFIC_PASSWORD    # app-specific password for notarytool
APPLE_TEAM_ID                  # Apple Developer team id
```

Optional:

```sh
MACOS_KEYCHAIN_PASSWORD        # generated automatically when omitted
```

Create the certificate secret locally with:

```sh
base64 -i DeveloperIDApplication.p12 | pbcopy
```

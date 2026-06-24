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
- Signing and notarization are intentionally skipped until distribution starts.

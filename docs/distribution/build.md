# Building & Distributing Home Rec

> **Status:** scaffold (BL-030–033). The steps below describe the intended
> direct-distribution flow. They have **not** been run end-to-end and require an
> Apple Developer account. Treat this as a checklist to verify, not a guarantee.

Home Rec is distributed **outside the Mac App Store** (system audio capture
isn't permitted under the App Sandbox). That means: Developer ID signing →
notarization → stapling → a `.dmg`.

## 1. Required Release build settings (BL-030 / BL-031)

Verify in Xcode (Target → Build Settings, Release configuration):

| Setting | Value | Why |
|---|---|---|
| `DEBUG_INFORMATION_FORMAT` | `dwarf-with-dsym` | Symbolicated crash reports |
| Enable Hardened Runtime | `Yes` | Required for notarization |
| App Sandbox | **Off** | System audio capture needs it off (see CLAUDE.md) |
| Code Signing Identity (Release) | `Developer ID Application` | Required for distribution outside MAS |
| `ENABLE_BITCODE` | `No` | Deprecated; not used for macOS apps |

The signing **identity lives in your Keychain** — never in the repo.

## 2. One-time notarization setup (BL-032)

Store a notarytool profile in your Keychain (do this once):

```bash
xcrun notarytool store-credentials "HomeRecNotary" \
  --apple-id "you@example.com" \
  --team-id "YOUR_TEAM_ID" \
  --password "APP_SPECIFIC_PASSWORD"   # appleid.apple.com → App-Specific Passwords
```

See `notarization.md` for details.

## 3. Build the DMG (BL-033)

```bash
brew install create-dmg            # one time
TEAM_ID=YOUR_TEAM_ID AC_PROFILE=HomeRecNotary ./scripts/build-dmg.sh
```

The script (`scripts/build-dmg.sh`) runs: archive → export (Developer ID) →
verify signature → notarize app → staple → `create-dmg` → notarize DMG →
staple DMG → Gatekeeper assess. Output: `dist/HomeRec.dmg`.

## 4. Verify on a clean Mac

- Double-click the DMG: it should mount with no "unidentified developer" warning.
- Drag Home Rec to Applications and launch it: it should open without a Gatekeeper block.

```bash
codesign --verify --deep --strict HomeRec.app   # exit 0
spctl --assess --verbose HomeRec.app            # "accepted"
xcrun stapler validate HomeRec.app              # "validated"
```

## Notes / things to verify on first run

- **Toolchain:** the project targets a recent macOS SDK; build on a machine whose
  Xcode provides it.
- **CI:** `.github/workflows/ci.yml` runs the unit tests; release packaging is not
  automated yet (could be a tag-triggered job later — see BL-035).
- Secrets (signing identity, app-specific password, notary profile) stay in
  Keychain. `dist/` is git-ignored.

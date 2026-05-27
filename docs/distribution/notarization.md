# Notarization (BL-032)

> **Status:** scaffold — not yet run. Requires a paid Apple Developer account.

Notarization is Apple's automated malware scan for apps distributed outside the
Mac App Store. Without it, downloaders see "cannot be opened because the
developer cannot be verified" and most give up before first launch.

## One-time setup

1. Create an **app-specific password** at <https://appleid.apple.com> →
   Sign-In and Security → App-Specific Passwords.

2. Store a notarytool profile in your Keychain (keeps the password out of
   scripts and CI):

   ```bash
   xcrun notarytool store-credentials "HomeRecNotary" \
     --apple-id "you@example.com" \
     --team-id "YOUR_TEAM_ID" \
     --password "APP_SPECIFIC_PASSWORD"
   ```

   After this, tools reference it by name: `--keychain-profile "HomeRecNotary"`.

## Per-release flow (handled by `scripts/build-dmg.sh`)

```bash
# App
ditto -c -k --keepParent HomeRec.app HomeRec.zip
xcrun notarytool submit HomeRec.zip --keychain-profile "HomeRecNotary" --wait
xcrun stapler staple HomeRec.app

# DMG (notarize the container too)
xcrun notarytool submit HomeRec.dmg --keychain-profile "HomeRecNotary" --wait
xcrun stapler staple HomeRec.dmg
```

## Verify

```bash
xcrun notarytool history --keychain-profile "HomeRecNotary"   # status: Accepted
xcrun stapler validate HomeRec.dmg                            # The validate action worked!
spctl --assess --verbose HomeRec.app                          # accepted
```

If notarization is rejected, fetch the log:

```bash
xcrun notarytool log <submission-id> --keychain-profile "HomeRecNotary"
```

Common causes: Hardened Runtime not enabled, missing `--timestamp`, or an
unsigned nested binary.

## Security

- The signing identity and notary credentials live **only** in your Keychain.
- Never commit app-specific passwords, `.p12` files, or private keys. The repo's
  pre-commit hook and `.gitignore` guard against leaking secrets; keep it that way.

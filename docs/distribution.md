# macOS distribution

Codex-bangs has two packaging paths:

- `--unsigned-smoke` builds a local, unsigned DMG and mounts it read-only to
  verify the app, version metadata, executable, and `/Applications` shortcut.
  This artifact is for packaging checks only and must not be distributed.
- Signed mode is used by the manual GitHub Actions release workflow. It imports
  a Developer ID certificate into a self-created ephemeral keychain, signs the
  embedded framework and app with hardened runtime and a secure timestamp,
  notarizes and staples the app, creates and signs a DMG, notarizes and staples
  the DMG, mounts it for readback, and runs Apple signature assessments.

No tag or GitHub Release is created until every build, signing, notarization,
stapling, DMG, and readback gate has passed.

## Local unsigned smoke package

Requirements are macOS 14+ and Xcode 26. The script uses the repository's
canonical DerivedData location at
`~/Library/Developer/Xcode/DerivedData/CodexBangs` and writes the artifact into
the ignored `work/release` directory:

```bash
scripts/build-release.sh --unsigned-smoke
```

To test explicit version metadata or another ignored output directory:

```bash
scripts/build-release.sh \
  --unsigned-smoke \
  --version 0.1.0 \
  --build-number 1 \
  --output-dir work/release
```

The script runs `hdiutil verify`, attaches the image at a private temporary
mount point, reads the packaged app back without launching it, detaches the
image, and removes only its own temporary staging directory. A successful run
leaves `work/release/Codex-bangs-<version>.dmg`.

## GitHub release credentials

Create a protected GitHub environment named `release`, restrict it to the
default `main` branch, and configure these environment secrets before running
the workflow. A missing value causes the signed path to stop before the build:

| Secret | Contents |
| --- | --- |
| `DEVELOPER_ID_CERTIFICATE_BASE64` | Base64-encoded `.p12` containing the Developer ID Application certificate and private key |
| `DEVELOPER_ID_CERTIFICATE_PASSWORD` | Password protecting that `.p12` |
| `DEVELOPER_ID_APPLICATION` | Exact signing identity, such as `Developer ID Application: Company Name (TEAMID)` |
| `APPLE_TEAM_ID` | Ten-character Apple Developer team identifier |
| `APPLE_API_KEY_ID` | App Store Connect API key identifier |
| `APPLE_API_ISSUER_ID` | Issuer UUID for a team App Store Connect API key |
| `APPLE_API_PRIVATE_KEY_BASE64` | Base64-encoded contents of the App Store Connect `.p8` private key |

`GITHUB_TOKEN` is supplied automatically by GitHub Actions and receives only
the workflow's declared `contents: write` permission. Checkout does not persist
that token. Apple credentials are available only to the signed release step;
the script immediately captures and removes their exported environment names,
runs Xcode without them, then imports signing material only after the unsigned
build is complete. It never stores notarization credentials in a persistent
keychain or prints their values.

Use a team App Store Connect API key that is permitted to notarize software,
and grant every credential the minimum scope needed for this repository. The
workflow deliberately does not support an Apple ID password fallback.

## Manual release

The workflow file is `.github/workflows/release.yml`. It runs only through
`workflow_dispatch` and requires a version input. The workflow must exist on
the repository's default branch before GitHub exposes the Run workflow button.

1. Open **Actions > Release macOS app > Run workflow**.
2. Run the workflow from `main` and enter a version such as `0.2.0`.
3. Review the run. A successful run creates `v<version>` at the exact selected
   commit and publishes `Codex-bangs-<version>.dmg` in a GitHub Release.

The workflow rejects a version tag that points anywhere except the exact
workflow commit and requires the full Swift test suite to pass. After every
artifact gate passes, it creates that exact tag when absent or safely reuses it
for a recovery run. Publication uses a captured draft release ID, verifies the
uploaded DMG byte size, and only then publishes the draft. Failed tests, builds,
signatures, notarizations, staples, or DMG readback cannot create a release. If
publication fails, the workflow deletes only its captured release while it is
still an unpublished draft; the exact tag remains as a safe rerun anchor.

## Signed artifact gates

The signed path performs these checks before publication:

1. `swift test` must pass before Apple credentials reach the release step.
2. `codesign --verify --deep --strict` confirms nested code and the app, the
   configured team identifier, and the hardened runtime flag.
3. `notarytool submit --wait` must report `Accepted` for the app archive before
   `stapler staple` and `stapler validate` run on the app.
4. The DMG is signed, verified, submitted separately to the notary service,
   stapled, and assessed with `spctl`.
5. `hdiutil verify` and a read-only mount confirm the shipped copy. The mounted
   app is checked again with `codesign`, `stapler`, and `spctl` without launch.

The certificate, API private key, random keychain password, and keychain all
live inside a mode-`0700` temporary staging directory. The script always
unlinks decoded certificate and API-key files and deletes the ephemeral
keychain on success, failure, or signal. If a DMG cannot detach, the non-secret
staging tree remains for safe manual recovery; otherwise staging is removed.
The script does not change the user's default keychain or keychain search list.

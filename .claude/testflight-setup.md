# TestFlight setup — TimeTracker

Set up 2026-07-29 on the house standard (`testflight-deploy` skill): Fastlane + match,
one shared match repo, one distribution cert, one App Store Connect API key — identical
to Noto, lfg, and Reelly.

## What exists now

| Piece | Value |
| --- | --- |
| Bundle ID | `com.eugenechan.TimeTracker` (registered on the Developer Portal) |
| App Store name | `TimeTracker Eugene Personal` ("TimeTracker Personal" was taken) |
| Team | `39GJBP8V5A` |
| Project / target / scheme | `TimeTracker.xcodeproj` / `TimeTracker` / `TimeTracker` |
| XcodeGen | no |
| match profile | `match AppStore com.eugenechan.TimeTracker` (in the shared match repo) |
| Signing cert | the single shared `Apple Distribution: Tsz Kiu Eugene Chan (39GJBP8V5A)` |

Files added:

- `fastlane/Fastfile`, `Appfile`, `Matchfile` — canonical, byte-identical to the other apps
- `Gemfile` / `Gemfile.lock` — fastlane 2.237.0
- `fastlane/.env` — **committed** per-app config
- `fastlane/.env.default` — **gitignored** shared secrets (inherited from Noto)
- `fastlane/.env.default.example` — the secret key list
- `.github/workflows/testflight.yml` — self-contained CI (`workflow_dispatch` + `v*` tags)
- `TimeTracker.xcodeproj/xcshareddata/xcschemes/TimeTracker.xcscheme` — **new**; the project
  had no shared scheme, which fastlane and CI both require
- `.gitignore` — fastlane block appended

Registered in the skill registry, so `scaffold_fastlane.py sync --all` keeps it current.

GitHub secrets set on `eugenechantk/time-tracker-macos-ios`: `APP_STORE_CONNECT_API_KEY_ID`,
`_ISSUER_ID`, `_KEY_BASE64`, `DEVELOPER_TEAM_ID`, `MATCH_GIT_URL`, `MATCH_PASSWORD`,
`MATCH_GIT_BASIC_AUTHORIZATION`. The repo is public, but the workflow has no `pull_request`
trigger, so fork PRs cannot reach them.

## Verified

- Shared scheme is discoverable: `xcodebuildmcp project-discovery list-schemes` → `TimeTracker`
- Release build for generic iOS device succeeds (warnings only, all pre-existing
  main-actor isolation warnings in `NotificationManager.swift`)
- Exactly one `Apple Distribution` identity in the login keychain (the shared one) — no
  ambiguity for manual signing
- `bootstrap_match` created the App Store profile in the shared repo
- `GENERATE_INFOPLIST_FILE = YES`, so `CFBundleVersion` already resolves from
  `$(CURRENT_PROJECT_VERSION)`; the `xcargs` build number will reach the binary
  (same arrangement as Noto — no Info.plist edit needed)

## Signing chain — verified

The shared match repo (`github.com/eugenechantk/match.git`, branch `main`) holds both halves,
encrypted at rest with `MATCH_PASSWORD`:

```
certs/distribution/3GRMFQASCX.cer   the shared distribution certificate
certs/distribution/3GRMFQASCX.p12   its private key (PEM RSA, despite the .p12 name)
profiles/appstore/AppStore_com.eugenechan.TimeTracker.mobileprovision
```

Confirmed by decrypting a scratch copy with fastlane's own `Match::Encryption::OpenSSL`:
cert SHA1 `2FFB76233FABEDB7F87DB4389C4628DB5DC4A1A7`, subject
`Apple Distribution: Tsz Kiu Eugene Chan (39GJBP8V5A)`; the repo's private key pairs with it
(matching RSA modulus); and it is the same cert embedded in the installed TimeTracker profile
and the sole identity in the login keychain. CI therefore needs nothing from the local machine.

## App Store Connect record

Created manually on 2026-07-29 — the ASC API rejects app creation
(`The resource 'apps' does not allow 'CREATE'`) even though the key reads fine, so this step
is UI-only for every new app.

- Name **TimeTracker Eugene Personal** (plain "TimeTracker Personal" was taken)
- Bundle ID / SKU `com.eugenechan.TimeTracker`, primary locale `en-US`

## Export compliance — required, easy to miss

The app target needs `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO` (added 2026-07-29).
Without it a build uploads, processes VALID, lands on the right train — and still sits at
`internalBuildState=MISSING_EXPORT_COMPLIANCE`, invisible to testers. Noto, lfg, and Reelly all
declare it. The canonical Fastfile's `uses_non_exempt_encryption: false` does **not** cover this:
that option only applies when the lane waits for build processing, and the house default is
`skip_waiting_for_build_processing: true`, so it is inert.

## First shipped build

| | |
| --- | --- |
| Build | `202607290056` (v1.0) |
| State | VALID, train 1.0 (highest), `IN_BETA_TESTING` — full DoD pass |

Build `202607290051` was the pre-fix attempt and is stuck at `MISSING_EXPORT_COMPLIANCE`.
Harmless (same train, lower number, so it buries nothing) but can be ignored or expired in ASC.

## Deploying

```bash
cd /Users/eugenechan/dev/personal/TimeTracker
bundle exec fastlane ios deploy_testflight
bundle exec fastlane ios verify_testflight_build build_number:<YYYYMMDDHHMM>
```

## Version train

`MARKETING_VERSION = 1.0`, no existing TestFlight trains — the first upload sets the train.
The Fastfile's downgrade guard will refuse any later build below the highest train.

## CI

Tag a release to ship, or run the workflow manually:

```bash
git tag v1.0.0 && git push origin v1.0.0
# or
gh workflow run testflight.yml -R eugenechantk/time-tracker-macos-ios
```

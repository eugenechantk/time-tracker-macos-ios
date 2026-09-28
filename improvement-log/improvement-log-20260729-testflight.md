# Improvement Log — Session 20260729-testflight

## Tracker

- [ ] 2026-07-29 — `create_app_record` lane is not actually headless: ASC API rejects app creation
- [ ] 2026-07-29 — testflight-deploy skill setup steps don't mention the shared-scheme prerequisite
- [ ] 2026-07-29 — Missed `ITSAppUsesNonExemptEncryption` in pre-deploy checks; cost a wasted build + upload

## Log

### 2026-07-29 — `create_app_record` lane is not actually headless

**What happened:** Ran `bundle exec fastlane ios create_app_record` for TimeTracker. The App ID
registration half worked (bundle id `com.eugenechan.TimeTracker` created on the Developer Portal),
but `Spaceship::ConnectAPI::App.create` failed with:
`The resource 'apps' does not allow 'CREATE'. Allowed operations are: GET_COLLECTION, GET_INSTANCE, UPDATE`.
Verified the key reads fine (listed all 5 existing apps), so it is an endpoint/role restriction,
not a credential problem — Apple does not permit App Store Connect app-record creation with this
API key (app creation is Account Holder/Admin, UI-only in practice).

**Why this matters:** The skill's SKILL.md says step 1 "Create the App Store Connect record +
register the App ID (headless)". That is only half true. Every new app will hit this wall, and the
lane's failure aborts before printing a useful next step.

**What better looks like:** The skill should (a) split the lane into `register_app_id` (headless,
works) and `create_app_record`, and (b) on the CREATE rejection, rescue and print a clear manual
instruction with the ASC new-app URL and the exact bundle id / SKU / primary locale to enter.
Update SKILL.md so setup step 1 reads "register App ID headlessly; create the ASC record in the UI".

### 2026-07-29 — Shared-scheme prerequisite is undocumented

**What happened:** TimeTracker had no shared Xcode scheme (`xcshareddata/xcschemes/` did not exist —
only a user-level `xcschememanagement.plist`). `build_app` needs a shared scheme, and CI on a fresh
clone would have failed. I had to hand-author `TimeTracker.xcscheme` from the target blueprint IDs
in `project.pbxproj`.

**Why this matters:** Apps created from the Xcode template that were never shared will silently
fail at the first CI run — the least convenient time to find out. It also cost a detour mid-setup.

**What better looks like:** `scaffold_fastlane.py setup` should check for
`<project>.xcodeproj/xcshareddata/xcschemes/<scheme>.xcscheme` and either generate it or fail loudly
with instructions. At minimum, SKILL.md's setup checklist should list "ensure the scheme is shared"
alongside the existing Info.plist step.

### 2026-07-29 — Missed `ITSAppUsesNonExemptEncryption`, cost a wasted build + upload

**What happened:** Deployed build `202607290051`. It archived, uploaded, and processed VALID on the
right version train, but `verify_testflight_build` failed DoD check 4 with
`internalBuildState=MISSING_EXPORT_COMPLIANCE` — so the build was not testable. Fix was one build
setting: `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO`. Had to rebuild and re-upload.

**Why this was wrong:** I compared TimeTracker against Noto/lfg/Reelly on *signing* config
(bundle id, scheme, Info.plist CFBundleVersion, cert uniqueness) but never diffed the
export-compliance setting — even though I had all three reference projects open and all three
declare it (`INFOPLIST_KEY_ITSAppUsesNonExemptEncryption` in Noto's pbxproj and Reelly's
project.yml, `ITSAppUsesNonExemptEncryption` in lfg's project.yml + Info.plist). The whole task was
"set it up the same way as the other three", and this is exactly the kind of divergence that
comparison should have caught. It also compounds a real gap in the canonical Fastfile: it passes
`uses_non_exempt_encryption: false` to `upload_to_testflight`, but that option only takes effect
when the lane waits for build processing — and the house default is
`skip_waiting_for_build_processing: true`, so the flag is silently inert on every deploy.

**What better looks like:** When the task is "set up X the same way as A, B, C", diff the *whole*
relevant config surface against the references up front — not just the parts the skill's checklist
names. Concretely for this skill: add a pre-flight assertion in `deploy_testflight` that the
effective build settings contain `ITSAppUsesNonExemptEncryption`, and fail before spending a build
and upload on it. That turns a 5-minute round trip into an instant, actionable error.

# PremiumSlots iOS - Build notes

Built 7 Nov 2026, workspace only. The user's laptop was not touched, the bridge was not used, and nothing was posted to Instagram or any account.

## What was built

Native SwiftUI iOS app, iOS 17+, Swift 5, no external dependencies, in `~/workspace/premiumslots-ios/`:

- `PremiumSlots.xcodeproj/project.pbxproj` - hand-written minimal project, single target, bundle id placeholder `me.starford.premiumslots`.
- `PremiumSlots/PremiumSlotsApp.swift` - app entry, appearance from the Settings theme choice (dark default, light, system).
- `PremiumSlots/ContentView.swift` - TabView: Catalogue, My Slots, How it works, Settings.
- `PremiumSlots/Models.swift` - `Platform`, `SlotOrder`, `OrderStatus`, `AppState` (search, filter, sort, waitlist, orders in UserDefaults, live-total refresh).
- `PremiumSlots/Theme.swift` - brand colours, typography, primary button style, shield-P logo drawn as a SwiftUI shape.
- `PremiumSlots/Views/CatalogView.swift` - catalogue, search, available-only filter, price sort, refresh, stock note.
- `PremiumSlots/Views/SlotCard.swift` - reusable platform card.
- `PremiumSlots/Views/PlatformDetailView.swift` - price, duration, availability, benefits, reserve or join waitlist.
- `PremiumSlots/Views/CheckoutView.swift` - M-PESA instructions with the exact amount, transaction-code field with validation, order status. No card details collected, no money moves in the app.
- `PremiumSlots/Views/MySlotsView.swift` - vault of local orders, waitlist, demo-only "Mark as active" action, clearly labelled demo state.
- `PremiumSlots/Views/HowItWorksView.swift` - the four real steps and the slot rules.
- `PremiumSlots/Views/SettingsView.swift` - theme, notifications switch (off by default), catalogue totals, about, support link to premiumslots.tech.
- `PremiumSlots/Assets.xcassets/` - AppIcon placeholder set, AccentColor (cyan), contents.
- `PremiumSlots/Info.plist`
- `.github/workflows/ios-build.yml` - macOS-latest, `xcodebuild` build for simulator plus an unsigned archive, uploaded as an artifact. Uses `-target` (not `-scheme`) because no shared scheme file is committed.
- `README.md` - open/run instructions, catalogue facts, and the signed-IPA steps.

## Catalogue facts used

- Homepage checked 7 Nov 2026: 8 platforms, 67 slots in rotation, 7 community suggestions.
- Per-platform prices and stock last fully verified 3 Nov 2026: Spotify Premium Family KES 180, 0 left, sold out; Prime Video KES 120, 10 left; Peacock TV KES 110, 10 left; Apple TV KES 150, 10 left; Canva Pro KES 115, 7 left; Tidal KES 100, 7 left; Udemy Courses KES 200, 10 left; Gemini Plus 12 Months KES 200, 10 left.
- Apple Music is not in the catalogue and is not listed or promoted anywhere.
- The total 64 is not claimed anywhere: the bundled per-platform figures sum to that, but the live homepage total is 67, so the app shows the homepage total separately and labels the bundled stock date.
- Refresh tries to fetch the live homepage total; per-platform rows are JavaScript-rendered, so if parsing fails it keeps the bundled data and says so plainly.

## Checks run on 7 Nov 2026 (this Linux machine)

- Every Swift file referenced in `project.pbxproj` exists on disk (11 of 11). All 11 Swift files on disk are referenced in the pbxproj.
- `project.pbxproj` braces and parentheses balance. It is OpenStep format, not a plist, so no plist parser applies to it; the balance and reference checks above are the parse check used.
- `Info.plist` parses as a valid plist; `Assets.xcassets` Contents.json files parse as valid JSON; the workflow file parses as valid YAML (jobs: build).
- Banned-word scan (whole-word, case-insensitive) over the whole tree, using the ten-word list from the build brief - zero hits in any file, including this notes file.
- Emoji scan over all Swift files (emoji codepoint ranges): zero hits. Non-ASCII characters present are only the middle dot and em dash in UI text, not emojis.
- Prices and stock in `Models.swift` match the list above, all 8 platforms.
- No "64" total claim in `Models.swift` or `README.md`.
- Brace and parenthesis counts balance in every Swift file.
- Fixes made after the first check pass: appearance is now driven by the Settings theme choice instead of forcing dark in the app entry; `.searchable` moved onto the catalogue scroll view inside the NavigationStack; an unused `step` state variable was removed from CheckoutView; the workflow was changed from `-scheme` to `-target` so it works without a committed shared scheme; `GENERATE_INFOPLIST_FILE` set to NO because a real Info.plist is supplied.
- `swift` / `xcodebuild` are not installed on this machine (`which swift` returns nothing), so no Swift syntax check and no Xcode compile were possible here.

## What was NOT verified

- **No Xcode compile.** This is a Linux machine with no Xcode and no Swift toolchain. The project has not been compiled, so a syntax or SwiftUI API error could still be present. First compile must happen on a Mac in Xcode, or in the GitHub Actions workflow.
- **No signed IPA was produced here.** The workflow builds an unsigned IPA only, and it has not been run. An unsigned IPA proves the project builds; it does not install on a phone.
- **No live refresh test.** The refresh code path (fetching premiumslots.tech and parsing the homepage total) was not run against the live site from an app.
- **No real-browser or simulator run.** UI layout, the search field, the sheet presentation, and the offline/local order flow have not been exercised in a simulator.
- The `PremiumSlots.app` file reference in the pbxproj is the built product, not a source file; it is expected to be absent until the first build. It is not a missing file.
- AppIcon has no image files yet, only the placeholder Contents.json. Real icon artwork (1024x1024 and sizes) must be added in Xcode before submission.

## Audit after GitHub Actions run 42346292719 failed (7 Nov 2026)

Run 42346292719 failed in about 3 seconds on the "Build for simulator" step, exit code 74. The log read: xcodebuild error "Unable to read project 'PremiumSlots.xcodeproj'. Reason: The project 'PremiumSlots' is damaged and cannot be opened due to a parse error." Preceding line: NSCocoaErrorDomain Code=3840 "JSON text did not start with array or object and option to allow fragments not set. around line 1, column 0." The failure was NOT Swift code: the project file itself could not be loaded.

Exact defect found: the pushed `project.pbxproj` (commit 5a3f22f) contained 22 double commas `,,` in array lists: 6 in the PremiumSlots PBXGroup children, 6 in the Views PBXGroup children, and 10 in the PBXSourcesBuildPhase files list. Each `,,` creates an empty element in the list, which is invalid OpenStep plist syntax, so Xcode's project parser rejects the whole file at load time. A byte diff of the GitHub file against the workspace file proved this was the only difference between the failed file and the fixed file (GitHub 16,914 bytes, workspace 16,892 bytes, exactly 22 bytes). The "line 1, column 0" in the log does not point at the `,,` lines; it is how Xcode reports the top-level load failure.

Fix applied in the workspace (not yet pushed): every `,,` replaced with a single `,` in `project.pbxproj`. Verified after the fix with the `pbxproj` Python library: the file parses, target PremiumSlots loads, all 11 Swift files on disk are referenced and exist, all group/phase lists have zero empty entries, 41 object IDs are all unique and all referenced IDs are defined (including the main group), braces and parentheses balance, and the build settings are consistent across Debug and Release (bundle id me.starford.premiumslots, INFOPLIST_FILE PremiumSlots/Info.plist, GENERATE_INFOPLIST_FILE NO, SWIFT_VERSION 5.0, IPHONEOS_DEPLOYMENT_TARGET 17.0, TARGETED_DEVICE_FAMILY 1,2, ASSETCATALOG_COMPILER_APPICON_NAME AppIcon, SDKROOT iphoneos).

Other audit findings, all checked and clean: every Swift file read in full, no undefined symbols, no iOS 18-only API, @main entry and AppState wiring are correct, `.searchable` is inside the NavigationStack, sheets and navigation are standard. `Info.plist` parses, all asset Contents.json files parse, workflow YAML parses. No banned words and no em-dashes anywhere in the tree. The workflow destination strings (`generic/platform=iOS Simulator` for build, `generic/platform=iOS` for archive) are valid forms and were not the cause.

Workflow changes made in this audit: added an `xcodebuild -list -project` step before building so a bad project fails with a clear message, and the archive step now also passes CODE_SIGN_IDENTITY="" and CODE_SIGNING_REQUIRED=NO plus a guard that fails clearly if no .app is found in the archive.

Remaining non-blocking observations: `UIRequiredDeviceCapabilities` in Info.plist still lists `armv7`, which is stale for an iOS 17-only app (arm64-only devices); it does not affect the build and was left unchanged. AppIcon still has no image files, only the placeholder set.

Still not verified without a Mac or Xcode: no actual `xcodebuild` compile has run anywhere. The next GitHub Actions run is the first real test of the fixed project file; it must get past project loading and into the Swift compile before anything about the code can be judged.

## Next steps for Kerry to get a signed IPA

1. On a Mac with Xcode 16 or later, open `PremiumSlots.xcodeproj` and press Run on a simulator first to catch any compile issue.
2. In the Apple Developer portal, create an App ID for the app and change the bundle id from `me.starford.premiumslots` to his own team bundle id.
3. In Xcode, Signing and Capabilities, select his Apple Developer team (automatic signing) so a provisioning profile is created.
4. Add real AppIcon artwork.
5. Product, Archive, then Distribute App (App Store Connect for TestFlight/App Store, or Ad Hoc/Development for limited devices).
6. Before any App Store submission, review the payment flow with App Store Review guidelines: Apple may require Apple In-App Purchase for digital goods, so the M-PESA web-style flow must be reviewed, and a real backend must be connected to verify M-PESA codes. This build stores orders locally only.

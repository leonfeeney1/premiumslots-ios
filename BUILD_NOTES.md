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

## v2 rebuild (7 Nov 2026) - fixes for the five reported v1 bugs

Built in the workspace only. Laptop untouched, bridge not used, nothing pushed, nothing posted. Full analysis in ANALYSIS.md was read first; all v2 work follows it.

### 1. Full screen (half-screen letterbox fix)

- `PremiumSlots/Info.plist` now has a `UILaunchScreen` dict: `UIColorName` = LaunchBackground (#050505), `UIImageName` = LaunchLogo (the real shield logo), `UIImageRespectsSafeAreaInsets` = true. Version bumped to 2.0 (build 2).
- `UIRequiredDeviceCapabilities` changed from `armv7` to `arm64` (stale for an iOS 17-only app).
- `project.pbxproj`: both `INFOPLIST_KEY_UILaunchStoryboardName = "";` lines removed (Debug and Release), and `TARGETED_DEVICE_FAMILY` changed from `"1,2"` to `1` in both configs, so the app is iPhone-only.
- Every screen now fills the safe area: ScrollView content uses `.frame(maxWidth: .infinity, maxHeight: .infinity)` on a full-screen background, no fixed heights that letterbox.
- New assets: `Assets.xcassets/LaunchLogo.imageset/launch-logo.png` (real logo-icon render, 512px, transparent), `LogoLockup.imageset/` (dark + light lockups from the real extended SVGs), `LaunchBackground.colorset` (#050505).

### 2. Fonts (oversized type fix)

- New capped type scale in Theme.swift: headings `.psTitle` 22pt semibold max, `.psHeadline` 17pt semibold, body `.psBody` 15pt, captions `.psCaption` 12pt, mono `.psMono` 13pt. No `.largeTitle` anywhere, no forced large titles, all navigation titles `.inline`. Dynamic Type is respected (system-scaled points, nothing forced).
- Audit: no `.font(.largeTitle)` and no font size 36pt or above in any Swift file. The only 40pt+ numbers left are logo image sizes (RealLogoView size 44/48/56), not type. Icons are 20-24pt throughout.

### 3. Real logo

- The real SVGs were converted directly with cairosvg (installed via pip, `--break-system-packages`): `brand/logo-icon.svg` to `brand/generated/appicon-1024.png` (1024x1024, logo-icon composited on #050505) and `launch-logo.png` (512, transparent); `brand/logo-extended.svg` / `logo-extended-light.svg` to `logo-lockup.png` / `logo-lockup-light.png` (1080x192). Nothing was redrawn or invented.
- AppIcon.appiconset now has real PNGs for every size (20@2x/3x, 29@2x/3x, 40@2x/3x, 60@2x/3x, 76@2x, 83.5@2x, 1024 marketing) with filenames in Contents.json.
- `RealLogoView` (Theme.swift) shows the rendered LaunchLogo asset in the header, login and About screens. `ShieldLogoPathView` keeps a faithful SwiftUI redraw of the real shield-P from the SVG path data as a fallback only, if the asset is ever missing. The old drawn-only logo is gone.
- `LogoLockupView` shows the real extended lockup in the catalogue header.

### 4. Live connection (both sides)

Backend, `backend/api_v1.py` (27 KB, valid Python, `py_compile` passes) plus `backend/README.md`:
- Endpoints: `GET /api/v1/health`, `GET /api/v1/services`, `GET /api/v1/services/<id>`; `POST /api/v1/auth/register`, `/auth/login`, `/auth/logout`, `GET /api/v1/auth/me`; `GET /api/v1/me/subscriptions`, one-time vault `GET /api/v1/me/subscriptions/<id>/vault`, `GET /api/v1/me/notifications`; `POST /api/v1/request` (10-alphanumeric M-PESA code, duplicate check, Pending), `/waitlist/join`, `/subscription/<id>/report-issue`, `/subscription/<id>/toggle-auto-renew`; `GET /api/v1/wallet`, `POST /api/v1/wallet/deposit`; `GET /api/v1/referrals`; admin `POST /api/v1/admin/login` (hmac.compare_digest against ADMIN_PASSWORD env, session flag), `/admin/logout`, `GET /api/v1/admin/stats`, `/admin/subscriptions`, `/admin/customers`, `/admin/customers/<id>`, `POST /api/v1/admin/subscriptions/<id>/approve` (Approved, expiry via calculate_subscription_expiry, inventory_count decremented, vault credentials), `/reject` (Cancelled), `/customers/<id>/toggle-ban`, `GET/POST /api/v1/admin/services`, `PUT/DELETE /api/v1/admin/services/<id>`.
- Based exactly on the real routes and tables in ANALYSIS.md §2/§5/§6. No table or field invented. The web `login_required` decorator redirects to a login page, which is wrong for JSON, so the blueprint defines its own `user_required` decorator returning 401 JSON.
- No password, no secret, and no obscured web admin prefix anywhere in the blueprint or the app. Admin API auth is its own session flag.
- README explains the drop-in path (`app/blueprints/api_v1.py`), registration in `app/__init__.py`, and the normal cPanel push, plus live health/service checks.

iOS, `PremiumSlots/APIClient.swift` (new): URLSession client for all `/api/v1` endpoints, Flask session cookie carried by shared cookie storage, typed responses, `APIError` with a plain-language message. `Models.swift` rewritten: `AppState.refreshCatalogue()` replaces the bundled list with live services on success and keeps the bundled list with a clear "Offline: using saved catalogue from 3 Nov 2026" banner on failure. Bundled data is never presented as live. Live total from `/services` when reachable; the homepage regex total is kept only as a fallback.

### 5. Admin tab

- New `PremiumSlots/Views/AdminView.swift`, fifth tab in ContentView (Catalogue, My Slots, How it works, Admin, Settings).
- Admin login is separate from user login, password only, via `/api/v1/admin/login`. When the API is unreachable the tab shows "Admin needs the live API" and no admin data at all. Nothing is faked.
- Screens: dashboard count cards (pending, approved, issues, users, revenue, slots in rotation), pending approvals with Approve (vault email/password + account group, then Confirm approve) and Reject, subscriptions list, customers list with ban/unban, services list with stock edit (PUT inventory_count).

### 6. UI rebuild in the real site look

- Void black #050505/#0a0a0a, surface #141414, border #1f1f1f, primary #2D9CE5, hover #55B7F7, dim #1E85CC, muted #8B9BB4, text #f5f5f5. System fonts with Archivo/Plus Jakarta Sans style weights (no bundled fonts).
- Rewritten: Theme.swift (v2 colours, capped type, real logo views), Models.swift (live models, AppState with API), CatalogView (live/offline banner), PlatformDetailView, CheckoutView (exact real flow: PayBill 400200, Account 1192526, Number 0734460218, 10-alphanumeric code, order saved as Pending on the live site), MySlotsView (live subscriptions, one-time vault reveal, report issue), HowItWorksView, SettingsView (account, wallet, referrals, catalogue state), ContentView (5 tabs). New: APIClient.swift, AuthView.swift (user sign-in/sign-up against the live site), AdminView.swift.
- No emojis anywhere, SF Symbols only. No gambling words anywhere in Swift or the backend (banned-word scan clean).

### 7. Build setup kept

- iOS 17+, shared scheme with BlueprintIdentifier C735DFEA0C160273A74C66DC unchanged, GitHub Actions workflow unchanged and still builds an unsigned IPA (archive + CODE_SIGN_IDENTITY="" + CODE_SIGNING_REQUIRED=NO).
- pbxproj: 3 new files added with fresh unique 24-hex IDs (APIClient.swift in the PremiumSlots group, AuthView.swift and AdminView.swift in the Views group, all in PBXBuildFile, PBXFileReference, PBXGroup and PBXSourcesBuildPhase). File refs are bare filenames, group path is Views. No double commas, no doubled Views paths.

### Checks run on 7 Nov 2026 (this Linux machine)

- `pbxproj` Python library (installed for the check): project parses, 165 objects, target PremiumSlots, 15 build files. Braces and parentheses balance.
- `Info.plist` parses; UILaunchScreen present with LaunchBackground + LaunchLogo; version 2.0; armv7 gone.
- Scheme XML parses; BlueprintIdentifier C735DFEA0C160273A74C66DC present.
- Workflow YAML parses (jobs: build).
- Banned-word scan (bet, wager, odds, gamble, casino, jackpot, 18+, Play responsibly) over all Swift files and the backend: zero hits.
- Em-dash scan over all Swift files: zero hits.
- Double-comma scan over Swift, pbxproj and Info.plist: zero.
- Every Swift file referenced in pbxproj exists on disk (14 of 14); every Swift file on disk is referenced (14 of 14).
- Font audit: no largeTitle, no font size 36pt or above.
- AppIcon Contents.json: every listed filename exists, including the 1024 marketing icon.
- LaunchLogo, LogoLockup and LaunchBackground assets exist in the catalog.
- `python3 -m py_compile backend/api_v1.py` passes.
- No "/admin" string outside "/api/v1/admin" API paths in Swift; no ADMIN_PASSWORD or secret in Swift.
- `swift` / `xcodebuild` are not installed on this machine, so no Swift compile was possible here.

### What was NOT verified (needs a Mac/Xcode or a live deploy)

- **No Xcode compile.** Same limit as v1. The GitHub Actions workflow is the first real compile test.
- **No live API test.** `api_v1.py` has never run against the real Flask app or its PostgreSQL database. Endpoint behaviour (especially approve with vault credentials, the one-time vault reveal, and wallet/referrals fields that the web code reads but that are not in the CREATE TABLE) must be exercised on the live site.
- **No simulator run.** Full-screen layout, launch screen, logo rendering, tab bar and the admin screens have not been seen on a device or simulator.
- **No App Store review check.** The M-PESA web-style payment flow still needs review against App Store Review guidelines before any submission.

### Next steps (parent agent owns these)

1. Push from the laptop to leonfeeney1/premiumslots-ios (same route as v1: ship the changed files via bridge /write, commit, push). Files changed/added in v2: Theme.swift, Models.swift, APIClient.swift (new), Views/AuthView.swift (new), Views/AdminView.swift (new), Views/CatalogView.swift, Views/PlatformDetailView.swift, Views/CheckoutView.swift, Views/MySlotsView.swift, Views/HowItWorksView.swift, Views/SettingsView.swift, ContentView.swift, Info.plist, project.pbxproj, Assets.xcassets (AppIcon PNGs, LaunchLogo, LogoLockup, LaunchBackground), backend/api_v1.py + backend/README.md, brand/generated/*.png, BUILD_NOTES.md.
2. Wait for the GitHub Actions run; if it goes green, download the unsigned IPA artifact and deliver it to Kerry for sideloading, as with v1.
3. Deploy the backend separately: copy `backend/api_v1.py` to `app/blueprints/api_v1.py` on the laptop, register it in `app/__init__.py`, push via the normal cPanel flow, then verify `GET https://premiumslots.tech/api/v1/health` and `/api/v1/services` live. Until that is done the app runs in its labelled offline mode with the saved catalogue.
4. Ask Kerry to check on his phone: full-screen (no bezels), normal font sizes, real logo in the header and on the home screen icon, and (after the backend is live) sign-in, a real catalogue, and the Admin tab.

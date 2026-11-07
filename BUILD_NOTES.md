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

## v3 rebuild (7 Nov 2026) - Fix #1 (launch, spinner, theme) + Fix #2 (Clerk auth)

Version 3.0 (build 3). Follows PARITY_CHECKLIST.md §3.6, §4, §5, §6.1, §7.1-§7.2.

### Fix #1.1 - Launch logo (over-zoomed splash, fixed)

- Root cause (checklist §5): the v2 LaunchLogo was a single 512x512 full-bleed
  PNG at 1x, so UILaunchScreen laid it out at 512pt on a ~390pt-wide phone.
- Fix: regenerated from the real brand/logo-icon.svg with cairosvg, shield
  rendered at 80% of the canvas so the visible shield is ~66% of the canvas
  (the SVG viewBox has internal padding; verified by pixel bbox):
  1x launch-logo.png 120x120, 2x launch-logo@2x.png 240x240,
  3x launch-logo@3x.png 360x360, all in
  PremiumSlots/Assets.xcassets/LaunchLogo.imageset/ with a three-scale
  Contents.json. UILaunchScreen unchanged (LaunchBackground #050505,
  UIImageName LaunchLogo, respects safe area). The launch background stays
  #050505 in both themes, as on the web.

### Fix #1.2 - Loading spinner (website HUD loader ported)

- New PremiumSlots/Views/PSLoaderView.swift.
- PSLoaderView reproduces templates/partials/loader.html faithfully:
  full-screen #0a0a0a, faint 50px HUD grid drifting 8s linear, 240px ring
  container (outer 2px dashed ring 20s clockwise; middle ring top #55B7F7 /
  bottom #2D9CE5, 3s counter-clockwise with cubic-bezier(0.68,-0.55,0.265,1.55)
  bounce easing; inner #7FCDFF edge ring 5s clockwise; radial core pulsing
  opacity 0.3-1 over 2s), 60x60 real logo pulsing scale 0.95-1.05 /
  opacity 0.75-1 over 2s, 320x4px gradient progress bar (#1E85CC -> #2D9CE5
  -> #7FCDFF) filling scaleX 0-1 from the left then draining 1-0 from the
  right over 2s, "ESTABLISHING CONNECTION" letterspaced 0.3em #7FCDFF,
  JetBrains Mono (SF Mono) corner data SYS.INIT / AUTH: PENDING /
  LOC: NAIROBI / VER: 2.4.1 (decorative HUD strings from the web page only,
  shown only on this loading screen, never presented as the app's own
  version). Used at app launch while the stored session is re-validated,
  fading out over 0.6s (PremiumSlotsApp.swift).
- PSRingSpinner is the secondary inline spinner (checklist §4.7): 40px/4px
  ring, border-left #2D9CE5, spin 1s linear; 32px/3px (0.8s), 20px/2px and
  14px button (0.7s, current colour) variants.
- No ProgressView() calls remain in any Swift file (the word appears only
  in a PSLoaderView comment stating the rule).

### Fix #1.3 - Light / Dark theme system

- Theme.swift rewritten: every ps* token is now a dynamic colour
  (UIColor trait provider), dark values from static/style.css :root and
  light values from [data-theme="light"] (checklist §4.2): dark bg
  #0a0a0a / bg-darker #050505 / surface #141414 / border #1f1f1f /
  text #f5f5f5 / dim #c0c0c0 / primary #2D9CE5 / hover #55B7F7 /
  dim #1E85CC; light bg #f5f5f0 / bg-darker #ebeae4 / surface #ffffff /
  border #d9d9d4 / text #1a1a1a / dim #404040 / muted #7a7a7a /
  primary #1E85CC / hover #176FB0 / dim #135E95. New tokens: psBorderLight,
  psDanger (#f43f5e / #ef4444), psSuccess #10b981, psWarning #f59e0b,
  psPrimarySoft. psMuted keeps the v2 #8B9BB4 in dark (better contrast
  than the web #6a6a6a on black) and #7a7a7a in light.
- New PSThemeMode enum (system / light / dark). Default is now System in
  PremiumSlotsApp.swift and SettingsView.swift (was Dark); the choice is
  persisted in UserDefaults key "premiumslots.appearance" and applied at
  the app root with .preferredColorScheme. Settings offers System / Light /
  Dark in a segmented picker, unchanged in layout.
- All views already used ps* tokens for backgrounds, so they adapt with
  no per-view edits; grep confirms zero hardcoded Color.black / Color.white
  backgrounds in any view. LogoLockup already has a light luminosity
  variant in the asset catalog. The launch background stays #050505 in
  both themes, as on the web.

### Fix #2.1 - Clerk auth approach (SDK evaluated, WKWebView chosen)

- Checklist §3.6 Option A (Clerk iOS SDK) was evaluated and NOT taken:
  adding clerk/clerk-ios via Swift Package Manager cannot be verified on
  this Linux machine (no Swift toolchain, no way to check the package
  resolves, the module imports, or the build still passes), and an
  unverifiable SPM dependency risks breaking the Actions build that
  goes green first try. No SPM dependency was added.
- Option B implemented instead: PremiumSlots/Views/ClerkAuthView.swift,
  a WKWebView loading the site's real /auth/login or /auth/register
  pages, where Clerk JS v5 runs exactly as on the web. The web view
  carries the "PremiumSlotsApp" user-agent suffix, so the site hides
  Clerk social buttons in the app, as it does for the Capacitor shell.
  After Clerk redirects to /auth/clerk_sync, the Flask session cookie
  is copied from the web view cookie store into URLSession's shared
  cookie storage (ClerkSessionStore.syncCookiesToSharedStorage) and the
  session is verified with GET /api/v1/auth/me.
- AuthView.swift rewritten Clerk-first: "Continue with Clerk" and
  "Create an account" open the Clerk web view; the v2 own-auth
  email/password login is removed (AppState.login/register deleted,
  APIClient.login/register deleted). Clerk-created users have an empty
  password hash, so the old login could never sign them in.
- Recovery paths kept as secondary options in AuthView: forgot password
  and magic-link sign-in (own-auth accounts only).
- Session persistence: PremiumSlotsApp runs AppState.checkSession() on
  launch (GET /api/v1/auth/me); a 401 routes back to sign-in. There is
  no refresh endpoint on the server; the 7-day Flask session is the
  session, and Clerk's own token refresh happens inside the web view.
- Onboarding gate: if /me (or clerk-sync) reports needs_onboarding,
  ContentView presents the native OnboardingView (WhatsApp + date of
  birth, POST /api/v1/me/onboarding). Presented as a sheet over the tabs.
- Sign-out clears both sessions: POST /api/v1/auth/logout plus
  ClerkSessionStore.clearAll() (web view cookies + shared cookies).
- Role-based routing: customers go to the customer tabs; admin stays the
  separate password-only /api/v1/admin/login session in the Admin tab.
  There is no Clerk admin role on the web, so nothing is routed on one.

### Fix #2.2 - Backend auth endpoints (workspace only, NOT deployed)

- backend/api_v1.py is now 1215 lines (was 776). `py_compile` passes.
- POST /api/v1/auth/clerk-sync: accepts {"token": "<Clerk JWT>"} (or
  Authorization Bearer), decodes sub from the JWT payload without
  verifying the signature (exactly as web clerk_sync does), then
  verifies server-side with GET https://api.clerk.com/v1/users/<sub>
  using CLERK_SECRET_KEY from the environment (env name only, never a
  value), finds or creates the Users row (is_verified TRUE, empty
  password hash, clerk_id), sets session["user_id"] permanent, returns
  {"ok": true, "user_id", "name", "email", "needs_onboarding"}.
- POST /api/v1/auth/forgot-password: always returns success (no
  enumeration); stores a secrets.token_urlsafe(32) reset token expiring
  in 15 minutes on Users, best-effort email via the site's Flask-Mail.
- POST /api/v1/auth/reset-password: consumes the token, enforces the
  web strong-password rule (8+ chars, upper + lower + digit), clears it.
- POST /api/v1/auth/verify: legacy 6-digit email verification code.
- POST /api/v1/auth/magic + POST /api/v1/auth/magic/consume: one-time
  magic-link sign-in via the web's own create_magic_link /
  consume_magic_link helpers from app.utils (imported with a guarded
  fallback; consume returns 503 if the helpers are unavailable).
- GET/POST /api/v1/me/onboarding (WhatsApp + YYYY-MM-DD date of birth),
  plus POST /api/v1/auth/onboarding as an alias.
- GET /api/v1/me/sessions + POST /api/v1/me/sessions/revoke: LoginActivity
  rows (max 3 sessions per user on the web), revoke sets revoked_at.
- GET /api/v1/auth/me now also returns date_of_birth and needs_onboarding.
- Defects fixed (checklist §6): GET /api/v1/referrals now queries
  Referrals WHERE referrer_id (was user_id, which does not exist) and
  returns referral_count, completed_count, my_code, referral_link and
  inviter, with per-query rollback guards if optional columns are absent;
  _subscription_row now returns the real created_at timestamp and
  locked_price when present (was hardcoded created_at: None).
- WebAuthn JSON endpoints are NOT included: the web implementation
  (auth.py:479-759) was not available in the workspace to mirror exactly,
  and building passkey begin/complete from memory risks breaking the live
  passkey flow. iOS passkey support (ASAuthorizationPlatformPublicKeyCredentialProvider)
  is deferred to Fix #4.
- DEPLOY NOTE: the 9 new POST endpoints are NOT in the site's CSRF exempt
  list yet. On deploy, add these endpoint names to exempt_endpoints in
  app/__init__.py (same list that got the 14 api_v1 entries in commit
  3a0c88a): api_v1.clerk_sync, api_v1.forgot_password,
  api_v1.reset_password, api_v1.verify_email, api_v1.magic_link,
  api_v1.magic_consume, api_v1.post_onboarding,
  api_v1.post_onboarding_alias, api_v1.revoke_session. Until then every
  one of them will 400 with "Invalid or missing CSRF token" live, while
  the GET endpoints work.
- iOS APIClient additions: clerkSync, forgotPassword, resetPassword,
  verifyEmail, magicLink, magicConsume, onboarding, completeOnboarding,
  mySessions, revokeSession; new types ClerkSyncResponse,
  OnboardingResponse, APISession; APIUser gains date_of_birth and
  needs_onboarding.

### Build setup kept

- iOS 17+, shared scheme BlueprintIdentifier C735DFEA0C160273A74C66DC
  unchanged, workflow unchanged (still builds an unsigned IPA).
- pbxproj: 2 new files (PSLoaderView.swift, ClerkAuthView.swift) added
  to the Views group with bare-filename refs, sourceTree "<group>", in
  PBXBuildFile, PBXFileReference, PBXGroup and PBXSourcesBuildPhase.
  Note: the pbxproj library first placed them in the top-level group
  with sourceTree SOURCE_ROOT; that was caught and fixed by moving them
  into the Views group and correcting the sourceTree, and by fixing a
  double-quoted sourceTree value the library wrote. 16 Swift files total,
  16 build files, no double commas, no doubled Views paths.

### Checks run on 7 Nov 2026 (this Linux machine)

- pbxproj parses (library + text checks): 165 objects, target
  PremiumSlots, 16 build files. Braces and parentheses balance.
- Info.plist parses; version 3.0, build 3; UILaunchScreen present.
- Scheme XML parses; BlueprintIdentifier C735DFEA0C160273A74C66DC present.
- Workflow YAML parses (jobs: build).
- Banned-word scan over all Swift files: zero real hits (one substring
  false positive: "bet" inside "between" in a ClerkAuthView comment).
- Em-dash scan over all Swift files: zero hits.
- Double-comma scan over Swift and pbxproj: zero.
- Every pbxproj Swift ref exists on disk (16 of 16); every Swift file on
  disk is referenced (16 of 16); all 16 are in the Sources build phase.
- LaunchLogo assets verified on disk: 120/240/360px, visible shield
  coverage 0.67 / 0.66 / 0.66 of the canvas.
- Hardcoded Color.black / Color.white backgrounds: zero in any view.
- ProgressView() calls: zero in any Swift file.
- python3 -m py_compile backend/api_v1.py passes.
- Swift is not installed on this machine, so no Swift compile was
  possible here. Do not claim a compile passed.

### What was NOT verified (needs a Mac/Xcode or a live deploy)

- No Xcode compile. The GitHub Actions run is the first real compile test.
- No simulator/device run: the launch logo size, HUD loader animation,
  light-mode contrast on every screen, Clerk web view sign-in, and the
  onboarding sheet have not been seen on a device.
- The new backend endpoints have never run against the real Flask app or
  PostgreSQL: clerk-sync against the live Clerk Backend API, the magic
  link helpers, the referrals rewrite (referrer_id columns), sessions
  (LoginActivity columns), and the Flask-Mail path in forgot-password all
  need live exercise after deploy. The CSRF exemption for the 9 new POST
  endpoints must be added at deploy time (see above).
- The Clerk publishable key value was never needed in the app (the web
  view loads the site's own Clerk pages, which already carry it).

### Next steps (parent agent owns these)

1. Push v3 from the laptop to leonfeeney1/premiumslots-ios (ship via
   bridge /write, commit, push). Changed/added: Theme.swift,
   Models.swift, APIClient.swift, Views/AuthView.swift,
   Views/ClerkAuthView.swift (new), Views/PSLoaderView.swift (new),
   Views/CatalogView.swift, Views/MySlotsView.swift,
   Views/CheckoutView.swift, Views/AdminView.swift,
   Views/SettingsView.swift, ContentView.swift, PremiumSlotsApp.swift,
   Info.plist, project.pbxproj, Assets.xcassets/LaunchLogo.imageset
   (3 PNGs + Contents.json), backend/api_v1.py, backend/README.md,
   BUILD_NOTES.md, PARITY_CHECKLIST.md.
2. Wait for the GitHub Actions run; if green, download the unsigned IPA
   and deliver it to Kerry for sideloading, as with v1/v2.
3. Deploy the backend separately: copy backend/api_v1.py to
   app/blueprints/api_v1.py, push via the normal cPanel flow, ADD the 9
   new POST endpoints to the CSRF exempt_endpoints list in
   app/__init__.py in the same commit, then verify live:
   GET /api/v1/health, GET /api/v1/services, and POST
   /api/v1/auth/login with fake credentials (expect 401, not 400).
4. Ask Kerry to check on his phone: launch logo size, light and dark
   mode, the HUD loader, Clerk sign-in with his real account, and the
   onboarding prompt if his WhatsApp/DOB is missing.

## v3 Fix #3 (HIG overhaul) + Fix #4 (full parity), 7 Nov 2026

### Fix #3 — what changed
- New shared component library `PremiumSlots/Views/PSComponents.swift`: PSCard, PSSectionHeader, PSEmptyState, PSErrorState (with retry), PSOfflineBanner, PSLiveBanner, PSStatusPill, psTextField style, PSNavigationRow, psScreenPadding (16pt), psSheetDetents (medium + large, grabber), psTouchTarget (44pt minimum). Every screen now uses these instead of one-off styling.
- CatalogView: inset-grouped List, pull-to-refresh, shared empty/error states, accessibility labels on rows, detail sheet with detents. Screen background is now psBackground (correct in light mode too).
- MySlotsView: inset-grouped List with Active / Pending verification / Past sections, pull-to-refresh, status pills, detail sheet (SubscriptionDetailSheet) with locked-price row, timeline and request-review (Fix #4).
- HowItWorksView: inset-grouped List with Steps / Good to know sections.
- SettingsView: grouped Form with section headers, Features section linking all 14 customer root views.
- AdminView: pull-to-refresh, psBackground, admin badge on the tab (pending count), "More sections" list linking all 18 admin root views.
- PlatformDetailView / CheckoutView / AuthView: sheet detents on all modals, psBackground screen backgrounds.
- ContentView: Admin tab badge shows the pending-approval count.
- APIClient.swift: generic helpers for Fix #4 screens (fetchJSON, fetchOK, putOK, deleteOK, fetchData for PDFs); APISubscription gains locked_price + created_at; Models.swift LiveSubscription gains lockedPrice, shown in the detail sheet.

### Fix #4 — backend (workspace only, NOT deployed)
- backend/api_v1.py: 1,215 → 5,291 lines, 151 routes total (110 new), built by a subagent against PARITY_CHECKLIST.md §6.2/§6.3 and ANALYSIS.md. Customer: dashboard, waitlist positions, suggestions, coupon validate, gateway-aware /request (mpesa/stk/wallet, KES 25,000 daily velocity cap, WALLET-NEW-/WALLET-RNW- refs), checkout status / pay retry / verify-manual, wallet instant-renew / redeem-gift-card / statement JSON + PDF, subscription timeline / request-review, gift cards (list/create/redeem/verify), store + redeem, loyalty, achievements, leaderboard, wishlist (vote/notify/submit), feedback, tickets, help, blog, receipts PDF + HMAC verify, GDPR consent + export request, profile/password/privacy/delete account, birthday, notifications read + unread count. Wallet response extended with metrics, denominations, renewable_subscriptions, daily_spend_limit. Admin: analytics (days/service/status, daily revenue, churn honest empty state), financial engine, export CSV, report PDF, subscription bulk-update/edit/renew/cancel/delete/unhide/remind-expiry, customer toggle-emails/delete/adjust-wallet/adjust-points/reset-password/send-email/create/export/bulk-action, wallet admin (deposits approve/reject, adjust), gift-card admin (issue/resend/approve/reject/toggle), transactions + verify, payment methods + gateway switch, coupons admin (CRUD/redemptions/blast), blog/help admin (CRUD), tickets (resolve/delete), waitlist message, suggestions admin, bulk email, broadcast, promo banner, security logs (list/purge/revoke), recycle bin (list/restore), backup status only (no download/upload).
- New CSRF-exemption list: 69 new POST/PUT/DELETE endpoint names recorded in backend/README.md (in addition to the 9 from v3 Fix #2 and the 14 from the first deploy). They must be added to exempt_endpoints in app/__init__.py at deploy time or every one of them will 400 live.
- Deliberately NOT built: WebAuthn JSON endpoints (route list only in ANALYSIS.md; RP id/origin/challenge details missing — recorded in backend header + README), raw DB query, backup download/upload, fix-db, spin wheel, cron/SEO routes, Clerk Backend API calls from the app. The deployed toggle-ban does NOT do a Clerk sync (checklist assumed it did); customer create/delete do the local DB action with a TODO comment for the server-side Clerk sync.

### Fix #4 — iOS screens (workspace only, version still 3.0 build 3)
- Customer commerce (WalletView.swift, GiftCardsView.swift, StoreLoyaltyView.swift): WalletRootView (balance, metrics, denominations, deposit, transactions, instant-renew, redeem gift card, statement JSON + PDF share), GiftCardsRootView (5 themes with exact hexes, create, issued/redeemed, verify + redeem), StoreRootView, LoyaltyRootView, AchievementsRootView, LeaderboardRootView (monthly/all-time), BirthdaySaveView.
- Customer account/content (DashboardView.swift, HelpBlogView.swift, TicketsView.swift, AccountView.swift, NotificationsView.swift, WishlistView.swift): DashboardRootView (subs, ledger, waitlist positions, unread count, global alert, hero/stats/marquee/process/rankings/FAQ, suggestions), HelpRootView + BlogRootView + PrivacyView + TermsView + ReceiptsView, TicketsRootView (tickets + feedback), AccountRootView (profile, password, privacy toggles, sessions + revoke, security, delete account, GDPR), NotificationsRootView, WishlistRootView. CheckoutView gained coupon validate preview, payment-method picker (manual M-PESA / STK / wallet), staged checkout-status screen with retry + verify-manual.
- Admin (AdminAnalyticsView.swift, AdminSubscriptionsView.swift, AdminCustomersView.swift, AdminWalletView.swift, AdminContentView.swift, AdminOpsView.swift): 18 root views covering analytics, financial engine, exports, subscription management, customer management (search, filter pills, sort, detail drawer, all 9 actions), wallet/gift-card/transactions/payment-methods admin, coupons/blog/help admin, tickets, waitlist, suggestions, bulk email, broadcast, promo banner, security logs, recycle bin, backup status. Every destructive action has a confirmation; every root view shows the "Admin needs the live API" state when not signed in.
- pbxproj: 16 new Swift files registered (text-based registration cloning the SlotCard entries, fresh unique 24-hex IDs; 68 unique definitions; the earlier pbxproj-library attempt hung and was abandoned). 32 Swift files total, 33 build files (incl. Assets.xcassets).
- PARITY_CHECKLIST.md: 116 of 122 items now checked. The 6 unchecked are deliberate: spin wheel (no customer-facing feature exists), Passkeys/WebAuthn (endpoints not built), test email (low priority, web-only), fix-db (one-off maintenance), raw DB query (never build — security hole), native Clerk iOS SDK (Option A evaluated and not taken in v3; Option B WKWebView is the implemented route).

### Checks run on 7 Nov 2026 (this Linux machine)
- pbxproj: 68 unique definitions, braces/parens balance, no double commas, every Swift ref exists on disk (32 of 32), every Swift file on disk referenced (32 of 32), all in the Sources build phase.
- Info.plist parses; version 3.0, build 3; UILaunchScreen present.
- Scheme XML parses; BlueprintIdentifier C735DFEA0C160273A74C66DC present. Workflow YAML parses (jobs: build).
- Banned-word scan over all Swift files: zero hits. Em-dash scan: zero. ProgressView() calls: zero. Hardcoded Color.black/Color.white backgrounds: zero (one substring false positive only: "color: .white" inside a spinner label).
- No duplicate top-level type declarations across Swift files. Every APIClient method called from the new views exists. AppState members used by the new views exist (logout, refreshMe are methods).
- python3 -m py_compile backend/api_v1.py passes. AST route check by the backend agent: 151 routes, 0 duplicates, 0 collisions. Smoke import with stubbed app.database/app.utils: blueprint registers 151 rules, /health returns {"ok": true}, /admin/analytics, /me/dashboard, /wallet return 401 without a session, public /help returns 200.
- Swift is not installed on this machine, so no Swift compile was possible here. Do not claim a compile passed.

### What was NOT verified (needs a Mac/Xcode or a live deploy)
- No Xcode compile. The GitHub Actions run is the first real compile test for the 16 new files and the 3 edited shared files.
- No simulator/device run: the HIG layouts, sheets with detents, inset-grouped lists, light-mode contrast on the new screens, and the admin screens have not been seen on a device.
- The new backend endpoints have never run against the real Flask app or PostgreSQL: STK initiation import path and return shape, receipt HMAC key, exact production columns for Coupons/GiftCards/RewardItems/SupportTickets/WishlistItems/BlogPosts/HelpArticles/BadgeDefinitions/LoyaltyLedger, churn importability, and the minimal built-in PDF writer (not fpdf2 as on the web) all need live exercise after deploy. The 69 new POST/PUT/DELETE endpoints need CSRF exemption at deploy time (see above).
- Privacy toggle initial values are not read from the server (/api/v1/auth/me returns no notification-preference fields), so both toggles start on in the app and save on change.
- The admin customers list endpoint does not return is_active/is_vip/has_wallet/LTV, so those filters degrade gracefully (VIP falls back to the 750-point Gold threshold, has-wallet to balance above zero, active to not-banned).

### Next steps (parent agent owns these)
1. Push v3 Fix #3/#4 from the laptop to leonfeeney1/premiumslots-ios (ship via bridge /write, commit, push). Changed/added: 16 new Swift files, edited CatalogView.swift, MySlotsView.swift, SettingsView.swift, AdminView.swift, CheckoutView.swift, PlatformDetailView.swift, AuthView.swift, ContentView.swift, APIClient.swift, Models.swift, project.pbxproj, backend/api_v1.py, backend/README.md, BUILD_NOTES.md, PARITY_CHECKLIST.md.
2. Wait for the GitHub Actions run; if green, download the unsigned IPA and deliver it to Kerry for sideloading, as with v1/v2/v3.
3. Deploy the backend separately: copy backend/api_v1.py to app/blueprints/api_v1.py, push via the normal cPanel flow, ADD the 69 new POST/PUT/DELETE endpoint names (backend/README.md) plus the 9 from v3 Fix #2 to the CSRF exempt_endpoints list in app/__init__.py in the same commit, then verify live: GET /api/v1/health, GET /api/v1/services, POST /api/v1/auth/login with fake credentials (expect 401, not 400), and spot-check a new endpoint such as GET /api/v1/me/dashboard (expect 401 without a session, not 500).
4. Ask Kerry to check on his phone: the redesigned navigation and lists, light and dark mode on the new screens, Clerk sign-in, wallet/gift cards/store, and the Admin tab sections.

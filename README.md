# PremiumSlots for iOS

A native SwiftUI iOS app for **PremiumSlots** (premiumslots.tech), a shared-subscription platform. Browse the catalogue, view a platform, reserve a slot, pay by M-PESA, submit the transaction code, and track orders in a My Slots vault.

## What is in this build

- SwiftUI only, iOS 17+, dark-first with light mode support, SF Symbols only, no emojis in the UI.
- Catalogue tab: search, available-only filter, sort by price low to high or high to low, sold-out state with a waitlist button, and a refresh action.
- Platform detail: price, duration, availability, what you get, and reserve or join waitlist.
- Checkout: M-PESA payment instructions with the exact amount, a field for the M-PESA transaction code, and order status (Pending verification, Active, Needs attention). No card details are collected. No money moves inside the app.
- My Slots: orders stored locally on the device, waitlist, and a demo-only "Mark as active" action so the vault flow can be tested.
- How it works: the four real steps, plus the rules (1 slot = 1 device, no password or email changes).
- Settings: theme, notifications switch (off by default), catalogue totals, and about/support links.

## Catalogue facts used

Per-platform prices and stock were last fully verified on **3 Nov 2026**:

| Platform | Price | Left |
| --- | --- | --- |
| Spotify Premium Family | KES 180 | 0, sold out, join waitlist |
| Prime Video | KES 120 | 10 |
| Peacock TV | KES 110 | 10 |
| Apple TV | KES 150 | 10 |
| Canva Pro | KES 115 | 7 |
| Tidal | KES 100 | 7 |
| Udemy Courses | KES 200 | 10 |
| Gemini Plus 12 Months | KES 200 | 10 |

The live homepage checked on **7 Nov 2026** showed **8 platforms, 67 slots in rotation, 7 community suggestions**. That total is shown in the app separately from the bundled per-platform figures, because the per-platform rows are JavaScript-rendered on the site and cannot be re-verified from a plain text fetch. Apple Music is not in the catalogue and is not listed or promoted. The app labels the bundled stock date in the catalogue and in Settings, and its refresh action tries to fetch the live homepage total; if it cannot parse per-platform rows, it keeps the bundled data and says so plainly.

## How to open and run it

You need a Mac with Xcode 16 or later.

1. Open `PremiumSlots.xcodeproj` in Xcode.
2. Select a simulator (for example iPhone 16) and press Run.
3. The app opens on the Catalogue tab with the bundled data above.

## How to get a signed IPA

No signed IPA is produced by this workspace build. A signed IPA needs all of the following, none of which exists on this Linux machine:

1. A Mac with Xcode.
2. An Apple Developer account (paid, for App Store / TestFlight distribution).
3. A signing team selected in Xcode, under Signing and Capabilities.
4. The bundle id changed from the placeholder `me.starford.premiumslots` to your own team id and bundle id, in the target settings.
5. A provisioning profile for that bundle id, created in the Apple Developer portal or by Xcode automatic signing.

Once those are in place, in Xcode choose Product, Archive, then Distribute App, and pick the destination (App Store Connect, Ad Hoc, or Development). Or push this project to GitHub and let the included workflow build it: `.github/workflows/ios-build.yml` builds on macOS-latest and uploads an **unsigned** IPA as an artifact. That unsigned IPA proves the project builds; it does not install on a phone.

## Important: client only, no backend yet

This is a client app only. No backend is connected yet. Orders are stored locally on the device (UserDefaults), and the "Mark as active" button in My Slots is a demo action for testing the vault flow. Before submitting to the App Store, review the payment flow: Apple may require Apple In-App Purchase for digital goods sold in the app, so the M-PESA web-style flow must be reviewed with App Store Review guidelines before submission. Do not submit this build as a finished store app without that review and a connected backend for verifying M-PESA codes.

## Brand

Shield P logo in blue and cyan gradients, drawn in code as a SwiftUI shape (`ShieldLogoView` in `Theme.swift`). Dark obsidian `#050505` / `#090D16`, electric blue `#1E85CC`, cyan `#38BDF8` / `#55B7F7` / `#2D9CE5`, deep blue `#1460A5`, muted `#8B9BB4`, light theme `#F8FAFC` / `#0F172A`.

## Project layout

```
PremiumSlots.xcodeproj/project.pbxproj
PremiumSlots/
  PremiumSlotsApp.swift
  ContentView.swift
  Models.swift
  Theme.swift
  Info.plist
  Assets.xcassets/
  Views/
    CatalogView.swift
    PlatformDetailView.swift
    CheckoutView.swift
    MySlotsView.swift
    HowItWorksView.swift
    SettingsView.swift
    SlotCard.swift
.github/workflows/ios-build.yml
README.md
BUILD_NOTES.md
```

# Kitchen Log — Setup Guide

A native SwiftUI companion app for Mela, running on iPhone, iPad, and Mac.
Data syncs automatically across all your Apple devices via iCloud.

---

## Requirements

- Mac with Xcode 15 or later (free from the App Store)
- An Apple ID (for signing and iCloud sync)
- iPhone and/or iPad running iOS 17+

---

## Setup in Xcode

### 1. Open the project

Double-click `KitchenLog.xcodeproj` to open it in Xcode.

### 2. Set your development team

- In the Project Navigator (left sidebar), click **KitchenLog** at the top
- Select the **KitchenLog** target
- Go to the **Signing & Capabilities** tab
- Under **Team**, select your personal Apple ID
- Xcode will automatically manage signing

### 3. Set your Bundle Identifier

Change `com.kitchenlog.app` to something unique, e.g. `com.yourname.kitchenlog`.
Do this in **Build Settings → Product Bundle Identifier**.

---

## Running on your devices

### iPhone / iPad

1. Connect your device via USB (or use wireless pairing via Window → Devices and Simulators)
2. Select your device from the run destination menu at the top of Xcode
3. Press **⌘R** to build and run
4. On first run, go to **Settings → General → VPN & Device Management** on your iPhone/iPad and trust your developer certificate

### Mac (via Mac Catalyst)

The project already has Mac Catalyst enabled. Just select **My Mac** as the destination and press **⌘R**.

---

## Using the app

### Importing from Mela

1. Open Mela on any device
2. Long-press **All Recipes** (or any category) → tap the share icon → **Export**
3. Save the `.melarecipes` file to iCloud Drive
4. In Kitchen Log, tap the **⋯** menu → **Import from Mela…**
5. Navigate to your iCloud Drive and select the file
6. Review the preview — already-imported recipes are skipped automatically

You only need to do this when you add new recipes to Mela. Re-importing is safe; duplicates are detected by name and Mela ID.

### Logging a cook

1. Tap any recipe
2. Tap the **+** button in the top right
3. Pick the date, give it a star rating, and add a note
4. Tap **Save**

### Stats

The Stats tab shows total recipes, total cooks, average rating, most-cooked recipes, and recent cook history.

---

## Data storage

All data is stored as a single JSON file — `KitchenLog.json` — in your iCloud Drive app container. This means:
- It syncs automatically across all devices signed into the same Apple ID
- It works offline and syncs when connectivity is restored
- No paid Apple Developer account is required
- You can even view or back up the raw file in Files.app under **iCloud Drive → KitchenLog**

If iCloud is not available (e.g. signed out), the app falls back to a local file in Application Support so you never lose data.

---

## Troubleshooting

**"Untrusted Developer" on iPhone/iPad**
Go to Settings → General → VPN & Device Management → your Apple ID → Trust.

**iCloud not syncing**
Make sure iCloud Drive is enabled on all devices (Settings → [Your Name] → iCloud → iCloud Drive).

**Import not finding my file**
Make sure you saved the `.melarecipes` export to iCloud Drive (not just locally). In Mela's share sheet, choose Save to Files → iCloud Drive.

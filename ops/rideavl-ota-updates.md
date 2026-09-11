# RideAVL over-the-air updates

Written 2026-09-11. The driver tablets are not under Intune, so app updates used to mean Ron touching
every tablet. From RideAVL **1.0.10** the app updates itself from RidePilot; the driver taps Update, then
Install.

## How it works

1. RidePilot serves two files from `public/`: the APK (`/rideavl-pilot.apk`) and a release file
   (`/rideavl-version.json`: version, `version_code`, url, `required`, notes, sha256).
2. The app reads the release file on the sign-in screen and every time the runs list opens (throttled
   to once a minute, silent when offline). If the file's `version_code` is higher than the build's, a
   banner appears: "RideAVL 1.0.11 is ready. Update."
3. Update downloads the APK into the app's own cache (native `AppUpdaterPlugin`, plain HTTP to
   `10.0.0.16` over the tunnel like everything else) and opens the Android package installer. The driver
   taps Install; Android replaces the app and it reopens on the new build.
4. `"required": true` in the release file (or `min_version_code` above the build) turns the banner red and
   disables the Sign In button until the update is done. Use it when a release changes the API contract.

**Once per tablet, ever**: Android must be told to allow installs from RideAVL ("Install unknown apps").
The first Update tap opens that settings page; flip the switch and come back, and the installer opens by
itself. Fold this into the last manual round (installing 1.0.10), after which no tablet needs touching.

Fully silent installs need device-owner mode, which these tablets cannot have. One Install tap per
release is as far as Android allows without an MDM.

## Publishing a release

```sh
cd ~/rptest/rideavl-v2
# bump versionCode and versionName in android/app/build.gradle (versionCode must go up)
npm run apk                                   # builds android/app/build/outputs/apk/prod/debug/app-prod-debug.apk
git commit -am "RideAVL 1.0.11: ..." && git push

cd ~/rptest/ridepilot
ops/release-rideavl.sh --notes "What changed, in one line for the banner"   # add --required if old builds must not sign in
git commit -m "Pilot APK: RideAVL 1.0.11" && git push
```

The script copies the APK into `public/`, backs the previous one up to `~/ridepilot-ops/`, writes the
release file from the gradle version, and stages both. Tablets see the banner within a minute of opening
the app. The QR code and the browser download still work for a fresh tablet.

## Pieces

- rideavl-v2: `android/.../AppUpdaterPlugin.java` (download, canInstall, install), registered in
  `MainActivity`; `REQUEST_INSTALL_PACKAGES` in the manifest; `updates/` added to `file_paths.xml`;
  `src/app/services/app-update.service.ts`; `src/app/components/update-banner.component.ts`; banner on
  the sign-in and runs pages.
- ridepilot: `ops/release-rideavl.sh`, `public/rideavl-version.json` (un-ignored in `.gitignore`), the
  existing `\.apk$` nginx location (the JSON goes through the Rails public file server).
- The training flavour reads `rideavl-training-version.json` from its own host (10.0.0.15); publish there
  the same way when a training build goes out.

## If it does not work

| Symptom | Look at |
|---|---|
| No banner on a tablet that should update | `curl http://10.0.0.16/rideavl-version.json`; is `version_code` higher than the tablet's build (sign-in footer shows the version)? Tablet on the tunnel? |
| Banner, but Update opens Settings every time | the "Install unknown apps" switch for RideAVL is still off on that tablet |
| "Download failed" | APK reachable at `http://10.0.0.16/rideavl-pilot.apk` from the tablet? Content-Length matches the file? |
| Installer says the app is not installed / signature mismatch | the APK was signed with a different key than the one on the tablet; both must come from the same `rideavl.keystore` / debug key |

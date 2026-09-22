# RideAVL over-the-air updates

**Renamed 2026-09-21** (agreed with Andrew before the first InTouch rollout): the app is now **GCRPC
Demand Response**, application id `org.gcrpc.transit.demandresponse`, version 1.0.14. It was RideAVL,
`com.victoriatransit.rideavl`. A new application id is a new app: it installs beside the old one and
never over it, so old copies on test tablets are uninstalled by hand (`adb uninstall
com.victoriatransit.rideavl`). Nothing was in service under the old id. The repo (`rideavl-v2`), this
file, the release script and the OTA slot files (`public/rideavl-pilot.apk`, `rideavl-version.json`)
keep their names: the app reads those paths and they are internal. Its sibling GCRPC Driver became
**GCRPC Fixed Route** (`org.gcrpc.transit.fixedroute`) the same day.

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

**Google Play Protect** (Samsung tablets, Android 11): on each install it may show "App scan
recommended" with Scan app / Don't install app. Tap **More details**, then **Install without scanning**.
Scan app also works (it uploads the APK to Google and then installs). To stop the prompt for good on a
tablet: Play Store -> profile -> Play Protect -> settings -> turn off "Scan apps with Play Protect".

Fully silent installs need device-owner mode, which these tablets cannot have. One Install tap per
release (plus the Play Protect tap) is as far as Android allows without an MDM.

**1.0.16 (2026-09-22):** End run is gated on the post-trip inspection (it used to be a separate button a driver could skip). Not yet tested on a device.

**Tested 2026-09-11** on a Galaxy Tab Active Pro (SM-T547U, Android 11): 1.0.10 installed by USB, then
1.0.11 and 1.0.12 arrived through the banner. Download took about a second on the office Wi-Fi.

## Signing: the fleet key from 1.0.13 (2026-09-21)

Through 1.0.12 the tablets ran a *debug* build signed with the Android debug key. From 1.0.13 RideAVL is
a proper release build (not debuggable, WebView not inspectable) signed with the GCRPC fleet key, the
same key as GCRPC Driver (`~/keystores/gcrpc-fixedroute.keystore`, alias `gcrpc-driver`, certificate
`8f744b22…`). One key to back up and rotate for both apps.

Android will not install a fleet-signed build over a debug-signed one. No tablet was running RideAVL in
service at the switch (2026-09-21), so InTouch installs 1.0.13 fresh and nothing needs uninstalling. The
exception is any test tablet that still has the debug-signed 1.0.12 or older: uninstall RideAVL there,
then install. `public/rideavl-pilot.apk` (the slot the app polls) has held the fleet-signed 1.0.13 since
2026-09-21.

## Publishing a release

```sh
cd ~/rptest/rideavl-v2
# bump versionCode and versionName in android/app/build.gradle (versionCode must go up)
npm run apk:release                           # android/app/build/outputs/apk/prod/release/app-prod-release-unsigned.apk
BT=~/android-sdk/build-tools/35.0.0
$BT/apksigner sign --ks ~/keystores/gcrpc-fixedroute.keystore --ks-key-alias gcrpc-driver \
  --out dist/rideavl-1.0.14.apk android/app/build/outputs/apk/prod/release/app-prod-release-unsigned.apk
git commit -am "RideAVL 1.0.14: ..." && git push

cd ~/rptest/ridepilot
ops/release-rideavl.sh --notes "What changed, in one line for the banner" ~/rptest/rideavl-v2/dist/rideavl-1.0.14.apk   # add --required if old builds must not sign in
git commit -m "Pilot APK: RideAVL 1.0.11" && git push
```

The script copies the APK into `public/`, backs the previous one up to `~/ridepilot-ops/`, writes the
release file from the gradle version, and stages both. Tablets see the banner within a minute of opening
the app. The QR code and the browser download still work for a fresh tablet.

## The one place for tablet software

**https://fixedroute.internal.gcrpc.org/static/apk/** lists both tablet apps (RideAVL and GCRPC
Driver) with QR codes, checksums and signing certificates; it is linked from apps.internal.gcrpc.org
("Tablet Apps"). `ops/release-rideavl.sh` publishes there as well as to `public/`, so Ron and the
over-the-air updater always see the same build. GCRPC Driver updates the same way; see
`gcrpc-fixedroute/ops/tablet-ota.md`.

## Pieces

- rideavl-v2: `android/.../AppUpdaterPlugin.java` (download, canInstall, install), registered in
  `MainActivity`; `REQUEST_INSTALL_PACKAGES` in the manifest; `updates/` added to `file_paths.xml`;
  `src/app/services/app-update.service.ts`; `src/app/components/update-banner.component.ts`; banner on
  the sign-in and runs pages.
- ridepilot: `ops/release-rideavl.sh`, `public/rideavl-version.json` (un-ignored in `.gitignore`), the
  existing `\.apk$` nginx location (the JSON goes through the Rails public file server), and a
  `/rideavl-*.json` entry in `config/initializers/cors.rb` (the WebView's origin is localhost; without
  the CORS header the check fails silently and no banner appears).
- The training flavour reads `rideavl-training-version.json` from its own host (10.0.0.15); publish there
  the same way when a training build goes out.

## If it does not work

| Symptom | Look at |
|---|---|
| No banner on a tablet that should update | `curl http://10.0.0.16/rideavl-version.json`; is `version_code` higher than the tablet's build (sign-in footer shows the version)? Tablet on the tunnel? |
| Banner, but Update opens Settings every time | the "Install unknown apps" switch for RideAVL is still off on that tablet |
| "Download failed" | APK reachable at `http://10.0.0.16/rideavl-pilot.apk` from the tablet? Content-Length matches the file? |
| Installer says the app is not installed / signature mismatch | the tablet still has the debug-signed 1.0.12 or older: uninstall RideAVL, then install (see "Signing" above). Builds from 1.0.13 on are all on the fleet key, so this only happens once per tablet |

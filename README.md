# CommuteScout Drive

Turn-by-turn navigation that knows what is on the road ahead. Search a place, save Home and Work, pick a route, and drive: closures, incidents, chain controls and fires along the route show up above the trip bar and are spoken about a minute ahead.

Both apps talk only to [commutescout.com](https://commutescout.com). Routing, map tiles and search go through the site, so no map or routing key ships in the app and every route already avoids full closures.

## Install

- **iOS**: TestFlight. Testers get an invitation by email from App Store Connect.
- **Android**: download the APK from the latest [release](https://github.com/nicglazkov/commutescout-app/releases), open it on the phone, and allow installing from that source when asked.

## What it does

| | iOS | Android |
|---|---|---|
| Map that follows you | yes | yes |
| Search a place, address or coordinates | yes | yes |
| Home, Work, favorites, recents | yes | yes |
| Alternatives before you start | yes | yes |
| Turn-by-turn with voice | yes | yes |
| Speed limit sign | yes | yes |
| Live alerts on the route, spoken ahead | yes | yes |
| Rerouting when you leave the route | yes | yes |
| Miles or kilometers (locale default) | yes | yes |

## Layout

- `ios/`: SwiftUI app over [Ferrostar](https://github.com/stadiamaps/ferrostar) and MapLibre. `project.yml` is the XcodeGen spec.
- `android/`: Jetpack Compose app over the Ferrostar Android artifacts and MapLibre Compose.
- `scripts/`: `sync_mac.sh` copies the tree to the build Mac, `ios_build.sh sim|run|testflight` builds, `ios_signing.sh` sets up signing from an App Store Connect API key.

## Build

iOS (on a Mac with Xcode 26 and `xcodegen`):

```sh
scripts/ios_build.sh sim        # build for the simulator
scripts/ios_build.sh run        # install and launch on the booted simulator
scripts/ios_build.sh testflight # archive, export, upload
```

Android:

```sh
cd android
./gradlew :app:assembleDebug
./gradlew :app:assembleRelease -PversionCode=2   # needs keystore.properties (not committed)
```

Debug builds accept a scripted drive for testing without a car: `-csAutoDrive` on iOS, `--ez csAutoDrive true` on Android.

## Backend endpoints used

- `POST /api/nav/route`: Valhalla request in, OSRM response out, closures excluded server-side.
- `GET /api/tiles/style.json` and `/api/tiles/{style}/{z}/{x}/{y}@2x.png`: base map.
- `GET /api/suggest`, `GET /api/geocode`: search.
- `GET /api/mapdata`: the markers the website draws, filtered to a box around the route.

Map tiles and routing by Stadia Maps, data (c) OpenStreetMap contributors. Road data from the agencies listed on commutescout.com. Verify before you drive.

# CommuteScout Drive

Turn-by-turn navigation that knows what is on the road ahead. Search a place, save Home and Work, pick a route, and drive: closures, incidents, chain controls, fires and community reports along the route show up under the maneuver card and are spoken ahead of time, at the distances you choose.

Both apps talk only to [commutescout.com](https://commutescout.com). Routing, map tiles, search, live data, sign-in and reports all go through the site, so no map or routing key ships in the app and every route already avoids full closures. The apps mirror the website's tools; the site holds the documentation, the data-source list and the developer docs, and the apps link back to it.

## Install

- **iOS**: TestFlight. Testers get an invitation by email from App Store Connect.
- **Android**: download the APK from the latest [release](https://github.com/nicglazkov/commutescout-app/releases), open it on the phone, and allow installing from that source when asked.

## What it does

| | iOS | Android |
|---|---|---|
| Map that follows you, 2D or 3D, pinch, rotate, tilt, quick zoom | yes | yes |
| Live markers: incidents, closures, chain controls, fires, community reports, with a card on tap | yes | yes |
| Layers: base map (light, dark, outdoors, match theme), traffic, per-kind toggles | yes | yes |
| Search a place, address or coordinates as you type; long-press to drop a pin | yes | yes |
| Home, Work, favorites, recents | yes | yes |
| Alternatives before you start, drawn on the map; directions from another start | yes | yes |
| Turn-by-turn with voice, speed limit, rerouting | yes | yes |
| Alerts on the route, spoken ahead; advanced per-kind distances and repeats | yes | yes |
| Report from the road (Waze-style kinds), signed in | yes | yes |
| Sign in with Google (and Apple on iOS): the same account as the website | yes | yes |
| Alerts nearby, Watch areas, Ask about the roads | yes | yes |
| Community sources: public Flare plugins and your own private ones by URL | yes | yes |
| Light and dark mode, miles or kilometers | yes | yes |

## Layout

- `ios/`: SwiftUI app over [Ferrostar](https://github.com/stadiamaps/ferrostar) and MapLibre. `project.yml` is the XcodeGen spec. `UITests/` drives every flow in the simulator.
- `android/`: Jetpack Compose app over the Ferrostar Android artifacts and MapLibre Compose.
- `scripts/`: `sync_mac.sh` copies the tree to the build Mac, `ios_build.sh sim|run|testflight` builds, `ios_signing.sh` sets up signing from an App Store Connect API key.

Firebase config files (`ios/CommuteScoutDrive/GoogleService-Info.plist`, `android/app/google-services.json`) are not committed; the Android build works without one, with sign-in disabled.

## Build

iOS (on a Mac with Xcode 26 and `xcodegen`):

```sh
scripts/ios_build.sh sim        # build for the simulator
scripts/ios_build.sh run        # install and launch on the booted simulator
scripts/ios_build.sh testflight # archive, export, upload
xcodebuild -project ios/CommuteScoutDrive.xcodeproj -scheme CommuteScoutDrive \
  -destination "platform=iOS Simulator,name=iPhone 17" test   # UI tests
```

Android:

```sh
cd android
./gradlew :app:assembleDebug
./gradlew :app:assembleRelease -PversionCode=3   # needs keystore.properties (not committed)
```

Debug builds accept a scripted drive for testing without a car: `-csAutoDrive` (and `-csSimulate`, `-csFocusMarker`) on iOS, `--ez csAutoDrive true` on Android.

## Backend endpoints used

- `POST /api/nav/route`: Valhalla request in, OSRM response out, closures excluded server-side.
- `GET /api/tiles/style.json?style=`, `/api/tiles/{style}/{z}/{x}/{y}@2x.png`, `/api/traffictile/…`: base map and traffic.
- `GET /api/suggest`, `GET /api/geocode`: search.
- `GET /api/mapdata`: the markers the website draws, for the area on screen.
- `GET /api/flare/sources`, `POST /api/flare/report`, `POST /api/flare/confirm`: community sources and reports (Bearer ID token).
- `GET /api/watch/me`, `POST /api/watch/create`, `DELETE /api/watch/{id}`, `DELETE /api/watch/account`: watch areas and the account.
- `POST /api/ask`: the assistant, streamed.
- Private plugins are read straight from the phone through the [Flare](https://commutescout.com/developers) endpoints `/flare/v1/handshake`, `/flare/v1/alerts`, `/flare/v1/report`.

Map tiles and routing by Stadia Maps, data (c) OpenStreetMap contributors. Road data from the agencies listed on commutescout.com. Verify before you drive.

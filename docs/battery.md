# Battery

A 20 minute drive used 10% of a healthy iPhone 17 Pro battery on 0.6.0.
This page says where that went, what 0.6.1 changed, and how to measure it
again. The rules live in one file per app: `ios/CommuteScoutDrive/PowerPolicy.swift`
and `android/app/src/main/java/com/commutescout/drive/Power.kt`, both under
unit tests.

## Where the power went (0.6.0)

1. **GPS at navigation grade all the time, plus the compass.** Ferrostar's
   `CoreLocationProvider` asks for `kCLLocationAccuracyBestForNavigation`
   with no distance filter and starts heading updates the moment it exists.
   Nothing reads the heading (FerrostarCore drops it).
2. **A second GPS client inside the map.** With no trip running,
   Ferrostar's `NavigationMapView` hands MapLibre a nil location manager, so
   MapLibre makes its own `CLLocationManager` and runs it beside the app's.
3. **The map drawn at the display's full rate for the whole drive.** About
   60 frames a second while following the car.
4. **An alert ring that never stopped breathing.** A one second timer
   changed the ring's size for as long as an alert was ahead (alerts look
   16 km ahead), and every change makes MapLibre draw again. On Android an
   infinite Compose animation did the same and recomposed the map content
   every frame.
5. **About three SwiftUI redraws of the whole screen per GPS fix.** The fix,
   the trip update and the compass each took their own turn of the main
   thread.
6. **Fetches on their own timers.** Viewport markers every 60 s and on
   every pan out of a small box, route alerts every 60 s, the 4.7 MB
   country snapshot every 5 minutes, plugin polls every 15 s, the speed
   limit every 45 s. Each wakes the cellular radio, which then stays powered
   for several seconds. Every viewport answer, changed or not, rebuilt all
   ~17,000 map features and sent them to MapLibre again.
7. **Background work on a trip.** With the screen off on a trip, the map's
   markers and plugin dots kept fetching for a map nobody could see.

## What runs now

| | No trip, standing | Driving, no trip | Trip |
|---|---|---|---|
| GPS accuracy | 10 m | best | navigation |
| Distance filter | 15 m | 10 m | 5 m |
| Compass | off | off | off |
| GPS in background | off | off | on (voice from the pocket) |
| Map frame rate | 30, full while touched | 30, full while touched | 30, full while touched |

- All timed fetches run on one 60 s beat aligned to the clock, so they
  leave together. Plugins are polled at most once a minute and not at all
  in the background. The snapshot is read every 10 minutes standing, 30 on
  the move, with an ETag so an unchanged file is a 304.
- The viewport box is snapped to a 0.05 degree grid with a cell to spare,
  so following the car asks again every few kilometres. An answer equal to
  the last one changes nothing.
- On a trip, alerts are fetched for the road from 1 km behind to 50 km
  ahead, and the window moves on 25 km in, not for the whole route.
- The alert ring breathes for 8 seconds when a new alert takes the banner,
  then holds still.
- One SwiftUI update per fix: the fix and the trip update are handled in
  the same main-thread turn, and the compass only redraws for turns of 2
  degrees or more and never on a trip.
- The screen stays on only while a trip runs or the car is moving, and
  only if Settings > Keep the screen on is on (it is by default).

Navigation itself did not change: a trip still gets navigation-grade fixes
about once a second at road speed, the same reroute rules and the same
alert distances.

## Measuring

Debug builds count what costs power when launched with `-csPerf`
(`PerfProbe.swift`): map frames, location fixes, screen redraws, marker
rebuilds and app requests, one `CSPERF` line every 10 seconds. Release
builds do not have it.

The bench drives a simulator from downtown San Jose to Palo Alto (28 km,
about 20 minutes, city streets then freeway) with `xcrun simctl location`
and records the app's CPU time and the CSPERF lines. A simulator has no
real GPS, radio or display, so it shows the app's own work, not the
phone's power draw. A real drive and Settings > Battery are the final test.

## Results (simulator, 0.6.0 vs 0.6.1, 20 minute drive)

| | Trip 0.6.0 | Trip 0.6.1 | No trip 0.6.0 | No trip 0.6.1 |
|---|---|---|---|---|
| App CPU, average | 18.3% | 10.7% | 15.7% | 9.1% |
| App CPU, 95th percentile | 29.9% | 16.5% | 26.3% | 14.2% |
| App CPU, peak | 44.2% | 21.7% | 46.1% | 18.5% |
| Map frames per second | 55.5 | 27.5 | 51.1 | 25.2 |
| Screen redraws per fix | 2.98 | 1.22 | 2.76 | 1.07 |
| Location fixes per minute | 58 | 54 | 58 | 50 |
| Marker rebuilds (whole drive) | 51 | 14 | 54 | 19 |
| Snapshot downloads | 8 | 2 | 8 | 2 |
| App network tasks per minute | 7.6 | 6.8 | 7.4 | 6.2 |

Measured on an iPhone 17 Pro simulator on an M-series MacBook, Release
build with the probe compiled in. Network tasks include map tiles.

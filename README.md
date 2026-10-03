# WHOOP 4 Bridge

An Android-only fork of OpenStrap Edge that reads a WHOOP 4 directly over Bluetooth and writes its data to Android Health Connect. No WHOOP account, subscription, cloud backend, or API token is used. A health app that reads Health Connect supplies the dashboard.

The bridge keeps a small pairing/status screen, a foreground Bluetooth service, durable local storage, and the existing nightly computation pipeline. Heart rate exports as minute averages shortly after history arrives. Sleep/stages, resting heart rate, RMSSD HRV, and respiratory rate export when nightly results are available. Missing measurements remain absent. Scores, steps, calories, workouts, AI, GPS, telemetry, widgets, other wearables, and other platform targets are excluded.

## Setup

1. Install the APK on Android with Health Connect available (Android 9 or later; built in on Android 14+).
2. Find and pair your WHOOP 4. Avoid another app holding the band connection during pairing.
3. Enable Health Connect export and grant the requested permissions.
4. Allow background battery use, then enable Health Connect reading in your chosen health app.

Use **Sync now** to retry or migrate previous exports. Background capture uses a quiet foreground notification. Force-stop, Bluetooth restrictions, battery policies, or an out-of-range band interrupt syncing. The receiving app controls when its dashboard refreshes. This is near-real-time historical sync, not a guaranteed live stream.

Existing OpenStrap installations retain their database and package identity. Old Health Connect exports migrate only during explicit foreground sync; own legacy records are copied/replaced before targeted cleanup. New data keeps exporting while old migration is pending. **Delete local data** pauses and forgets the band, retaining Health Connect records; already acknowledged band history may be unrecoverable.

## Build and verification

Flutter 3.41.6, Java 17+, and Android SDK are required. Protocol and analytics dependencies remain pinned to full commit SHAs.

```sh
flutter pub get
flutter analyze
flutter test --concurrency=1
flutter build apk --release
cd android
./gradlew app:testDebugUnitTest
```

Release signing uses the existing Android keystore environment variables in `android/app/build.gradle.kts`. Without a release key a local build uses the debug signing key and cannot replace an installation signed by another key.

See [the implementation plan](docs/WHOOP4_BRIDGE_PLAN.md) for scope and real-device acceptance checks. Subscription-free operation and background reliability must be verified with the owner's WHOOP 4; desktop tests cannot prove device firmware behavior.

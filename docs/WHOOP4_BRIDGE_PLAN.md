# WHOOP 4 Android Health Connect bridge

Status: implementation plan; application code has not changed.

## Objective

Use the owner's WHOOP 4 without a WHOOP subscription. A small Android app owns
the Bluetooth connection, stores the band's data safely, and writes supported
health records to Health Connect. A separate Health Connect reader provides the
everyday dashboard. No WHOOP account, WHOOP cloud API, or hosted backend is needed.

The bridge must remain usable with its Activity closed. Android force-stop is
different from closing the UI: recovery after force-stop may require the user to
open the app again. Do not promise uninterrupted operation under every phone's
battery restrictions.

## Recommended approach

Reduce the existing Flutter application in stages, retaining its proven WHOOP 4
protocol, durable storage, and Android background machinery. Extract a small
coordinator from AppState before deleting features. Keep the current pinned
protocol and analytics packages; new metric implementations do not belong in edge.

Alternatives considered:

- Hide the existing dashboards: quickest to try, but retains unrelated startup,
  permissions, background work, and maintenance. Useful as a baseline only.
- Rewrite in native Kotlin: potentially a smaller final app, but requires porting
  the Dart protocol and analytics, reproducing recovery policies, and validating
  history acknowledgments again. Unnecessary for the first version.

## First-version scope

| Output | Decision | Input and processing |
| --- | --- | --- |
| Heart rate | Keep | WHOOP historical HR, one-minute averages |
| Sleep session and stages | Keep | Existing local sleep detection and staging |
| HRV | Keep | Existing cleaned beat intervals and nightly RMSSD |
| Resting heart rate | Keep | Existing nocturnal calculation |
| Respiratory rate | Keep | Existing beat-interval estimate |
| Calories | Defer | Estimates require profile and activity processing |
| Workouts and GPS routes | Defer | Separate activity/session product scope |
| Steps | Exclude | Current exporter deliberately does not write steps |
| SpO2 and skin temperature | Defer | Current exporter has no writer for these |
| Readiness, strain, stress | Exclude | Not standard exported records |

Missing or insufficient measurements produce no record. These are OpenStrap's
locally calculated metrics, not WHOOP's proprietary scores. The receiving app's
support for displaying each record type must be checked on the user's phone.

## Minimal interface

Keep onboarding for WHOOP 4 pairing, Bluetooth permission, Health Connect write
permission, companion-device association, and Android battery settings.

After onboarding, show one status screen:

- Paired band and battery level.
- Connected, reconnecting, Bluetooth disabled, or actionable error.
- Last band data received and last successful Health Connect write, separately.
- Pending export status, Sync now, and links to Health Connect permissions.
- Pause/resume syncing, unpair, and explicit local-data deletion.

Retain the Android ongoing-service notification. Avoid dashboards and metric
charts. A reader app cannot manage this bridge's Bluetooth pairing or permissions.

## Implementation sequence

### 1. Establish a working baseline

Use Flutter 3.41.6, matching the current CI pin, and the full sibling SHAs from
pubspec.yaml. Confirm a clean dependency resolution without tracked path overrides.
Run the existing analyze/tests and an Android build before refactoring.

On a real WHOOP 4, confirm pairing, historical drain, screen-off capture, and
current Health Connect records. Record firmware, phone/Android version, export
latency, and overnight battery use. Verify the chosen reader displays HR, sleep,
and nightly metrics before assuming it can replace the app's dashboard.

### 2. Extract the bridge lifecycle

Introduce a small bridge coordinator owning paired-device state, BLE lifecycle,
durable ingest callbacks, reconnects, derivation scheduling, and export scheduling.
Make the minimal app shell and Android service use that coordinator.

Reuse BleEngine, the WHOOP 4 adapter, BandHost's commit seam, RecordGate,
BandOwnership, HeadlessSyncGate, and reset protection. Keep one active band owner
and one frame-ingest path. Do not duplicate the drain implementation.

Preserve decoded rows and cursor commits in one transaction before echoing the
original HISTORY_END token. Health Connect failures must never block durable
local ingest or cause premature band acknowledgment.

### 3. Separate heart-rate export from day derivation

The current exporter selects day_result rows even for HR sourced directly from
decoded_onehz. Give measured HR its own export entry point over committed band
samples, independent of sleep and day_result availability.

Replace routine whole-day HR deletion/replacement with bounded, idempotent minute
batches. Use stable Health Connect client identities/versioning and persistent
local export progress. Revisit the mutable tail minute and mark replacements
dirty when INSERT-OR-REPLACE corrects older source rows; a timestamp-only watermark
must not permanently miss corrections. Retain an explicit historical replay path.

Advance export progress only after successful writes. Serialize overlapping
exports, persist retry state, and recover from permission denial, quota errors,
process death, and a successful remote write followed by a local progress-write
failure without duplicating records.

### 4. Make every background path deliver data

Run the same export scheduler after foreground drains, screen-off drains, headless
boot/recovery drains, and reconnect catch-up. The current runHeadlessSync stores
and derives data but never invokes HealthExporter; close this gap explicitly.

Keep EdgeTrackingService, KeepAliveWorker, CompanionBridge, BootReceiver,
AndroidBootSignal, the cached Flutter engine, and required native channels.
Check actual lifecycle behavior rather than trusting stale file headers.

A failed export leaves a durable backlog for the next eligible run. Resuming the
app or restoring permissions retries it. Headless work skips an already-owned
session rather than creating a second connection or queued competing drain.

### 5. Retain only necessary nightly computation

Keep substrate decoding, local-day handling, sleep segmentation/staging, cleaned
RR processing, and the existing nightly HRV/RHR/respiratory computations. Remove
unrelated analytics orchestration after tracing their actual dependencies.

Heavy processing remains inside isolates. Preserve the existing metrics' behavior
and absent-input rules. If any analytics output changes, bump kAlgoVersion and
document the change; verify any sibling change against its actual pinned SHA.

Publish nightly records after computation succeeds. Recompute and replace our own
changed sleep/nightly records safely, without deleting another app's data.

### 6. Tune freshness using measured results

First remove the 30-minute rewrite throttle from incremental HR export; retain
appropriate batching and quotas. Export newly committed HR promptly rather than
waiting for a full day derivation.

Begin with the existing history-pull cadence. Trial a shorter cadence, such as
five minutes, on WHOOP 4 only after confirming its flash-data availability, BLE
stability, and phone/band battery cost. Do not merely change a timer and promise
five-minute delivery. Empty-drain backoff and reconnect policies remain necessary.

Measure band-to-local-store and local-store-to-Health-Connect latency separately.
The receiving dashboard's refresh interval is outside the bridge's control.
Sleep and nightly metrics are available after sufficient sleep data and processing,
not second by second. Do not persist the high-rate live streams to bypass this.

### 7. Remove unused features and dependencies

Once the bridge works end to end, remove references, then implementations, then
dependencies and native configuration in reviewable groups:

- Other wearable adapters, WHOOP 5/MG-only entry points, and discovery options.
- Existing dashboards, charts, trends, recaps, coach, AI, and journal.
- GPS/workout UI, alarms, cycle/nutrition flows, and unrelated health imports.
- Widgets/watch/Siri, iOS platform files, cloud upload, and optional telemetry.
- Unused permissions, method channels, packages, assets, and startup initializers.

Do not rewrite shared BLE policies solely to remove dormant Gen5 branches if doing
so risks WHOOP 4 behavior. No non-WHOOP-4 device is offered or supported by the app.

Keep the existing DB schema during initial extraction. Old tables are less risky
than destructive migration. Later storage cleanup must remain additive/idempotent;
do not prune raw data for incompletely derived or unsuccessfully exported windows.
Do not reset pairing or delete existing user data as part of slimming the app.

### 8. Build and prove the replacement

Run flutter analyze, flutter test --concurrency=1, affected native tests, and the
release APK build. Retain regression coverage for ACK ordering, counter-reset
replacement, reconnect policies, headless ownership, missing metrics, local day
boundaries, and export retries/deduplication. Replace removed-screen tests with
meaningful bridge behavior tests rather than leaving broken imports.

Keep the Android application ID/signing identity for an in-place upgrade when
the existing signing key is available. Preserve pairing/database state, retain
the version +BUILD suffix, and increase versionCode. Verify Health Connect
ownership and legacy record cleanup; a new package would be a different writer.

## Acceptance checks

- WHOOP 4 pairs and syncs without WHOOP credentials or a subscription.
- Only WHOOP 4 is selectable; normal startup initializes only bridge features.
- HR reaches Health Connect before any derived day exists.
- Closing the Activity and locking the phone still allows capture and export.
- Reboot/recovery and reconnect both drain and export through the same coordinator.
- Disconnecting for several hours catches up without lost or duplicate samples.
- Repeating sync and retrying after process death produces stable record counts.
- Corrected historical HR replaces previously exported values.
- Revoked health permissions preserve local data and show an actionable status.
- Missing/thin data produces no invented HRV, sleep stage, or respiratory record.
- A real overnight run delivers sleep and nightly metrics to the selected reader.
- ACK-ordering and counter-reset regression tests still pass.
- The slim build has no unused location, AI, telemetry, or other-device flows.

Automated checks prove code behavior; screen-off reliability, battery cost, reader
compatibility, and actual WHOOP firmware behavior require a physical phone/band.
An emulator cannot establish those outcomes.

## Delivery boundaries

Make the bridge work before deleting the broad feature tree. The first usable APK
should provide pairing/status, background capture, incremental HR export, and
nightly metrics. Remove remaining unused code after those acceptance checks pass.
Optional calories, workouts, SpO2, and temperature can be separate later work if
the owner needs them and the reader supports them.

## Implemented state

The Android bridge now has one setup/status screen and one retained-engine coordinator. Direct WHOOP 4 capture writes a durable minute outbox in the same database transaction; Health Connect export runs independently of derivation. Native writes use stable client IDs and monotonic versions. Legacy anonymous exports migrate only on explicit foreground actions, with replacement/copy before targeted deletion. Pause/unpair is mirrored to native boot, companion, and watchdog entry points. Local deletion preserves Health Connect records.

The runtime tree is reduced from 286 tracked Dart files to 45. Other platform targets, dashboards, AI, GPS, telemetry, widgets, and non-WHOOP adapters are removed. Existing database schema and nightly orchestration remain for migration compatibility and sleep computation. Protocol/analytics pins and algorithm version are unchanged; Android version is 0.10.1+68.

Automated source analysis, the retained regression suite, native tests, release assembly, and targeted real-database retention/query-plan tests are recorded in GATES.md. The APK uses the local debug signing certificate; an in-place upgrade of an installation signed with another key needs that original release key. Physical WHOOP 4 screen-off sync, actual firmware behavior, battery cost, and receiving-app refresh remain unverified because no connected phone/band is available. Historical guide and screenshot folders remain after automatic approval review rejected their deletion.

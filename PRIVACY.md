# Privacy — WHOOP 4 Bridge

The bridge stores band records and derived nightly results in SQLite on your phone. It connects directly to your WHOOP 4 over Bluetooth. It does not use a WHOOP account, send data to an OpenStrap backend, collect telemetry, invoke AI services, or upload health data.

Health Connect export is off until you enable it and grant permissions. The exported types are heart rate, sleep/stages, resting heart rate, RMSSD HRV, and respiratory rate. Your selected health app controls its own access to Health Connect and any further use of that data.

Fresh installs request write access. Upgrades that contain old export cursors also request read access to migrate this app's own anonymous Health Connect records during explicit foreground sync. Migration targets only records from this package; it does not delete another app's records.

Android backup is disabled. **Delete local data** stops sync, forgets the band, and erases the local database while retaining Health Connect history. To delete Health Connect history, use Health Connect's own data-management controls.

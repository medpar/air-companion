<p align="center"><img src="docs/brand/pebble-icon.svg" width="96" alt="Pebble icon"></p>

# Pebble

A native, offline iPhone companion for the Fitbit Air. Alarms, vibration
alerts, live heart rate and evidence-based training and recovery trends, built
on short authenticated Bluetooth sessions that share the band with Google Health.
No firmware changes, no account, no cloud.

<p>
<img src="docs/screenshots/today.png" alt="Today" width="200">
<img src="docs/screenshots/alarms.png" alt="Alarms" width="200">
<img src="docs/screenshots/trends.png" alt="Trends" width="200">
<img src="docs/screenshots/band.png" alt="Band" width="200">
</p>

## Features

| Feature | How it works | Verified on the physical Air |
| --- | --- | --- |
| Alarms: add, edit, repeat, smart wake, delete | Fresh read, conflict check, protected backup, read-back verification | Yes (2026-10-15) |
| Vibration intensity (Off/Low/High) | Advertised options only, verified read-back | Yes |
| Vibration patterns: Single, Double, Triple, Long gap, Urgent | 1–5 buzzes via intensity toggle, spaced so the count is feelable; restored and verified | Yes — owner counted Triple's 3 buzzes on the band |
| Per-event alerts: calls, daily goal, step milestones, move reminder, Shortcuts | Each event has its own pattern, plus an optional iPhone notification or webhook | Goal buzz and foreground call buzz verified earlier; new engine covered by tests |
| Background alerts | Opt-in **Keep Pebble running** (silent mixable audio session, `voip` + `audio` modes) plus adaptive step checks | Background call → band buzz verified via CallKit test; real locked call needs one owner confirmation |
| Shortcuts & Siri | App Intents: **Buzz Band**, **Get Steps**, **Get Band Battery** | Built and registered; run on device pending |
| Steps, heart rate, battery | Activity-only read (~3 s) or full sync (~5 s) | Yes |
| Live heart rate | Standard Bluetooth Heart Rate Profile while *Share heart rate* is on in Google Health; zones, RMSSD from RR intervals, Edwards load | Needs sharing turned on |
| Readiness | Transparent 0–100 recovery score from your own HRV, resting HR, sleep duration and regularity, each component shown | Logic tested; uses Apple Health data |
| Trends | Steps, sleep, resting HR, HRV; sleep timing with regularity and social jetlag; 7-day average against your own usual range | Logic tested; uses Apple Health data |
| Training | Session-RPE load, Banister fitness/fatigue/form, EWMA acute:chronic ratio, weekly ramp, HRV CV, VO₂max vs age/sex norms, Karvonen zones | Logic tested |

### What the Air can't do from an iPhone

- **Other apps' notifications.** Bands that show notifications on an iPhone use
  Apple's ANCS from their firmware. The Air doesn't subscribe to ANCS (confirmed
  with a Bluetooth trace), and iOS gives no app access to other apps'
  notifications. Pebble uses Shortcuts automations instead: *Message* or *Email*
  trigger → **Buzz Band**.
- **LED colour.** Decompilation found no app-addressable LED for any Fitbit
  model; the notification `color` field is a UI accent for screened devices. The
  Air's light is firmware battery status (white ≥20 %, red <20 %) only.
- **Double-tap / gestures as a phone trigger.** Decompilation confirms the Air
  exports no tap or gesture event — double-tap is an on-device alarm-dismissal
  behaviour only, and there is no accelerometer/gyro stream. The one defined
  interaction event is wrist on/off, which this Air has never emitted. Pebble's
  **Listen for band events** screen shows any event code (unknown ones as
  four-character codes) so a trigger can be wired if the firmware ever emits one.
- **A permanent connection.** The Air accepts one secure-session owner at a
  time. Pebble connects briefly and disconnects, so Google Health keeps syncing.

## Using it

1. Import your Air's device-key file in **Band → Device key** (stored in the
   device-only Keychain, never in the repo or binary).
2. Pull down on Today or Alarms to sync. Pebble also syncs when opened if the
   last read is over 10 minutes old.
3. Choose alerts and patterns in **Band → Alerts**. Turn on **Keep Pebble
   running** for calls and step alerts while the phone is locked; it uses extra
   iPhone battery.
4. Forward messages: Shortcuts → Automation → *Message* → *Run Immediately* →
   add **Buzz Band**.
5. Optional: add a webhook URL to receive `{"event":"goal","steps":10240,…}` for
   Home Assistant, n8n or your own server.

## Methods

Each figure is explained in the app (**Trends → How these are calculated**) and in
[docs/METHODS.md](docs/METHODS.md). In short:

- **Usual range:** last 7 days against the previous 60 (needs 4 + 14 days).
  HRV uses log-scaled ±0.5 SD (Plews et al. 2013); resting HR and sleep use ±1 SD.
- **Training:** session RPE × minutes (Foster et al. 2001); fitness and fatigue
  are 42- and 7-day exponentially weighted loads (Banister et al. 1975).
- **Cardio fitness:** VO₂max ≈ 15.3 × HRmax / HRrest (Uth et al. 2004), HRmax =
  208 − 0.7 × age (Tanaka et al. 2001). Shown as an estimate, ±10–15 %.
- **Sleep timing:** midpoint of the main sleep episode; regularity is its
  14-night standard deviation.
- **Steps:** about 100 steps/min for moderate walking (Tudor-Locke et al. 2018);
  goal guidance from Paluch et al. 2022.
- **Readiness:** HRV-led recovery heuristic (HRV 40, resting HR 25, sleep 25,
  regularity 10), rescaled to available inputs (Plews et al. 2013; Buchheit 2014).
- **Workload:** EWMA acute:chronic ratio (Williams et al. 2017), shown after ~8
  training days with the 0.8–1.3 band as context, not a rule.
- **Circadian:** social jetlag = weekend vs weekday sleep-midpoint gap
  (Wittmann et al. 2006).
- **Cardio fitness:** VO₂max ranked against age/sex norms (Cooper Institute).

The daily Readiness score is a transparent, user-visible heuristic from your own
baselines — not a diagnosis, clinical measure or injury prediction.

## Build

Requires macOS, Xcode 27 with an iOS 18+ SDK, CMake 3.25+, Git and curl.

```sh
./scripts/prepare-native.sh
./scripts/build-simulator.sh
xcrun simctl install booted .private/simulator-project/Debug-iphonesimulator/AirCompanion.app
xcrun simctl launch booted com.medpar.air.companion --preview
```

Signed phone build (your own team; free Personal Team signing lasts 7 days):

```sh
AIR_DEVELOPMENT_TEAM=YOUR_TEAM_ID ./scripts/build-ios.sh
xcrun devicectl device install app --device DEVICE_ID .private/ios-project/Debug-iphoneos/AirCompanion.app
```

Set `CMAKE_BIN` if `cmake` isn't on your `PATH`. The bundle identifier stays
`com.medpar.air.companion`, so updates install over earlier builds and keep keys
and history.

### Offline checks

```sh
./scripts/check-offline.sh
```

Runs the encrypted synthetic-peer transport test, alarm parser, fitness/alert
engine, storage tests and 29 Python research-tool tests. No phone, band or key
is needed.

### USB diagnostics

`devicectl … process launch … com.medpar.air.companion` with:
`--diagnostic-refresh`, `--diagnostic activity`, `--diagnostic events`,
`--diagnostic pattern <single|double|triple|longGap|urgent>`,
`--diagnostic background-check`, `--preview`, `--tab N`. Reports are written to
the app's private `Documents/connection-report.json`.

## Privacy and safety

- No analytics, account or server. Health data is read-only and kept per source.
- Keys: device-only Keychain, readable after first unlock so locked alerts work.
- Every band write reads fresh state first, keeps a protected backup and verifies
  the result. Vibration patterns journal the original intensity and never
  overwrite a conflicting change. There are no firmware, reset, pairing or
  arbitrary-command paths.
- Raw captures, identifiers, keys and proprietary files stay in ignored
  `.private/` storage.

[Device acceptance](docs/DEVICE-ACCEPTANCE.md) · [Protocol](docs/PROTOCOL.md) ·
[Research log](docs/RESEARCH.md) · [Methods](docs/METHODS.md) ·
[Third-party notices](Native/THIRD_PARTY.md)

<img src="docs/screenshots/dark.png" alt="Pebble in dark mode" width="820">

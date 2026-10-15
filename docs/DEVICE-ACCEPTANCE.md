# Device acceptance

## Pebble 1.0 on 2026-10-15

The redesigned app was signed with the owner's Personal Team and installed over
the earlier build (same bundle identifier), keeping keys and history. Results
from the physical Air, using USB diagnostics and app metadata only:

- **Full sync:** authenticated, read 2 alarms, capabilities, haptic setting,
  battery and activity in about 5 s, then disconnected.
- **Activity-only read:** begin to clean close in about 3 s (11 fragments sent).
- **Urgent pattern:** four buzzes with the 0.45/1.35/0.45 s gaps; the original
  intensity was restored and read back after each one. The owner felt the
  pattern.
- **Tap discovery:** a read-only listening window while the owner firmly
  double-tapped the band and took it off once. Only the session-start `rset`
  events arrived. About a minute in, the link ended, plausibly when the band was
  removed. No tap or wrist event is exported on this route, so no tap trigger is
  offered.
- **Background execution:** with keep-alive started for that process only, Pebble
  was sent to the background by opening Settings. Its scheduled check ran 55 s
  later in the `background` state: connected, authenticated, read activity and
  closed cleanly. The process stayed alive afterwards.
- **Not yet tested on the device:** a real call while the phone is locked, a
  Shortcuts automation, live Heart Rate Profile streaming (needs *Share heart
  rate* on) and Apple Health import with the new metrics.

Device keys were migrated to after-first-unlock Keychain accessibility, and
band files now use until-first-authentication protection, so a locked phone can
deliver alerts.


## Verified on 2026-10-15

The owner reconnected the iPhone and authorized USB-controlled testing. The
signed development build was installed over the existing app, preserving keys
and the library. No pairing, firmware, or factory settings were changed.

- Authenticated refresh read two alarms, normal settings capabilities, current
  vibration intensity, steps and heart rate, then disconnected.
- The failing trace showed outgoing Gattlink sequence 3 before sequence 2 under
  CoreBluetooth backpressure. A bounded FIFO corrected this; the following
  trace had zero sequence discontinuities and all four reads completed.
- Created a temporary alarm. The Air returned CoAP 5.00 but created it enabled,
  despite the requested disabled flag. The app did not repeat POST. A separately
  verified edit disabled it, changed time/recurrence, and deletion restored the
  original two alarm configurations exactly.
- Added a narrowly checked post-creation correction for that firmware behavior.
  A second create test read the new alarm, turned it off with one PUT, verified
  the full list, then deleted the test alarm. Existing alarms were unchanged.
- Low → High → Low returned success and read-back matched the original. The
  owner confirmed feeling vibration. Two consecutive feedback groups also
  completed with restoration verified after each group.
- A separate acceptance library used a temporary one-step goal with the real
  activity reading. The real automation evaluator delivered one band vibration
  and recorded restoration. A second refresh after process relaunch kept one
  receipt and emitted zero vibration requests. The owner's real goal, rules and
  health/workout library were not modified.
- Final alarm snapshot exactly matched the original list. Google Health was
  relaunched successfully over USB afterward; its on-screen sync indicator was
  not available through the control surface, so full UI sync is not claimed.
- The owner confirmed a real incoming call produced one vibration. The report
  shows four seconds from connection start to the first intensity change and
  seven seconds to verified restoration. The owner requested faster delivery
  and multiple groups, with subsequent checks driven by local notifications.
- A local test notification was delivered at 11:01:01.051 UTC. The first
  vibration command was recorded in that same second; three groups completed
  with three original-intensity verifications by 11:01:12.647 UTC. The band was
  connected before scheduling the notification. This confirms the iOS callback
  and device exchanges; it does not measure exact motor onset or establish
  other-app/background notification forwarding. Two earlier attempts stopped
  on background before any vibration; explicit keep-awake fixed the test run.

Raw traces, snapshots, transaction journals and device identifiers remain
private. Metadata reports are the evidence; launching a process alone is not
treated as successful sync or feature validation.

## Remaining acceptance

1. Re-sign if provisioning has expired; install over the existing app to retain
   its Keychain and protected library. Do not delete or unpair the band.
2. With Google Health closed, refresh once. Check reconnect/authentication,
   alarm list, optional capabilities/haptic value, battery, activity and clean disconnect.
   If handshake stalls, use the metadata report before asking for another cycle.
3. Alarm CRUD and recurrence read-back passed above. Scheduled ringing, actual
   recurrence over a day boundary, and smart-wake behavior remain untested.
4. Foreground incoming-call delivery passed with one group; the preconnected
   local-notification test passed with three groups and verified restoration.
   Locked/background support is not implemented.
5. Grant chosen Health permissions; verify source labels and a few known daily
   values. Log a workout and check timer recovery, effort/load and local storage.
6. Grant notifications if desired. Use a deliberately chosen step goal/rule to
   test an iPhone alert after refresh; confirm another refresh does not duplicate
   it. Band milestone delivery and deduplication already passed above.
7. Reopen Google Health once for final coexistence, sync and original-alarm check.

Other apps' notification forwarding, locked/background calls, LEDs and gesture
events remain unresolved. Intensity-feedback groups are implemented; arbitrary
motor waveforms are not. No unverified LED or gesture command is exposed.

## USB controls

The signed development app accepts explicit `devicectl` launch arguments.
Normal launch never starts Bluetooth automatically. The phone must be unlocked;
app control cannot bypass its passcode.

- `--diagnostic-refresh`: bounded read of alarms, capabilities, intensity, battery and activity.
- `--diagnostic events`: two-minute observation of incoming event names after the
  normal reads. No phone actions or settings changes. Wrist/tap events still need
  physical evidence; absence alone does not prove lack of support.
- `--diagnostic vibration [1..3]`: read, run feedback groups, restore and verify.
- `--diagnostic create-disabled-alarm`: create the fixed temporary 12:34 alarm;
  firmware activation is corrected and verified.
- `--diagnostic edit-test-alarm ID` / `delete-test-alarm ID`: use an explicitly
  identified temporary alarm and the normal fresh-state conflict checks. Never
  infer the ID; compare the saved before/after lists first.
- `--diagnostic-step-goal`: separate acceptance library, real reading, temporary
  one-step goal, persistent deduplication receipt.
- `--diagnostic-call`: separate call acceptance library; keep the app visible
  for up to one hour while a real call is supplied externally.
- `--diagnostic-notification`: separate test library; request notification
  permission, connect and inspect haptic support/current setting, then schedule
  a local notification two seconds later. The matching foreground delivery
  callback requests three groups; the test stops on background or after 60
  seconds. Metadata is in `Documents/notification-test-report.json`.
- `--diagnostic-ancs`: read/authenticate normally, then reconnect only the same
  authenticated peripheral with Apple's `CBConnectPeripheralOptionRequiresANCS`.
  The second phase sends no application GATT writes or DTLS messages and ends
  after 35 seconds. Once iOS reports sharing authorization, schedule a local
  banner/list/sound notification whose callback explicitly bypasses app-controlled
  vibration. This diagnostic uses a separate library; permission is not proof
  that the accessory subscribes to or acts on notifications.

The one-hour call build was installed and launched on 2026-10-15 at 10:44 UTC;
authenticated refresh completed. The owner subsequently confirmed the call and
switched further testing to app-generated notifications. Battery integration and
stricter event observation were developed without disturbing the call window. Battery
parsing matches an existing authenticated capture. The subsequent ANCS probe's
baseline refresh also persisted a valid battery percentage and read timestamp
from the physical Air, verifying the new read/storage path; the UI was separately
checked with simulator preview data.

Read the protected metadata report at `Documents/connection-report.json` using
`devicectl device copy from` with the app data-container domain. A successful
launch is not acceptance. Capture mode also stores encrypted GATT fragments;
keep that file, snapshots and all identifiers out of Git. Relaunch normally to
return to the owner's normal library and stop the acceptance mode.

## System notification sharing — 2026-10-15

The first bounded probe requested ANCS through Apple's CoreBluetooth connection
option. iOS changed `ancsAuthorized` to true at 11:09:30 UTC; the local system-only
notification reached the app at 11:09:32 UTC. The owner reported **no vibration**.
The second probe retained authorization, delivered its notification at 11:13:17
UTC, and sent/received zero app transport fragments during the sharing phase.
It ended at 11:13:49 UTC. The initial diagnostic called this "Connection timed
out"; the status is now "System sharing check ended" because the connection had
succeeded and the observation duration had elapsed.

A private PacketLogger trace covered the baseline and most of the second probe,
until its USB logger connection was lost at 13:13:37 local time. Its 50 Air ATT
packets consist of the normal client discovery, CCCD write and encrypted app
transport traffic; no Air-to-phone ATT discovery/subscription requests or
phone-to-Air ANCS notification was observed. The CLI text conversion rendered
times two hours later than PacketLogger's UI; app metadata uses UTC. No exact
cross-tool latency is inferred. This bounded negative observation does not prove
that every firmware configuration lacks ANCS, but it provides no working direct
forwarding route. The trace contains private Bluetooth data and is not published.

The existing app-controlled notification test remains separate: it establishes
its encrypted connection before the notification and explicitly requests haptic
feedback groups on the matching foreground callback. It cannot intercept other
apps' notifications or establish locked/background delivery.

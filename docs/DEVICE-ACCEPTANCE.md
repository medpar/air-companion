# Device acceptance

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

Raw traces, snapshots, transaction journals and device identifiers remain
private. Metadata reports are the evidence; launching a process alone is not
treated as successful sync or feature validation.

## Remaining acceptance

1. Re-sign if provisioning has expired; install over the existing app to retain
   its Keychain and protected library. Do not delete or unpair the band.
2. With Google Health closed, refresh once. Check reconnect/authentication,
   alarm list, optional capabilities/haptic value, activity and clean disconnect.
   If handshake stalls, use the metadata report before asking for another cycle.
3. Alarm CRUD and recurrence read-back passed above. Scheduled ringing, actual
   recurrence over a day boundary, and smart-wake behavior remain untested.
4. Run a real incoming-call check with the app open and a saved call rule.
   This cannot establish locked/background support, which is not implemented.
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

- `--diagnostic-refresh`: bounded read of alarms, capabilities, intensity and activity.
- `--diagnostic vibration [1..3]`: read, run feedback groups, restore and verify.
- `--diagnostic create-disabled-alarm`: create the fixed temporary 12:34 alarm;
  firmware activation is corrected and verified.
- `--diagnostic edit-test-alarm ID` / `delete-test-alarm ID`: use an explicitly
  identified temporary alarm and the normal fresh-state conflict checks. Never
  infer the ID; compare the saved before/after lists first.
- `--diagnostic-step-goal`: separate acceptance library, real reading, temporary
  one-step goal, persistent deduplication receipt.
- `--diagnostic-call`: separate call acceptance library; keep the app visible
  for up to five minutes while a real call is supplied externally.

Read the protected metadata report at `Documents/connection-report.json` using
`devicectl device copy from` with the app data-container domain. A successful
launch is not acceptance. Capture mode also stores encrypted GATT fragments;
keep that file, snapshots and all identifiers out of Git. Relaunch normally to
return to the owner's normal library and stop the acceptance mode.

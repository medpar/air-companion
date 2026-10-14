# Later device acceptance

Phone installation and physical testing are explicitly deferred by the owner.
This is one grouped acceptance pass, not repeated checks after every UI edit.

1. Re-sign if provisioning has expired; install over the existing app to retain
   its Keychain and protected library. Do not delete or unpair the band.
2. With Google Health closed, refresh once. Check reconnect/authentication,
   alarm list, optional capabilities/haptic value, activity and clean disconnect.
   If handshake stalls, use the metadata report before asking for another cycle.
3. Record existing alarm values. Create one temporary alarm, edit its time and
   recurrence, toggle it, and remove it. Confirm read-back each time and confirm
   unrelated alarms are intact. Test ringing/dismissal only with the owner.
4. Only if advertised, change intensity once and restore its original value.
   Do not attempt custom light or vibration commands from saved rule drafts.
5. Grant chosen Health permissions; verify source labels and a few known daily
   values. Log a workout and check timer recovery, effort/load and local storage.
6. Grant notifications if desired. Use a deliberately chosen step goal/rule to
   test an iPhone alert after refresh; confirm another refresh does not duplicate
   it. This does not validate band vibration.
7. Reopen Google Health once for final coexistence, sync and original-alarm check.

Notification forwarding, band patterns, LEDs and gesture events require separate
protocol evidence before an implementation can be activated. They are not
included in the successful offline checks or represented as working features.

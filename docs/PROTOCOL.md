# Application protocol boundary

The Air is the DTLS client; the iPhone is the server. Golden Gate provides
Gattlink → NIP IPv4/UDP → DTLS → CoAP. The selected suite is PSK AES-128-CCM
(0xC0A4); the mobile-data identity selects a raw 16-byte device key by ID.
Live offline decryption verified both Finished messages and 131 application
records. A custom read later succeeded on the real band.

## Exposed operations

| Route | Method | Purpose |
| --- | --- | --- |
| `/alarms` | GET | Read capabilities and alarm list |
| `/alarms` | POST | Create one alarm configuration |
| `/alarms/{decimal ID}` | PUT | Replace one alarm configuration |
| `/alarms/{decimal ID}` | DELETE | Delete one alarm |
| `/settings/capabilities` | GET | Discover advertised normal settings |
| `/settings` | PUT | **Query** haptic setting; this protocol uses PUT for a read |
| `/settings` | POST | Change only an advertised haptic intensity |
| `/liveactivity` | GET | Read current activity snapshot |

Alarm/configuration/route definitions were recovered from static app analysis;
live repeated GET responses validate the alarm decoder. Write routes are tested
against synthetic peers, **not yet the physical Air**. Settings PUT-query and
POST-mutation semantics were checked in the original bytecode fallback as well
as the generated schema. No proprietary source is included here.

Alarm edits preserve unknown configuration fields and the separate repeating/
snooze flag. Weekday bits run Monday=0 through Sunday=6. New alarms initialize
the known fields only. Recurrence and smart-wake behavior of created alarms
still need device acceptance. Read-back compares decoded fields conservatively;
a band that canonicalizes omitted defaults differently can produce “needs
checking” even when an edit applied. That is safer than claiming success.

Haptic controls require a fresh capability response advertising setting 1 and
the requested intensity, a successful current-setting query, an unchanged prior
value, protected backup and verified read-back. Only the haptic submessage is
sent; unknown fields inside it are preserved. This is intensity configuration,
not an arbitrary “vibrate now” command or per-event pattern control.

## Remaining interoperability questions

- A later refresh stalled during the handshake. No usable ATT trace was captured
  for that attempt. Its root cause remains unknown. The current app prevents a
  new session while its previous Bluetooth disconnect is pending, pumps timers
  in common run-loop modes, and records bounded progress. These are robustness
  improvements, not proof that the physical failure is resolved.
- ANCS authorization can be inspected, but false does not prove unsupported band
  firmware. ANCS is consumed by an accessory, not by a normal iPhone app.
- Apple's newer accessory-notification route requires system support, extensions
  and accessory-side encrypted transport; the tested phone was on iOS 26.3, below
  the SDK's iOS 26.5 API availability. There is no evidence this Air supports it.
- General Fitbit Switchboard notification records exist, but no Air-specific
  capability/transport has been verified. They are not guessed CoAP writes.
- No exported double-tap event or arbitrary LED color command is established.
  Documented white/red status lights do not establish app-controlled RGB.

[ANCS specification](https://developer.apple.com/library/archive/documentation/CoreBluetooth/Reference/AppleNotificationCenterServiceSpecification/Specification/Specification.html)
· [New accessory notification transport](https://developer.apple.com/documentation/AccessoryTransportExtension/receiving-ios-notifications-on-an-accessory)
· [Fitbit Air guide](https://support.google.com/googlehealth/answer/17033101?hl=en-IE)

No pairing changes, firmware updates, sync acknowledgements/deletions or unknown
command probing are part of the app. Device keys and traces are never published.

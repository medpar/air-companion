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
| `/device/info` | GET | Read battery percentage (protobuf field 13) |

Alarm/configuration/route definitions were recovered from static app analysis;
live repeated GET responses validate the alarm decoder. Alarm write routes and
haptic setting changes were verified on the physical Air on 2026-10-15. Settings PUT-query and
POST-mutation semantics were checked in the original bytecode fallback as well
as the generated schema. No proprietary source is included here.

Alarm edits preserve unknown configuration fields and the separate repeating/
snooze flag. Weekday bits run Monday=0 through Sunday=6. New alarms initialize
the known fields only. Recurrence and smart-wake behavior of created alarms
still need device acceptance. Read-back compares decoded fields conservatively;
a band that canonicalizes omitted defaults differently can produce “needs
checking” even when an edit applied. That is safer than claiming success.

This Air creates an alarm enabled even when POST explicitly encodes disabled,
and returned 5.00 despite applying creation. Read-back identifies exactly one
new alarm and checks every other field and existing alarm. Only that observed
activation mismatch allows one PUT to apply the requested off state, followed
by another verification. POST is never repeated automatically. Creation may
briefly enable the new alarm; an interrupted save must be checked.

Haptic controls require a fresh capability response advertising setting 1 and
the requested intensity, a successful current-setting query, an unchanged prior
value, protected backup and verified read-back. Only the haptic submessage is
sent; unknown fields inside it are preserved. This is intensity configuration,
not an arbitrary motor waveform command. Changing Low/High produces feedback:
the owner confirmed vibration. A group changes to the alternate active value,
waits 800 ms, reads, restores only the known temporary state, and reads again.
One to three groups are supported, with 800 ms between groups. A protected
journal survives interruption; later connections recover before other work.
Off is never overridden, and an unexpected configuration is never overwritten.

Vibration-only sessions now skip the unrelated alarm read and begin with fresh
capabilities/current intensity. The local-notification test prepares that
connection before scheduling its alert. On the matching notification delivery,
it re-reads current intensity on the established session before changing it.
Preparation writes no settings. The session remains bounded and closes if the
app backgrounds; if a temporary intensity is already applied, the existing
bounded restoration path takes priority. This improves a foreground test path,
not background delivery or access to other apps' notifications.

The [Android notification bridge](https://github.com/paceaitian/fitbit-air-notification-bridge/tree/6fec57fafc68e03904f49d823248e38b07a54478)
provided the intensity-feedback lead. Its Android notification permissions and
BOOTSTRAP authentication are not used here; this app keeps the owner's recovered
mobile-data keys and iOS-supported interfaces.

## Remaining interoperability questions

- The 2026-10-15 trace authenticated successfully but reordered outgoing
  Gattlink sequence 3 ahead of 2 after a sink backpressure return. The Swift
  bridge now accepts into a bounded 64-packet FIFO and drains in order whenever
  CoreBluetooth permits writes. The next physical refresh completed with no
  sequence discontinuities. Earlier uncaptured failures cannot be diagnosed
  retrospectively from this finding.
- ANCS authorization can be inspected, but false does not prove unsupported band
  firmware. ANCS is consumed by an accessory, not by a normal iPhone app.
- Apple's newer accessory-notification route requires system support, extensions
  and accessory-side encrypted transport; the tested phone was on iOS 26.3, below
  the SDK's iOS 26.5 API availability. There is no evidence this Air supports it.
- General Fitbit Switchboard notification records exist, but no Air-specific
  capability/transport has been verified. They are not guessed CoAP writes.
- No exported double-tap event or arbitrary LED color command is established.
  Documented white/red status lights do not establish app-controlled RGB.
- [CXCallObserver](https://developer.apple.com/documentation/callkit/cxcallobserver)
  supplies incoming-call state while the app runs. The implementation deliberately
  requires foreground execution, skips answered/ended/outgoing calls, and stores
  event IDs to avoid duplicate vibrations. It does not provide a background wake
  mechanism or access to other apps' notification content.

[ANCS specification](https://developer.apple.com/library/archive/documentation/CoreBluetooth/Reference/AppleNotificationCenterServiceSpecification/Specification/Specification.html)
· [New accessory notification transport](https://developer.apple.com/documentation/AccessoryTransportExtension/receiving-ios-notifications-on-an-accessory)
· [Fitbit Air guide](https://support.google.com/googlehealth/answer/17033101?hl=en-IE)

No pairing changes, firmware updates, sync acknowledgements/deletions or unknown
command probing are part of the app. Device keys and traces are never published.

## Bounded event observation

The optional `--diagnostic events` mode registers incoming POST `/events` and
`/eventsSecure` handlers for two minutes. It accepts only these exact paths,
payloads up to 128 bytes, and complete messages without Block1. It decodes at
most 32 event IDs per message and records at most 128 names per session. It keeps
the previous 4.04 response; it does not acknowledge sync, establish a subscription,
or execute phone actions. Ordinary refresh and call mode do not install these
handlers. A negative observation therefore cannot establish that an event is
unsupported: firmware may require registration or a different acknowledgement.

The shared EventSet schema uses repeated field 1 (packed or unpacked). Known IDs
are `rset`, `bsnc`, `cgps`, `ping`, `aofl`, `wrs+` and `wrs-`. The original app's
EventConsumer maps the last two to true/false wrist status. The Air's existing
authenticated trace contains `rset` on both routes, not a wrist or tap event.
The general TapGestureOption capability model only carries a name/display name;
it is not evidence of a live exported Air gesture.

## Device information

The official app's authenticated capture includes four successful GET
`/device/info` responses. Battery percentage is optional uint32 field 13 in
DeviceInfo.Info. The Swift decoder was checked against a captured response as
well as missing, zero, out-of-range, duplicate and wrong-wire-type fixtures.
Only battery percentage and its read time are persisted, not the response's
Bluetooth address or other identifiers. A failed read retains the old timestamp;
an absent field stays unavailable rather than becoming a false zero.

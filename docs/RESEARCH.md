# Research evidence and acceptance plan

Chronological research log; older entries describe the evidence available then.
For the current implementation and physical results, see the
[2026-10-15 acceptance record](DEVICE-ACCEPTANCE.md) and [README](../README.md).

## Evidence levels

1. **Live verified**: measured on the connected phone/band in this investigation.
2. **Primary reference**: vendor source/documentation, not proof of this firmware's behavior.
3. **Recovered static output**: earlier analysis transcript, with original artifact unavailable.
4. **Unverified**: hypothesis awaiting evidence.

## Live environment

The connected physical device is an iPhone 12 on iOS 26.3, Developer Mode enabled. Google Health is `com.fitbit.FitbitMobile`, version 5.09, build 50924075. iPhone 17 simulator entries are not the physical test target. User selected free Apple ID signing and confirmed the iOS Bluetooth logging profile is installed. Xcode shows an active Personal Team; no valid signing identity was found by the initial CLI check. A certificate/provisioning check remains part of installation.

The first macOS discovery scan completed without connecting or writing, finding zero candidate advertisements. This result does not establish that the band is absent, unsupported, or unavailable from the already paired phone.

## Primary references

- [Google Air getting started](https://support.google.com/googlehealth/answer/17033101?hl=en-IE): alarms, double-tap dismissal, red/white status indications.
- [Google alarm management](https://support.google.com/googlehealth/answer/14226604?hl=en): Air alarm management in Google Health.
- [Google heart-rate sharing](https://support.google.com/googlehealth/answer/14236705?hl=en-AO): Air supports sharing to compatible Bluetooth Heart Rate Profile equipment/apps. This is a possible read path; it does not expose alarm control.
- [Golden Gate source](https://github.com/Google-Health-API/golden-gate/tree/b8a6f2552e12aaf92c1549dc88a41c9b7e73f1aa), Apache-2.0. Checked out locally under `.private/references/golden-gate` and inventoried using REA 6.4.0.
- [Golden Gate security](https://github.com/Google-Health-API/golden-gate/blob/b8a6f2552e12aaf92c1549dc88a41c9b7e73f1aa/docs/src/architecture/security.md): phone/hub is DTLS server, node is DTLS client; PSK key management is deployment-specific. The reference source is not the Air firmware.
- [Golden Gate Bluetooth configuration](https://github.com/Google-Health-API/golden-gate/blob/b8a6f2552e12aaf92c1549dc88a41c9b7e73f1aa/platform/apple/apps/host/Source/BluetoothConfiguration%2BDefaults.swift): FD62 service; ABBAFF01/02 RX/TX; legacy ABBAFF00; ABBAFD00 status; ABBAFC00 configuration. All long UUIDs use suffix E56A-484C-B832-8B17CF6CBFE8.
- [REA](https://github.com/morluto/rea): analysis tooling; a source inventory alone does not reverse engineer a device.
- [Apple Bluetooth tools](https://developer.apple.com/bluetooth/): PacketLogger for Bluetooth observation.
- [Apple Personal Team limits](https://developer.apple.com/help/account/basics/about-your-developer-account): free provisioning expires after seven days; reinstall/reprovision required.

## Recovered Android analysis

55 unique tool-output records were recovered from the prior local Claude session into `.private/recovered/`. Each record contains source session/tool IDs and a SHA-256 of the recovered output. They concern Google Health Android 5.10, whereas the phone runs iOS 5.09. The original APK and complete decompiled classes are no longer at their former paths. These outputs are leads, not freshly reproduced decompilation or live firmware evidence.

Important correction to the earlier notes: the captured `providePathForProtocol` implementation uses `/md/<hex protocol>` with NFC exceptions, not a universal literal `mobiledata` path. Another recovered output shows Android key material being cached in a KeyStore-backed file; the earlier blanket assertion that keys are never stored locally was too strong. Neither finding demonstrates an accessible key cache on this iPhone.

| Operation | Recovered evidence | Remaining gap |
| --- | --- | --- |
| Read alarms | `aedy.invokeSuspend`: GET `/alarms`, protobuf `Alarms.DeviceAlarms` | Original schema field numbers, transport/auth, Air firmware response |
| Add alarm | `aedw`: POST `/alarms`, Configuration encoded by `zni.K` | Air response/ID assignment, prior-state restore |
| Update alarm | `aeeb`: PUT `/alarms/{id}`, same Configuration encoder | Air behavior, prior-state restore |
| Delete alarm | `aedx`: DELETE `/alarms/{id}`, empty body | Air behavior; no deletion authorized as an experiment yet |
| Alarm capabilities | Reader extracts maximum alarms, smart wake, dismissal method, snooze duration | Device's actual returned values |
| Alarm settings | Reader extracts ID, hour/minute/second, enabled, recurring, weekday byte, smart wake, repeats | Wire schema, one-shot and timezone/DST semantics |
| Device info | GET `device/info` | Actual response and model/firmware identification |
| Settings capabilities | GET `/settings/capabilities` | Air-specific supported settings/intensities/goals |
| Read settings | PUT `/settings` with `SettingsRequest` (requested type list) | Verify device-specific behavior before using |
| Change settings | POST `/settings` with `SettingsResponse` (setting values) | Air capability and prior-state restore; no write attempted |
| DTLS key identity | `MD-` + 8 hex key-ID digits + `-` + 8 hex expiry digits | Actual handshake, key resolution, expiry behavior |
| Key lookup | Account API relative path `user/-/devices/device/{id}/keys`; primary/secondary key objects | Exact live service/auth and iOS behavior; no account keys obtained |

App-wide notification/haptic class names do not prove that Air firmware implements them. Other models share the same app. No arbitrary RGB LED control or general tap-event stream has been demonstrated.

## Requested feature acceptance

| Feature | Evidence needed before enabling |
| --- | --- |
| Set/modify alarms | Authenticate, read capabilities and existing alarms, decode exact schema, set a user-approved test alarm, observe vibration/dismissal, restore and read back |
| Incoming-call vibration | Air-supported haptic path plus supported iOS delivery mechanism and locked/background real-call test; distinguish ANCS accessory support from app access |
| Event vibration/LED colors | Device capability plus understood command and permitted intensity/duration/color values; do not repurpose optical measurement LEDs |
| Daily-step milestone | Reliable Air step source, date/timezone rollover, once-per-threshold behavior, verified haptic path |
| Double-tap phone actions | Demonstrated exported event, debounce and background delivery, specific iOS action allowed by the OS |
| Fitness analytics | Verified input source/resolution/units, research references, missing-data/quality behavior, validation fixtures; no unsupported clinical claims |
| Minimal iPhone interface | Real data or explicit unavailable states, accessibility/Dynamic Type, render review on actual phone, battery/background measurements |
| Install and publish | Physical-device acceptance, normal Google Health sync restored, secrets/proprietary artifacts excluded, then new GitHub repository |

## Initial safe experiment (completed)

Captured a short iPhone Bluetooth trace while the user opened the existing alarm list in Google Health. No settings changes. Results appear below. Captures stay local and private. Capture success means usable packets, not merely a running process or nonempty file.

A later authenticated read session requires an explicit coexistence plan. Do not infer that two apps can or cannot share this peripheral merely from general BLE topology. Do not disable Google Health Bluetooth permission, add a new bond, restart the band, or install interception certificates without discussing the concrete next experiment with the user.

## First live trace result

The bounded 90-second capture produced 80,714 bytes. PacketLogger identified an existing connection named Google Fitbit Air. The trace contained 172 outgoing writes to attribute `0x0042` and 182 notifications from `0x0044`. These are capture-specific handles, not portable constants or proof of service UUIDs. No service-discovery UUID mapping or new DTLS handshake was captured.

Using the reference Gattlink framing, the offline decoder reconstructed 93 phone-to-band and 92 band-to-phone IPv4/UDP datagrams. All 185 contained DTLS 1.2 application-data records (content type 23, epoch 1), with both UDP ports 5684. No sequence discontinuities or trailing partial frames remained in those selected streams. An additional ATT response was outside this transport decoder's accepted frame shape. No CoAP messages were decrypted, and the alarm page action cannot yet be tied to an individual encrypted message.

`scripts/summarize_trace.py` processes saved PacketLogger text only; it has no networking or device access. Six synthetic tests cover fragmentation, piggybacked ACKs, sequence wrap, duplicate fragments, missing data, reset, checksum/truncation rejection, and exclusion of payload content from the summary. It intentionally supports only uncompressed IPv4 and conservatively discards partial data after sequence discontinuities. Passing tests establish decoder behavior, not device-feature support.

The user authorized a temporary local HTTPS proxy/certificate experiment to observe a possible device-key response. The proxy uses an isolated CA named `Air Research Temporary 2026-10-13`. Its initial interception scope was `api.fitbit.com`; the updated observed-host scope is documented below. It persists only validated device-key fields from the expected response route, plus restricted connection/request metadata. It does not save authorization headers, cookies, arbitrary bodies, or request dumps. Other HTTPS hosts tunnel without interception. No keys have been obtained. Remove the iPhone proxy and temporary certificate and stop the local listener after this experiment.

## Reproduced alarm schema inspection

The Android bundle was reacquired on October 13. SHA-256 `cab6207662b870bd3c110afe9b51136edbe2fff65ed794be685956647d312a47` matches the hash in the recovered original download record. The base APK hash is `ff5ccea47e30aac0675e3a62a0a9d7f27ca3a2c350ef2a9953d2a0bc83c3e92a`. Hash equality establishes continuity with the previous artifact; independent APK signer verification remains pending. No Android package was installed or executed.

JADX 1.5.6 inspected only `Alarms` and `zni`, one worker and a 1536 MiB Java heap limit. It produced the selected output but reported errors while processing the application; this is not a claim of error-free full decompilation. The visible field constants and the small alarm encoder provide the following wire-schema evidence, still untested against the Air:

| Message | Fields (number: meaning) |
| --- | --- |
| DeviceAlarms | 1: capabilities message; 2: repeated AlarmEntry |
| AlarmEntry | 1: integer ID; 2: Configuration message |
| Configuration | 1: enabled boolean; 2: repeats boolean; 3: smart-wake boolean; 4: recurring boolean; 5: AlarmTime message; 6: weekday bytes |
| AlarmTime | 1: hour; 2: minute; 3: second |
| Capabilities | 1: maximum alarms; 2: supports smart wake; 3: dismissal enum; 4: snooze minutes |

Dismissal enum values are 0 unspecified, 1 double tap, 2 button, 3 touchscreen. The encoder `zni.K` serializes a **Configuration** directly, not a complete DeviceAlarms list. It sets all four booleans and a one-byte weekday mask using `1 << DayOfWeek.ordinal()` for each selected day. Reproduced call-site evidence passes that result to POST `/alarms` for creation and PUT `/alarms/{id}` for modification. DELETE `/alarms/{id}` uses an empty body. The separate meanings of repeats and recurring, timezone behavior, and verified write/restore semantics remain unresolved. Do not issue writes from this partial schema.

### Settings query versus mutation

The earlier recovered-output interpretation of PUT `/settings` as a settings mutation was incorrect. The full `xqu.b` call serializes `DirectSettings.SettingsRequest`, containing repeated requested `SettingType` enum values in field 1, and parses a `SettingsResponse`. The write method `xqu.e` serializes `SettingsResponse` (repeated Setting messages in field 1) and uses **POST** `/settings`. The normal decompilation omitted part of this method; fallback instruction output from the APK's `classes6.dex` shows the POST explicitly. Thus the HTTP/CoAP method name alone must not determine safety classification.

`SettingsCapabilities` fields 1/2/3 are supported setting types, supported haptics intensities, and supported goal types. These are repeated enum lists. Haptics values are 0 unspecified, 1 off, 2 low, 3 high. Goal values are 0 unknown, 1 steps, 2 distance, 3 calories, 4 active-zone minutes. A Setting holds a oneof: field 1 haptics, 2 goal, 3 display, 4 GPS, 5 tracker orientation, or 6 magnification. HapticsSetting field 1 is intensity. MainGoalSetting fields 1/2 are enabled and goal type. This demonstrates a capability-driven settings protocol shared by app-supported devices; it does not prove Air supports every entry or any arbitrary vibration pattern, LED color, or tap-event stream.

## Temporary certificate download troubleshooting

The phone's initial `mitm.it` page returned 404. An exact HTTP route `/air-research.cer` on the local proxy now serves only the public CA certificate. The user subsequently confirmed installation via `http://mitm.it/cert/pem`, full trust enabled, and successful loading of the alarm list both before and after closing/reopening Google Health. A regression test verifies that other paths, hosts, ports, schemes, and methods cannot access certificate files through the direct route, including the private CA file.

Reproduced `biur.f` / `shz.a` code shows the Android key URL builder appends `.json` to the `keys` resource. `ServerConfiguration.getApiUri()` appends `/1` to the configured CDN base; the Android production constants use `https://android-cdn-api.fitbit.com` (direct base `https://android-api.fitbit.com`). Do not assume iOS uses the same host or `api.fitbit.com`. The proxy records only Fitbit/Health-related CONNECT hostnames so its interception scope can be corrected from actual iPhone traffic before relying on an absent key response.

The capture path filter now accepts the exact `.json` suffix as well as the extensionless resource; it still excludes unrelated paths, headers, and bodies. This correction has a dedicated test. The iOS app's actual key-fetch host/path and caching behavior remain unobserved. Opening an alarm page may use cached credentials and need not cause any key fetch, even with a correctly configured proxy.

### Live proxy and second trace update

The phone produced CONNECT events for `fitbit-pa.googleapis.com` and `fitbitvestibuleshim-pa.googleapis.com`. After the user's full-trust confirmation, the proxy's exact-host interception scope became those two hosts plus `api.fitbit.com`. Other observed website/account hosts remain pass-through. The addon records only validated RPC service/method identifiers, response status and coarse content type; it streams unrelated request/response bodies instead of buffering them. On client TLS failure it removes that host from interception so later connections can use normal end-to-end TLS. Sixteen synthetic tests cover the decoder and capture safeguards.

Two local Mac requests to the Google Fitbit host's `/robots.txt` returned HTTP 401 through the proxy. They are **self-tests**, not iPhone requests or an account-authentication failure. The second produced TLS-established, request-header and response-header events, confirming those hooks work. The subsequent dashboard refresh finished normally according to the user. No device-key response was obtained; protocol findings and cleanup are recorded below.

A separate 180-second Bluetooth window produced 98,322 bytes and decoded 123 phone-to-band plus 124 band-to-phone datagrams, all DTLS 1.2 application records, with no sequence gaps or trailing bytes in the selected streams. No handshake was identified in that window. The user's reopening confirmation does not provide an exact timestamp relative to the capture, so absence of a handshake in the window does not prove reopening cannot create one. The original band connection and paired state were not manipulated.

## Proxy protocol diagnosis and completed cleanup

The final refresh reached `web-api.fitbit.com` and produced seven HTTP 200 responses, none matching the device-key route. The two Google Fitbit gRPC hosts completed TLS but produced HTTP parsing errors. Inspection of connection metadata identified ALPN `grpc-exp` on both sides of those gRPC connections, whereas the web API negotiated `h2`. This is evidence of a proxy protocol-handling defect, not evidence of certificate pinning or invalid account credentials.

An isolated copy of mitmproxy 12.2.3 was changed to treat `grpc-exp` as HTTP/2 at its seven ALPN dispatch comparisons. A bounded localhost-only test offered `grpc-exp` and `h2` and sent an unauthenticated `/robots.txt` request to `fitbit-pa.googleapis.com`. Before the change, the connection ended without an HTTP/2 response. Afterward, it negotiated `grpc-exp` and received HTTP 401, expected for that unauthenticated request. This verifies the protocol fix only, not device-key retrieval. The approach matches the [NCC Group gRPC proxy note](https://github.com/nccgroup/blackboxprotobuf/blob/master/mitmproxy/README.md#grpc). No external decoding addon was installed.

Original module SHA-256: `0e7b3474f7febddcf81cb69685f3cd9a3b7af9c849ae47925add565e9ed67d4c`. Patched module: `976c3c5f49f6eb8e3f0ef9a2ccb47537296934e9efb9ff0844d0c73327ba78c9`. Test evidence remains local in `.private/alpn-selftest.json`; the shared mitmproxy installation was not modified.

The user confirmed: proxy off, temporary certificate removed, its trust entry gone, normal Google Health sync, and existing alarms present. The old Mac proxy was stopped and its two CA private-key files removed. Its port 8080 listener was verified closed. The separate localhost test proxy also stopped. No device keys were recovered, no research commands were sent to the band, and no band settings or pairing were changed. A corrected follow-up capture would require a fresh temporary certificate and phone setup; cleanup must not be silently undone.

## Corrected gRPC capture preparation

Scoped inspection of Android `brkz`, `brlc`, `brld`, `bccx`, and `bcbr` established the shared legacy-HTTP wrapper. Its RPC is `fitbit.platform.vestibuleshim.proto.GaiaToFitbitAuthProxyService/HTTPRequest`. The Android production host configuration maps the service to `fitbitvestibuleshim-pa.googleapis.com`, also observed from the iPhone. Request protobuf fields are 1 method string, 2 full URL string, 3 repeated headers, 4 body bytes, 9 auxiliary account string and 10 auxiliary boolean. Response fields are 1 HTTP status, 2 repeated headers and 3 body bytes. The caller supplies gzip compression. This is reproduced Android schema evidence; iOS wire compatibility still requires observation.

The capture addon now observes a bounded copy (at most 64 KiB) of this exact unary RPC request, including gzip decoding with an expansion limit. It forwards all bytes unchanged, retains only a key-route boolean, and observes the response only for a GET to an exact allowed Fitbit host and the known device-key path. It rejects malformed, truncated, oversized and ambiguous envelopes. It persists only the previously validated JSON key fields; inner URLs, account strings, authorization headers and unrelated response bodies are not saved. Twenty synthetic tests pass, including fragmented gzip and uncompressed envelopes, byte-for-byte forwarding, oversize rejection and exclusion of private fields.

A fresh isolated CA named `Air Research Temporary B 2026-10-13` and corrected proxy were prepared. The direct public-certificate endpoint returned HTTP 200 and the expected certificate subject; it contains no private key. The user has been asked to install/trust this new certificate temporarily, reopen Google Health, refresh once and open existing alarms. That phone action and live key retrieval remain pending. The prior certificate and proxy experiment remain cleaned up; the fresh experiment has a separate local directory and requires its own cleanup afterward.

## Corrected live capture and bounded cloud-read probe

The user confirmed normal sync and alarms with the second certificate installed. The corrected proxy observed 79 outer requests/responses, including 67 successfully decoded `GaiaToFitbitAuthProxyService/HTTPRequest` request envelopes. No envelope parse error, TLS failure, or proxy runtime error was recorded. None matched the allowed device-key endpoint and no keys were saved. HTTP 200 on an outer gRPC response does not establish the inner HTTP status. This confirms iOS request-envelope compatibility, while key-response compatibility remains unverified.

The observer was extended with an explicitly armed, single-use read probe. It reuses credentials only in memory from a fresh request to the same observed Google gRPC host. It constructs at most two additional wrapped GETs: `/1/user/-/devices.json`, then `/1/user/-/devices/device/{id}/keys.json` only if exactly one TRACKER in the returned list identifies itself as Air, Fitbit Air, or Google Fitbit Air. The first route and response fields are documented in the [official Get Devices reference](https://dev.fitbit.com/build/reference/web-api/devices/get-devices/); the second comes from the reproduced Android key-fetch call. No write routes, retries, account changes, pairing actions, or band commands are implemented. Original app requests are forwarded unchanged.

The trigger expires after ten minutes and is consumed before the first request is queued. Unsupported hosts, response schemas, ambiguous devices, and unsuccessful statuses stop the probe. Credentials, device identifiers, and unrelated bodies are not persisted. Tests cover original-request preservation, exact endpoint restrictions, single use and expiry, and refusing ambiguous devices. All 23 tests pass. The probe is armed awaiting one user refresh; actual cloud reads and key retrieval remain pending.

The public Fitbit Web API documentation currently announces shutdown on October 30, 2026. That announcement does not by itself establish the lifetime of the official app's private gRPC shim or internal key service. Do not build a durable companion-app authentication promise around this temporary research route.

The requested dashboard refresh reached `google.internal.fitbit.api.timeseries.v4.TimeSeriesServiceV4` on the newer health API. It produced no legacy HTTP-wrapper request, so the armed cloud-read probe did not run. A single close/reopen was requested because the earlier cold start produced the required wrapper traffic. This distinguishes absence of an eligible trigger from a failed key lookup.

The close/reopen exposed `iphone-cdn-api.fitbit.com` as the inner HTTP URL host. It was absent from the initial allowed-host list, which had been based on Android constants and already observed direct hosts. No device-key path was present in those requests, and the active probe correctly remained unconsumed. This exact observed iPhone host was added to the allowlist, all 23 tests passed again, and one further reopen was requested to trigger the pending probe.

## End of the second proxy attempt

After the iPhone host correction, the next requested restart did not yield another eligible HTTP-wrapper request before the single-use window expired. **No cloud-read request was queued or sent.** This is not an HTTP rejection of the device-key endpoint and does not establish that the endpoint is unavailable. No device keys were saved. Later traffic included direct CONNECT attempts to `iphone-cdn-api.fitbit.com`, which was outside the outer TLS interception scope; no claim is made about its encrypted paths or bodies.

The expired probe marker was removed and the proxy was switched to pass-through (`allow_hosts` matches nothing). The user was asked to disable the iPhone proxy, remove the second temporary profile/trust entry, and verify normal sync/alarms. That cleanup confirmation is pending; the Mac listener remains available until the phone proxy is off to avoid breaking its network access. The patched runtime hash remains the verified value, and observed Google gRPC connections still negotiated `grpc-exp`. The lack of later eligible requests has not been fully explained; do not disguise repeated app restarts as a proven key-retrieval path.

The user subsequently confirmed that the second iPhone proxy and temporary profile/trust entry were removed and that sync and existing alarms are normal. The second Mac proxy was then stopped, port 8080 was verified closed, and both CA private-key files were deleted. Both proxy experiments are now cleaned up. No cloud-read probe was sent, no device keys were recovered, and no research command was sent to the band.

## Second proxy defect reproduced entirely on the Mac

No Android phone is available. Further inspection found that mitmproxy's independent next-layer protocol classifier did not include `grpc-exp` in `HTTP_ALPNS`. The earlier HTTP/2 dispatch patch alone was insufficient: the classifier chose `HttpLayer` when the client preface arrived first, but `TCPLayer` when server SETTINGS arrived first or both sides had data. Raw forwarding bypassed all HTTP capture hooks without necessarily disrupting the app. This is a demonstrated local failure mode consistent with the intermittent capture, not a packet-level proof of each earlier connection's ordering.

An offline three-case test reproduced those selections. Adding `grpc-exp` to the isolated runtime's HTTP ALPN registry made all three select `HttpLayer`. The TLS module's original SHA-256 is `76e315d8e64355a757183d3f4dbace43550ce4092d1907547ed9ddf40c6a2c39`; patched SHA-256 is `e82564ae533e4ff62bb595f33e4fbb19435c139521556f7f22e460c86424d018`. Evidence: `.private/grpc-classification-selftest.json`.

A separate end-to-end fixture then ran a local TLS/HTTP2 server that sends SETTINGS first. DNS inside the test proxy was restricted to loopback; unexpected destinations were rejected. Synthetic account headers and a fake device/key response exercised the actual proxy hooks and client-replay engine. The original request received HTTP 200, exactly one device-list read and one key read occurred, exactly one synthetic key file was produced, unrelated data and credentials were excluded, and the runtime log was empty. Temporary fixture credentials/certificates were deleted automatically and both local processes stopped. Evidence: `.private/proxy-e2e-selftest.json`. This verifies the software path, not actual Google authorization or Air keys.

With both defects fixed, the 23 unit tests passed again. A third isolated certificate, `Air Research Temporary C 2026-10-13`, was prepared and its public download endpoint verified. The exact observed direct iPhone host was included in the outer interception scope as well. A single-use ten-minute read probe is armed, awaiting the user's temporary setup and one reopen. It has not yet established live key retrieval. The third certificate/proxy will require its own cleanup.

## Live device-key retrieval and third cleanup — 2026-10-13

The third corrected proxy successfully ran the bounded cloud read. Both device-list reads returned HTTP 200 and identified exactly one Air. Both corresponding key reads returned HTTP 200. The first key response was rejected by an overly strict local parser; the response body was discarded. Static Android parsing permits decimal-string key IDs and Base64 whitespace/omitted padding, so the parser was corrected to accept these representations while validating signed 64-bit IDs and decoded key lengths. The rejected body's precise representation is unknown. A second explicitly armed two-read sequence succeeded. Total additional cloud requests: four GETs, with no cloud or band mutation.

Both recovered keys are 16 bytes and their IDs fit unsigned 32 bits. Only the two keys/IDs and capture timestamp were saved to an ignored, owner-only file (0600). No values, identifiers or authorization headers are included in this document. These are live device keys, distinct from the earlier synthetic fixture. All 25 unit tests pass. Successful key retrieval does not establish a working custom DTLS session, plaintext decoding, or feature support.

The Mac can relaunch the already installed Google Health app using `devicectl device process launch --terminate-existing`; both launches reported success and triggered the wrapper traffic. This avoids requesting repeated manual app restarts. It does not attach a debugger or inspect app memory.

The user confirmed proxy off, temporary C profile/trust removed, normal sync, and existing alarms intact. The third Mac proxy was stopped, port 8080 was verified closed, and both temporary CA private-key files were removed. All probe triggers are disabled. Recovered device keys remain protected locally.

The next observation needs a fresh DTLS handshake and the negotiated cipher suite. The reference Golden Gate implementation advertises PSK AES-128 CCM/GCM and ECDHE-PSK AES-128 CBC; reference defaults are not proof of Air's negotiated cipher. Prior traces contain only encrypted application records. A normal phone Bluetooth reconnection may provide the handshake without changing pairing or settings, but session resumption and incomplete capture can limit passive decoding. Protocol decoding follows [DTLS 1.2 (RFC 6347)](https://www.rfc-editor.org/rfc/rfc6347) and [TLS 1.2 (RFC 5246)](https://www.rfc-editor.org/rfc/rfc5246).

The offline decoder now accepts DTLS 1.0 record headers used during initial negotiation as well as DTLS 1.2. It counts plaintext handshake fragments and extracts only complete ClientHello/ServerHello version, cipher-suite choices, compression, and extension types. It deliberately excludes randoms, cookies, session IDs and PSK identities, and does not guess fragmented messages. Four additional tests cover initial-version compatibility, selected cipher/extended-master-secret metadata, malformed lengths, and exclusion of encrypted Finished records. All 29 tests pass. The user performed a normal phone Bluetooth off/on cycle and confirmed reconnection, sync, and existing alarms normal; trace availability remains under investigation.

## Live handshake, authenticated offline decryption, and alarm schema validation

The first three-minute handshake capture and a brief buffered retry produced zero bytes. The iPhone remained visible and unlocked to Xcode, but PacketLogger's new iOS window had no device name. After the user reconnected USB and confirmed the Bluetooth logging profile remained installed, a bounded 30-second buffered capture produced 70,331 bytes. Its buffer preserved the earlier Bluetooth reconnection, so no second radio toggle was needed. The new Air transport connection uses ATT 0x0042 outbound and 0x0044 inbound; these handles are capture-specific. All capture processes ended.

The Air's full handshake identifies it as the DTLS client and the phone as server. The Air offered 0xC0A4, 0x00A8, 0xC037 and the renegotiation SCSV. The phone selected **TLS_PSK_WITH_AES_128_CCM (0xC0A4)**, null compression, and extended master secret (extension 23). ClientHello, ServerHello, ServerHelloDone and ClientKeyExchange are present in full. The observed mobile-data key identity selects exactly one of the locally saved keys.

An offline experiment reconstructed the SHA-256 handshake transcript including DTLS headers, derived the PSK premaster/extended master secret and traffic keys, and authenticated every selected encrypted record with AES-CCM. **Both client and server Finished verify_data values match.** The decoded session contains 65 band-to-phone and 66 phone-to-band application records, plus one Finished from each side. No key, identity, random, plaintext health value, or alarm time was printed or added to public files. The decryption scripts remain local experiments, not a general production protocol implementation. Relevant definitions: [PSK premaster (RFC 4279)](https://www.rfc-editor.org/rfc/rfc4279), [AES-CCM (RFC 6655)](https://www.rfc-editor.org/rfc/rfc6655), and [extended master secret (RFC 7627)](https://www.rfc-editor.org/rfc/rfc7627).

All 131 plaintext application records parse as CoAP. Observed official-app requests include GET `/alarms`, `/device/info`, `/liveactivity`, `/aspen/info`, `/app/outbox`, `/exercise/sessions`, and `/sync/dump`; the official app also sends sync-related PUTs. These writes are observations of existing official behavior, not commands issued by research software and not authorization to replay them. The band initiates POSTs to `/events`, `/eventsSecure`, `/aspen/info`, and `/sync/request`; this alone does not establish arbitrary gesture or notification control.

Sixteen alarm responses were correlated by token and message ID to GET `/alarms`; each is a successful 2.05 Content ACK without blockwise options. All sixteen payloads are identical. The previously reproduced protobuf schema decodes capacity **8**, **smart-wake supported**, and **2 existing alarm entries**, each with a structurally valid time. Dismissal method and snooze duration fields are absent, so their defaults are not interpreted as measured capabilities. Alarm times and IDs remain private. This is device-specific schema evidence, but no custom client or alarm mutation has yet been tested.

Fresh bounded decompilation also reproduces `MobileDataTlsKeyId`, its 20-byte `MD-xxxxxxxx-xxxxxxxx` parser, the TLS key resolver, and the provider returning raw key bytes by key ID. No key derivation from the expiration field is present in that resolver path. The cryptographically verified live decryption independently confirms the selected raw key works for this captured session.

## Native read-only preview — 2026-10-14

The new SwiftUI preview embeds Golden Gate's Gattlink/NIP/DTLS stack with Mbed
TLS 3.6.7. A C bridge exposes one application request: GET `/alarms`. It offers
only the observed AES-128-CCM PSK cipher, resolves the observed mobile-data
identity format, and uses `SecRandomCopyBytes`. No reset, provisioning, firmware,
sync-deletion, or settings-write API is exposed. Protocol acknowledgements and
unhandled-resource responses still exist; read-only refers to the application
request, not an absence of Bluetooth writes.

A local test uses two isolated processes because NIP's interface is global.
Synthetic PSK peers complete DTLS and a real CoAP alarm read through 20-byte
Gattlink fragments. The test checks backpressure, rejection of reads before
authentication and overlapping reads, a single active transport, and three
subsequent create/destroy cycles. It passes. The NIP wrapper destructor needed a
small documented cleanup patch; no device firmware is changed.

The bounded Swift protobuf parser passes malformed/overflow/duplicate/wire-type
tests and decodes the private captured response. The existing 29 Python tests
also pass. iPhone and simulator builds succeeded, and the simulator UI was
visually checked. These checks do not establish real-band interoperability.

Signing succeeded with the user's selected free Personal Team. Installation
initially failed because three other free-developer apps occupied the phone's
slots. After the user freed one slot, installation succeeded. Keys were copied
over USB into this app's own private container; first launch is blocked pending
the user's developer-trust check. Keychain import is not yet verified. No custom
Bluetooth connection has been attempted.

The preview never connects at launch. A button starts one foreground attempt,
bounded to 35 seconds; it disconnects after an alarm response, failure or
backgrounding. Its local diagnostic report records only event labels, timestamps,
counts and error codes. Secrets and alarm values are excluded from diagnostics.
Alarm mutation and all other originally requested features remain unfinished.

### First successful custom connection

After developer trust was resolved, the user opened the app and its key warning
disappeared. The import file was no longer present in the app's Documents
directory. The local report records a foreground attempt at 22:06:07 UTC on
October 13, Bluetooth connection and DTLS authentication at 22:06:09, two decoded
alarms at 22:06:13, then a closed connection. Nine fragments were sent and thirteen
received. This is the first verified custom-client authentication and alarm read,
not merely offline decoding or a synthetic test. The user subsequently confirmed
that Google Health sync and both original alarm times/enabled states are normal.
No custom alarm mutation has yet been tested.

## Offline app expansion — 2026-10-14

The owner deferred installation and device testing and requested complete offline
app development. No phone/band connection was made during this phase. The prior
native redesign's refresh/save report was an error: diagnostics reached the
handshake without a completed operation, and the later capture lacked usable ATT
traffic. Its cause is unresolved; the earlier successful read does not establish
reliable reconnection or any physical mutation.

Version 0.2 implements native tabs, alarm create/edit/delete/recurrence with
fresh-state conflict checks, protected transaction journals and read-back; gated
haptic intensity query/change/read-back; timestamped activity cache; read-only
HealthKit import with source/device separation; trends; workouts and persistent
session timer; foreground step-goal iPhone notifications; and capability-gated
automation drafts. Preview examples are isolated from real storage and Bluetooth.

The haptic route and setting messages were verified against bounded static
schema/bytecode output: PUT `/settings` queries SettingsRequest, while POST writes
SettingsResponse. The UI only exposes a setting after actual band capability and
current-value responses. No haptic settings have been queried or changed on the
physical device by this build.

Tests exercise native encrypted synthetic alarm CRUD and haptic settings routes,
Swift conflict/read-back checks, unknown-field preservation, malformed protobuf,
DST and sleep-overlap math, missing-data handling, milestone deduplication,
protected persistence, timer/relaunch recovery and preview isolation. The 29
Python research tests pass. Signed iPhone and simulator builds are produced;
real installation, Health authorization and physical acceptance remain deferred.
See the current README feature table rather than interpreting earlier research
milestones as the status of the finished app.

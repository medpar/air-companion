#ifndef AIR_TRANSPORT_H
#define AIR_TRANSPORT_H
#include <stddef.h>
#include <stdint.h>
/* All functions and callbacks must execute on the creating thread. Callbacks
 * must copy byte buffers before returning and must not destroy the transport.
 * Only the explicitly declared routes are exposed; no arbitrary command API. */
typedef struct AirTransport AirTransport;
typedef int (*AirSend)(void* context, const uint8_t* bytes, size_t length);
typedef void (*AirAlarmResponse)(void* context, int code, const uint8_t* bytes, size_t length);
typedef void (*AirEventObserver)(void* context, const uint8_t* bytes, size_t length);
/* send returns 0 for accepted, 1 for temporary backpressure, -1 for failure. */
AirTransport* air_transport_create(uint16_t mtu, const uint32_t ids[2],
                                  const uint8_t keys[32], AirSend send,
                                  AirAlarmResponse response, void* context);
void air_transport_destroy(AirTransport* transport);
int air_transport_start(AirTransport* transport);
/* Optional observation of inbound event payloads. Keeps the existing 4.04
 * response; does not acknowledge sync, subscribe, or change band settings. */
int air_transport_observe_events(AirTransport* transport, AirEventObserver observer);
int air_transport_receive(AirTransport* transport, const uint8_t* bytes, size_t length);
void air_transport_writable(AirTransport* transport);
/* Pumps nonblocking work and returns next timer delay in milliseconds.
 * UINT32_MAX means no timer is currently required. */
int air_transport_work(AirTransport* transport, uint32_t* next_delay);
/* 0=init, 1=handshake, 2=session, 3=error, negative=inspection failure. */
int air_transport_state(AirTransport* transport);
/* Only GET /alarms, one request at a time, no automatic application retry. */
int air_transport_read_alarms(AirTransport* transport);
/* resource: 0=alarms, 1=settings/capabilities, 2=liveactivity,
 * 3=haptic settings query (protocol PUT), 4=device/info. */
int air_transport_read(AirTransport* transport, unsigned resource);
/* Existing alarm configuration only; caller captures prior state and verifies
 * readback. No automatic retry, reset, provisioning, or firmware operation. */
int air_transport_update_alarm(AirTransport* transport, uint32_t id,
                               const uint8_t* configuration, size_t length);
int air_transport_create_alarm(AirTransport* transport, const uint8_t* configuration, size_t length);
int air_transport_delete_alarm(AirTransport* transport, uint32_t id);
/* POST /settings with a narrowly constructed HapticsSetting; callers must check
 * fresh capability evidence, preserve prior state, and verify the resulting value. */
int air_transport_set_haptics(AirTransport* transport, const uint8_t* settings, size_t length);
#endif

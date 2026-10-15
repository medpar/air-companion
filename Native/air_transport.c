#include "air_transport.h"
#include <stdlib.h>
#include <string.h>
#include <stdatomic.h>
#include <stdio.h>
#include "xp/module/gg_module.h"
#include "xp/common/gg_common.h"
#include "xp/common/gg_io.h"
#include "xp/loop/gg_loop.h"
#include "xp/stack_builder/gg_stack_builder.h"
#include "xp/coap/gg_coap.h"

/* Golden Gate NIP is process-global and supports one active network interface. */
static atomic_flag transport_in_use = ATOMIC_FLAG_INIT;

struct AirTransport {
    GG_IMPLEMENTS(GG_DataSource);
    GG_IMPLEMENTS(GG_DataSink);
    GG_IMPLEMENTS(GG_TlsKeyResolver);
    GG_IMPLEMENTS(GG_CoapResponseListener);
    GG_Loop* loop;
    GG_Stack* stack;
    GG_CoapEndpoint* coap;
    GG_DataSink* incoming;
    GG_DataSource* top_source;
    GG_DataSinkListener* writable;
    GG_CoapRequestHandle request;
    uint32_t ids[2];
    uint8_t keys[32];
    uint16_t mtu;
    int reading;
    AirSend send;
    AirAlarmResponse response;
    void* context;
};

static GG_Result source_sink(GG_DataSource* _self, GG_DataSink* sink) {
    AirTransport* self = GG_SELF(AirTransport, GG_DataSource);
    self->incoming = sink;
    return GG_SUCCESS;
}
static GG_Result send_data(GG_DataSink* _self, GG_Buffer* buffer, const GG_BufferMetadata* metadata) {
    (void)metadata;
    AirTransport* self = GG_SELF(AirTransport, GG_DataSink);
    size_t size = GG_Buffer_GetDataSize(buffer);
    if (size > self->mtu) return GG_ERROR_NOT_ENOUGH_SPACE;
    int result = self->send(self->context, GG_Buffer_GetData(buffer), size);
    return result == 0 ? GG_SUCCESS : result == 1 ? GG_ERROR_WOULD_BLOCK : GG_ERROR_INVALID_STATE;
}
static GG_Result set_listener(GG_DataSink* _self, GG_DataSinkListener* listener) {
    AirTransport* self = GG_SELF(AirTransport, GG_DataSink);
    self->writable = listener;
    return GG_SUCCESS;
}
static int hex_digit(uint8_t byte) {
    if (byte >= '0' && byte <= '9') return byte - '0';
    if (byte >= 'a' && byte <= 'f') return byte - 'a' + 10;
    if (byte >= 'A' && byte <= 'F') return byte - 'A' + 10;
    return -1;
}
static GG_Result resolve_key(GG_TlsKeyResolver* _self, const uint8_t* identity,
                             size_t length, uint8_t* key, size_t* key_size) {
    AirTransport* self = GG_SELF(AirTransport, GG_TlsKeyResolver);
    if (length != 20 || memcmp(identity, "MD-", 3) || identity[11] != '-') return GG_ERROR_NO_SUCH_ITEM;
    uint32_t id = 0;
    for (size_t i = 3; i < 20; ++i) {
        if (i == 11) continue;
        int digit = hex_digit(identity[i]);
        if (digit < 0) return GG_ERROR_NO_SUCH_ITEM;
        if (i < 11) id = (id << 4) | (uint32_t)digit;
    }
    for (size_t i = 0; i < 2; ++i) {
        if (self->ids[i] != id) continue;
        if (*key_size < 16) { *key_size = 16; return GG_ERROR_NOT_ENOUGH_SPACE; }
        memcpy(key, self->keys + i * 16, 16);
        *key_size = 16;
        return GG_SUCCESS;
    }
    return GG_ERROR_NO_SUCH_ITEM;
}
static void on_ack(GG_CoapResponseListener* _self) { (void)_self; }
static void on_error(GG_CoapResponseListener* _self, GG_Result error, const char* message) {
    (void)message;
    AirTransport* self = GG_SELF(AirTransport, GG_CoapResponseListener);
    self->reading = 0; self->request = 0;
    self->response(self->context, error, NULL, 0);
}
static void on_response(GG_CoapResponseListener* _self, GG_CoapMessage* message) {
    AirTransport* self = GG_SELF(AirTransport, GG_CoapResponseListener);
    self->reading = 0; self->request = 0;
    GG_CoapMessageOption block;
    if (GG_CoapMessage_GetPayloadSize(message) > 4096 ||
        GG_SUCCEEDED(GG_CoapMessage_GetOption(message, GG_COAP_MESSAGE_OPTION_BLOCK2, &block, 0))) {
        self->response(self->context, GG_ERROR_NOT_SUPPORTED, NULL, 0);
        return;
    }
    self->response(self->context, GG_CoapMessage_GetCode(message),
                   GG_CoapMessage_GetPayload(message), GG_CoapMessage_GetPayloadSize(message));
}
GG_IMPLEMENT_INTERFACE(AirTransport, GG_DataSource) { source_sink };
GG_IMPLEMENT_INTERFACE(AirTransport, GG_DataSink) { send_data, set_listener };
GG_IMPLEMENT_INTERFACE(AirTransport, GG_TlsKeyResolver) { resolve_key };
GG_IMPLEMENT_INTERFACE(AirTransport, GG_CoapResponseListener) { on_ack, on_error, on_response };

AirTransport* air_transport_create(uint16_t mtu, const uint32_t ids[2], const uint8_t keys[32],
                                  AirSend send, AirAlarmResponse response, void* context) {
    if (!ids || !keys || !send || !response || mtu < 20 || mtu > 512 || ids[0] == ids[1]) return NULL;
    if (atomic_flag_test_and_set(&transport_in_use)) return NULL;
    if (GG_FAILED(GG_Module_Initialize())) { atomic_flag_clear(&transport_in_use); return NULL; }
    AirTransport* self = calloc(1, sizeof(*self));
    if (!self) { atomic_flag_clear(&transport_in_use); return NULL; }
    memcpy(self->ids, ids, sizeof(self->ids)); memcpy(self->keys, keys, sizeof(self->keys));
    self->mtu = mtu; self->send = send; self->response = response; self->context = context;
    GG_SET_INTERFACE(self, AirTransport, GG_DataSource);
    GG_SET_INTERFACE(self, AirTransport, GG_DataSink);
    GG_SET_INTERFACE(self, AirTransport, GG_TlsKeyResolver);
    GG_SET_INTERFACE(self, AirTransport, GG_CoapResponseListener);
    if (GG_FAILED(GG_Loop_Create(&self->loop)) || GG_FAILED(GG_Loop_BindToCurrentThread(self->loop))) goto fail;
    static const uint16_t ciphers[] = { GG_TLS_PSK_WITH_AES_128_CCM };
    GG_TlsServerOptions tls = { .base = { ciphers, 1 }, .key_resolver = GG_CAST(self, GG_TlsKeyResolver) };
    GG_StackElementGattlinkParameters link = { .initial_max_fragment_size = mtu };
    GG_StackBuilderParameters parameters[] = {
        { GG_STACK_ELEMENT_TYPE_DTLS_SERVER, &tls }, { GG_STACK_ELEMENT_TYPE_GATTLINK, &link }
    };
    if (GG_FAILED(GG_StackBuilder_BuildStack("DSNG", parameters, 2, GG_STACK_ROLE_HUB, NULL,
                   self->loop, GG_CAST(self, GG_DataSource), GG_CAST(self, GG_DataSink), &self->stack))) goto fail;
    GG_StackElementPortInfo top;
    if (GG_FAILED(GG_Stack_GetPortById(self->stack, GG_STACK_ELEMENT_ID_TOP, GG_STACK_PORT_ID_TOP, &top))) goto fail;
    self->top_source = top.source;
    if (GG_FAILED(GG_CoapEndpoint_Create(GG_Loop_GetTimerScheduler(self->loop), top.sink, top.source, &self->coap))) goto fail;
    return self;
fail:
    air_transport_destroy(self);
    return NULL;
}
void air_transport_destroy(AirTransport* self) {
    if (!self) return;
    if (self->top_source) GG_DataSource_SetDataSink(self->top_source, NULL);
    if (self->coap) GG_CoapEndpoint_Destroy(self->coap);
    if (self->stack) GG_Stack_Destroy(self->stack);
    if (self->loop) GG_Loop_Destroy(self->loop);
    volatile uint8_t* erase = self->keys;
    for (size_t i = 0; i < sizeof(self->keys); ++i) erase[i] = 0;
    free(self);
    atomic_flag_clear(&transport_in_use);
}
int air_transport_start(AirTransport* self) { return self ? GG_Stack_Start(self->stack) : GG_ERROR_INVALID_PARAMETERS; }
int air_transport_receive(AirTransport* self, const uint8_t* data, size_t length) {
    if (!self || !self->incoming || !data || !length || length > 512) return GG_ERROR_INVALID_PARAMETERS;
    GG_DynamicBuffer* buffer = NULL;
    GG_Result result = GG_DynamicBuffer_Create(length, &buffer);
    if (GG_FAILED(result)) return result;
    result = GG_DynamicBuffer_SetData(buffer, data, length);
    if (GG_SUCCEEDED(result)) result = GG_DataSink_PutData(self->incoming, GG_DynamicBuffer_AsBuffer(buffer), NULL);
    GG_DynamicBuffer_Release(buffer);
    return result;
}
void air_transport_writable(AirTransport* self) {
    if (self && self->writable) GG_DataSinkListener_OnCanPut(self->writable);
}
int air_transport_work(AirTransport* self, uint32_t* delay) {
    if (!self || !delay) return GG_ERROR_INVALID_PARAMETERS;
    return GG_Loop_DoWork(self->loop, 0, delay);
}
int air_transport_state(AirTransport* self) {
    if (!self) return GG_ERROR_INVALID_PARAMETERS;
    GG_DtlsProtocolStatus status;
    GG_Result result = GG_Stack_GetDtlsProtocolStatus(self->stack, &status);
    return GG_FAILED(result) ? result : (int)status.state;
}
static int request(AirTransport* self, GG_CoapMethod method, const char* first,
                   const char* second, const uint8_t* payload, size_t size) {
    if (!self || self->reading || air_transport_state(self) != GG_TLS_STATE_SESSION) return GG_ERROR_INVALID_STATE;
    GG_CoapMessageOptionParam options[2] = {
        { .option = { .number = GG_COAP_MESSAGE_OPTION_URI_PATH,
          .type = GG_COAP_MESSAGE_OPTION_TYPE_STRING, .value.string = { first, strlen(first) } } },
        { .option = { .number = GG_COAP_MESSAGE_OPTION_URI_PATH,
          .type = GG_COAP_MESSAGE_OPTION_TYPE_STRING, .value.string = { second, second ? strlen(second) : 0 } } }
    };
    GG_CoapClientParameters policy = { .ack_timeout = 5000, .max_resend_count = 0 };
    self->reading = 1;
    GG_Result result = GG_CoapEndpoint_SendRequest(self->coap, method, options, second ? 2 : 1, payload, size,
                       &policy, GG_CAST(self, GG_CoapResponseListener), &self->request);
    if (GG_FAILED(result)) self->reading = 0;
    return result;
}
int air_transport_read(AirTransport* self, unsigned resource) {
    switch (resource) {
        case 0: return request(self, GG_COAP_METHOD_GET, "alarms", NULL, NULL, 0);
        case 1: return request(self, GG_COAP_METHOD_GET, "settings", "capabilities", NULL, 0);
        case 2: return request(self, GG_COAP_METHOD_GET, "liveactivity", NULL, NULL, 0);
        case 3: {
            const uint8_t query[] = { 0x0A, 0x01, 0x01 }; /* packed SettingsRequest.setting_type: HAPTICS */
            return request(self, GG_COAP_METHOD_PUT, "settings", NULL, query, sizeof(query));
        }
        default: return GG_ERROR_INVALID_PARAMETERS;
    }
}
int air_transport_read_alarms(AirTransport* self) { return air_transport_read(self, 0); }
int air_transport_update_alarm(AirTransport* self, uint32_t id, const uint8_t* configuration, size_t length) {
    if (!configuration || !length || length > 512) return GG_ERROR_INVALID_PARAMETERS;
    char identifier[11]; snprintf(identifier, sizeof identifier, "%u", id);
    return request(self, GG_COAP_METHOD_PUT, "alarms", identifier, configuration, length);
}

int air_transport_create_alarm(AirTransport* self, const uint8_t* configuration, size_t length) {
    if (!configuration || !length || length > 512) return GG_ERROR_INVALID_PARAMETERS;
    return request(self, GG_COAP_METHOD_POST, "alarms", NULL, configuration, length);
}
int air_transport_delete_alarm(AirTransport* self, uint32_t id) {
    char identifier[11]; snprintf(identifier, sizeof identifier, "%u", id);
    return request(self, GG_COAP_METHOD_DELETE, "alarms", identifier, NULL, 0);
}

int air_transport_set_haptics(AirTransport* self, const uint8_t* settings, size_t length) {
    if (!settings || !length || length > 512) return GG_ERROR_INVALID_PARAMETERS;
    return request(self, GG_COAP_METHOD_POST, "settings", NULL, settings, length);
}

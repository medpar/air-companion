#include "air_transport.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <errno.h>
#include "xp/module/gg_module.h"
#include "xp/common/gg_common.h"
#include "xp/loop/gg_loop.h"
#include "xp/stack_builder/gg_stack_builder.h"
#include "xp/coap/gg_coap.h"
#define CHECK(x) do { if (!(x)) { fprintf(stderr, "Check failed line %d: %s\n", __LINE__, #x); exit(1); } } while (0)
typedef struct {
    GG_IMPLEMENTS(GG_DataSource);
    GG_IMPLEMENTS(GG_DataSink);
    GG_IMPLEMENTS(GG_CoapRequestHandler);
    GG_IMPLEMENTS(GG_CoapResponseListener);
    GG_DataSink* incoming;
    int fd;
    int requests, responses, blocked, writes, observed, event_responses, info_requests;
} Fixture;
static const uint8_t info_payload[] = { 0x68, 76 };
static const uint8_t haptic_payload[] = { 0x0a, 0x04, 0x0a, 0x02, 0x08, 0x02 };
static const uint8_t payload[] = { 0x0a, 0x04, 0x08, 0x08, 0x10, 0x01 };
static GG_Result set_sink(GG_DataSource* _self, GG_DataSink* sink) {
    Fixture* self = GG_SELF(Fixture, GG_DataSource); self->incoming = sink; return 0;
}
static GG_Result put(GG_DataSink* _self, GG_Buffer* buffer, const GG_BufferMetadata* metadata) {
    (void)metadata; Fixture* self = GG_SELF(Fixture, GG_DataSink);
    size_t size = GG_Buffer_GetDataSize(buffer);
    CHECK(write(self->fd, GG_Buffer_GetData(buffer), size) == (ssize_t)size); return 0;
}
static GG_Result listener(GG_DataSink* self, GG_DataSinkListener* target) { (void)self; (void)target; return 0; }
static GG_Result request(GG_CoapRequestHandler* _self, GG_CoapEndpoint* endpoint,
                        const GG_CoapMessage* msg, GG_CoapResponder* responder,
                        const GG_BufferMetadata* metadata, GG_CoapMessage** result) {
    (void)responder; (void)metadata; Fixture* self = GG_SELF(Fixture, GG_CoapRequestHandler);
    int method = GG_CoapMessage_GetCode(msg);
    GG_CoapMessageOption path;
    CHECK(!GG_CoapMessage_GetOption(msg, GG_COAP_MESSAGE_OPTION_URI_PATH, &path, 0));
    if (path.value.string.length == 6 && !memcmp(path.value.string.chars, "device", 6)) {
        CHECK(method == GG_COAP_METHOD_GET && GG_CoapMessage_GetPayloadSize(msg) == 0);
        CHECK(!GG_CoapMessage_GetOption(msg, GG_COAP_MESSAGE_OPTION_URI_PATH, &path, 1));
        CHECK(path.value.string.length == 4 && !memcmp(path.value.string.chars, "info", 4));
        self->info_requests++;
        return GG_CoapEndpoint_CreateResponse(endpoint, msg, 69, NULL, 0, info_payload, sizeof(info_payload), result);
    }
    if (path.value.string.length == 8 && !memcmp(path.value.string.chars, "settings", 8)) {
        if (method == GG_COAP_METHOD_PUT) {
            const uint8_t query[] = { 10, 1, 1 }; /* packed repeated setting_type */
            CHECK(GG_CoapMessage_GetPayloadSize(msg) == sizeof(query));
            CHECK(!memcmp(GG_CoapMessage_GetPayload(msg), query, sizeof(query)));
            return GG_CoapEndpoint_CreateResponse(endpoint, msg, 69, NULL, 0, haptic_payload, sizeof(haptic_payload), result);
        }
        CHECK(method == GG_COAP_METHOD_POST);
        CHECK(GG_CoapMessage_GetPayloadSize(msg) == sizeof(haptic_payload));
        CHECK(!memcmp(GG_CoapMessage_GetPayload(msg), haptic_payload, sizeof(haptic_payload)));
        return GG_CoapEndpoint_CreateResponse(endpoint, msg, 68, NULL, 0, NULL, 0, result);
    }
    if (method == GG_COAP_METHOD_DELETE) {
        GG_CoapMessageOption option;
        CHECK(!GG_CoapMessage_GetOption(msg, GG_COAP_MESSAGE_OPTION_URI_PATH, &option, 1));
        CHECK(option.value.string.length == 1 && option.value.string.chars[0] == '1');
        CHECK(GG_CoapMessage_GetPayloadSize(msg) == 0); self->writes++;
        return GG_CoapEndpoint_CreateResponse(endpoint, msg, 66, NULL, 0, NULL, 0, result);
    }
    if (method == GG_COAP_METHOD_POST) {
        CHECK(GG_CoapMessage_GetPayloadSize(msg) == sizeof(payload));
        CHECK(!memcmp(GG_CoapMessage_GetPayload(msg), payload, sizeof(payload))); self->writes++;
        return GG_CoapEndpoint_CreateResponse(endpoint, msg, 65, NULL, 0, NULL, 0, result);
    }
    if (method == GG_COAP_METHOD_PUT) {
        GG_CoapMessageOption option;
        CHECK(!GG_CoapMessage_GetOption(msg, GG_COAP_MESSAGE_OPTION_URI_PATH, &option, 1));
        CHECK(option.value.string.length == 1 && option.value.string.chars[0] == '1');
        CHECK(GG_CoapMessage_GetPayloadSize(msg) == sizeof(payload));
        CHECK(!memcmp(GG_CoapMessage_GetPayload(msg), payload, sizeof(payload)));
        self->writes++;
        return GG_CoapEndpoint_CreateResponse(endpoint, msg, 68, NULL, 0, NULL, 0, result);
    }
    CHECK(GG_CoapMessage_GetCode(msg) == GG_COAP_METHOD_GET);
    CHECK(GG_CoapMessage_GetPayloadSize(msg) == 0); self->requests++;
    return GG_CoapEndpoint_CreateResponse(endpoint, msg, 69, NULL, 0, payload, sizeof(payload), result);
}
GG_IMPLEMENT_INTERFACE(Fixture, GG_DataSource) { set_sink };
GG_IMPLEMENT_INTERFACE(Fixture, GG_DataSink) { put, listener };
GG_IMPLEMENT_INTERFACE(Fixture, GG_CoapRequestHandler) { request };
static void event_ack(GG_CoapResponseListener* self) { (void)self; }
static void event_error(GG_CoapResponseListener* self, GG_Result code, const char* message) {
    (void)self; (void)code; (void)message; CHECK(0);
}
static void event_response(GG_CoapResponseListener* _self, GG_CoapMessage* message) {
    Fixture* self = GG_SELF(Fixture, GG_CoapResponseListener);
    CHECK(GG_CoapMessage_GetCode(message) == 132); // Preserve prior unsupported response.
    CHECK(GG_CoapMessage_GetPayloadSize(message) == 0);
    self->event_responses++;
}
GG_IMPLEMENT_INTERFACE(Fixture, GG_CoapResponseListener) { event_ack, event_error, event_response };
static void observed_event(void* context, const uint8_t* bytes, size_t size) {
    Fixture* f = context;
    CHECK(size == 2 && bytes[0] == 8 && bytes[1] == 1);
    f->observed++;
}
static int transport_send(void* context, const uint8_t* bytes, size_t size) {
    Fixture* f = context; if (f->blocked) return 1;
    CHECK(write(f->fd, bytes, size) == (ssize_t)size); return 0;
}
static void response(void* context, int code, const uint8_t* bytes, size_t size) {
    Fixture* f = context;
    if (f->responses == 1) { CHECK(code == 68); CHECK(size == 0); }
    else if (f->responses == 3) { CHECK(code == 65); CHECK(size == 0); }
    else if (f->responses == 5 || f->responses == 7) { CHECK(code == 69); CHECK(size == sizeof(haptic_payload)); CHECK(!memcmp(bytes, haptic_payload, size)); }
    else if (f->responses == 6) { CHECK(code == 68); CHECK(size == 0); }
    else if (f->responses == 4) { CHECK(code == 66); CHECK(size == 0); }
    else if (f->responses == 8) { CHECK(code == 69); CHECK(size == sizeof(info_payload)); CHECK(!memcmp(bytes, info_payload, size)); }
    else { CHECK(code == 69); CHECK(size == sizeof(payload)); CHECK(!memcmp(bytes, payload, size)); }
    f->responses++;
}
int main(void) {
    int sockets[2]; CHECK(!socketpair(AF_UNIX, SOCK_DGRAM, 0, sockets));
    pid_t child = fork(); CHECK(child >= 0);
    Fixture f = {0}; f.fd = sockets[child ? 0 : 1]; close(sockets[child ? 1 : 0]);
    GG_SET_INTERFACE(&f, Fixture, GG_DataSource);
    GG_SET_INTERFACE(&f, Fixture, GG_DataSink);
    GG_SET_INTERFACE(&f, Fixture, GG_CoapRequestHandler);
    GG_SET_INTERFACE(&f, Fixture, GG_CoapResponseListener);
    uint32_t ids[2] = { 0x01020304, 0x05060708 };
    uint8_t keys[32]; for (unsigned i = 0; i < sizeof keys; i++) keys[i] = (uint8_t)(i + 1);
    if (!child) {
        AirTransport* hub = air_transport_create(20, ids, keys, transport_send, response, &f); CHECK(hub);
        CHECK(!air_transport_observe_events(hub, observed_event));
        CHECK(!air_transport_create(20, ids, keys, transport_send, response, &f));
        CHECK(air_transport_read_alarms(hub) < 0); CHECK(!air_transport_start(hub));
        int requested = 0;
        int wrote = 0, verified = 0, created = 0, deleted = 0, settingsRead = 0, settingsWrite = 0, settingsVerify = 0, infoRead = 0;
        for (unsigned step = 0; step < 12000 && (f.responses < 9 || f.observed < 2); ++step) {
            uint32_t delay; CHECK(!air_transport_work(hub, &delay));
            uint8_t bytes[512]; ssize_t n;
            while ((n = recv(f.fd, bytes, sizeof(bytes), MSG_DONTWAIT)) > 0)
                CHECK(!air_transport_receive(hub, bytes, (size_t)n));
            if (air_transport_state(hub) == 2 && !requested) {
                f.blocked = 1; CHECK(!air_transport_read_alarms(hub));
                CHECK(air_transport_read_alarms(hub) < 0);
                f.blocked = 0; air_transport_writable(hub); requested = 1;
            }
            if (f.responses == 1 && !wrote) {
                CHECK(!air_transport_update_alarm(hub, 1, payload, sizeof(payload))); wrote = 1;
            }
            if (f.responses == 2 && !verified) { CHECK(!air_transport_read_alarms(hub)); verified = 1; }
            if (f.responses == 3 && !created) { CHECK(!air_transport_create_alarm(hub, payload, sizeof(payload))); created = 1; }
            if (f.responses == 4 && !deleted) { CHECK(!air_transport_delete_alarm(hub, 1)); deleted = 1; }
            if (f.responses == 5 && !settingsRead) { CHECK(!air_transport_read(hub, 3)); settingsRead = 1; }
            if (f.responses == 6 && !settingsWrite) { CHECK(!air_transport_set_haptics(hub, haptic_payload, sizeof(haptic_payload))); settingsWrite = 1; }
            if (f.responses == 7 && !settingsVerify) { CHECK(!air_transport_read(hub, 3)); settingsVerify = 1; }
            if (f.responses == 8 && !infoRead) { CHECK(!air_transport_read(hub, 4)); infoRead = 1; }
            usleep(1000);
        }
        CHECK(f.responses == 9); CHECK(f.observed == 2); CHECK(air_transport_state(hub) == 2);
        air_transport_destroy(hub);
        for (unsigned attempt = 0; attempt < 3; ++attempt) {
            hub = air_transport_create(20, ids, keys, transport_send, response, &f); CHECK(hub);
            CHECK(air_transport_read_alarms(hub) < 0);
            air_transport_destroy(hub);
        }
        close(f.fd); _exit(0);
    }
    CHECK(!GG_Module_Initialize());
    GG_Loop* loop = NULL; CHECK(!GG_Loop_Create(&loop)); CHECK(!GG_Loop_BindToCurrentThread(loop));
    static const uint16_t ciphers[] = { GG_TLS_PSK_WITH_AES_128_CCM };
    static const uint8_t identity[] = "MD-01020304-00000000";
    GG_TlsClientOptions tls = { .base = { ciphers, 1 }, .psk_identity = identity,
        .psk_identity_size = sizeof(identity) - 1, .psk = keys, .psk_size = 16 };
    GG_StackElementGattlinkParameters link = { .initial_max_fragment_size = 20 };
    GG_StackBuilderParameters parameters[] = {
        { GG_STACK_ELEMENT_TYPE_DTLS_CLIENT, &tls }, { GG_STACK_ELEMENT_TYPE_GATTLINK, &link }
    };
    GG_Stack* stack = NULL;
    CHECK(!GG_StackBuilder_BuildStack("DSNG", parameters, 2, GG_STACK_ROLE_NODE, NULL, loop,
                                    GG_CAST(&f, GG_DataSource), GG_CAST(&f, GG_DataSink), &stack));
    GG_StackElementPortInfo top;
    CHECK(!GG_Stack_GetPortById(stack, GG_STACK_ELEMENT_ID_TOP, GG_STACK_PORT_ID_TOP, &top));
    GG_CoapEndpoint* endpoint = NULL;
    CHECK(!GG_CoapEndpoint_Create(GG_Loop_GetTimerScheduler(loop), top.sink, top.source, &endpoint));
    CHECK(!GG_CoapEndpoint_RegisterRequestHandler(endpoint, "alarms", GG_COAP_REQUEST_HANDLER_FLAG_ALLOW_GET | GG_COAP_REQUEST_HANDLER_FLAG_ALLOW_PUT | GG_COAP_REQUEST_HANDLER_FLAG_ALLOW_POST | GG_COAP_REQUEST_HANDLER_FLAG_ALLOW_DELETE,
                                                GG_CAST(&f, GG_CoapRequestHandler)));
    CHECK(!GG_CoapEndpoint_RegisterRequestHandler(endpoint, "settings", GG_COAP_REQUEST_HANDLER_FLAG_ALLOW_PUT | GG_COAP_REQUEST_HANDLER_FLAG_ALLOW_POST, GG_CAST(&f, GG_CoapRequestHandler)));
    CHECK(!GG_CoapEndpoint_RegisterRequestHandler(endpoint, "device", GG_COAP_REQUEST_HANDLER_FLAG_ALLOW_GET, GG_CAST(&f, GG_CoapRequestHandler)));
    CHECK(!GG_Stack_Start(stack));
    int event_requests = 0;
    for (unsigned step = 0; step < 12000; step++) {
        uint32_t delay; CHECK(!GG_Loop_DoWork(loop, 0, &delay));
        uint8_t bytes[512]; ssize_t n;
        while ((n = recv(f.fd, bytes, sizeof(bytes), MSG_DONTWAIT)) > 0) {
            GG_DynamicBuffer* buffer = NULL; CHECK(!GG_DynamicBuffer_Create((size_t)n, &buffer));
            CHECK(!GG_DynamicBuffer_SetData(buffer, bytes, (size_t)n));
            CHECK(!GG_DataSink_PutData(f.incoming, GG_DynamicBuffer_AsBuffer(buffer), NULL));
            GG_DynamicBuffer_Release(buffer);
        }
        GG_DtlsProtocolStatus tls_status;
        CHECK(!GG_Stack_GetDtlsProtocolStatus(stack, &tls_status));
        if (tls_status.state == GG_TLS_STATE_SESSION && event_requests < 5 && f.event_responses == event_requests) {
            const char* path = event_requests == 4 ? "eventsSecure" : "events";
            GG_CoapMessageOptionParam options[2] = {{ .option = { .number = GG_COAP_MESSAGE_OPTION_URI_PATH,
                .type = GG_COAP_MESSAGE_OPTION_TYPE_STRING, .value.string = {path, strlen(path)} } }};
            unsigned option_count = 1;
            if (event_requests == 0) {
                options[1].option.number = GG_COAP_MESSAGE_OPTION_URI_PATH;
                options[1].option.type = GG_COAP_MESSAGE_OPTION_TYPE_STRING;
                options[1].option.value.string.chars = "unrelated";
                options[1].option.value.string.length = 9;
                option_count = 2;
            } else if (event_requests == 2) {
                options[1].option.number = GG_COAP_MESSAGE_OPTION_BLOCK1;
                options[1].option.type = GG_COAP_MESSAGE_OPTION_TYPE_UINT;
                options[1].option.value.uint = 8; // More fragments follow.
                option_count = 2;
            }
            const uint8_t event[129] = {8, 1}; GG_CoapRequestHandle handle;
            size_t event_size = event_requests == 1 ? sizeof(event) : 2;
            CHECK(!GG_CoapEndpoint_SendRequest(endpoint, GG_COAP_METHOD_POST, options, option_count, event, event_size, NULL, GG_CAST(&f, GG_CoapResponseListener), &handle));
            event_requests++;
        }
        int status; pid_t done = waitpid(child, &status, WNOHANG);
        CHECK(done >= 0);
        if (done == child) { CHECK(WIFEXITED(status) && WEXITSTATUS(status) == 0); child = 0; break; }
        usleep(1000);
    }
    CHECK(!child); CHECK(f.requests == 2); CHECK(f.writes == 3); CHECK(f.event_responses == 5); CHECK(f.info_requests == 1);
    GG_DataSource_SetDataSink(top.source, NULL); GG_CoapEndpoint_Destroy(endpoint);
    GG_Stack_Destroy(stack); GG_Loop_Destroy(loop); close(f.fd);
    puts("PASS: synthetic PSK peers, fragmentation, alarm CRUD and haptic settings query/write/readback, bounded exact-route event observation, backpressure, reconnect cleanup");
    return 0;
}

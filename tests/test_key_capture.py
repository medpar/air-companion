"""Synthetic tests: no real credentials, app requests, or network traffic."""
import base64
import gzip
import importlib.util
import json
import os
import re
from pathlib import Path
import tempfile
import time
from types import SimpleNamespace
import unittest
from unittest.mock import patch


class CaptureTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.previous = os.environ.get('AIR_CAPTURE_DIR')
        os.environ['AIR_CAPTURE_DIR'] = self.tmp.name
        spec = importlib.util.spec_from_file_location('capture', Path(__file__).parents[1] / 'scripts/device_key_capture.py')
        self.capture = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.capture)

    def tearDown(self):
        self.tmp.cleanup()
        if self.previous is None: os.environ.pop('AIR_CAPTURE_DIR', None)
        else: os.environ['AIR_CAPTURE_DIR'] = self.previous

    def flow(self, host='api.fitbit.com', path='/1/user/-/devices/device/test-device/keys', status=200, bad=False):
        key = {'key': base64.b64encode(bytes(range(16))).decode(), 'keyId': 7}
        body = {'data': {'attributes': {'primaryKey': key, 'secondaryKey': key}},
                'unrelatedHealthData': 'do-not-save'}
        if bad: body['data']['attributes']['primaryKey'] = {'key': 'bad', 'keyId': 7}
        return SimpleNamespace(request=SimpleNamespace(host=host, path=path,
                                headers={'Authorization': 'do-not-save-bearer'}),
                               response=SimpleNamespace(status_code=status, json=lambda: body),
                               metadata={})

    def test_only_expected_host_route_and_success(self):
        for flow in [self.flow(host='api.fitbit.com.evil.test'), self.flow(path='/1/user/-/sleep.json'),
                     self.flow(status=401), self.flow(path='/1/user/-/devices/device/test-device/keys/extra')]:
            self.capture.response(flow)
        self.assertFalse(list(self.root.glob('device-keys-*.json')))

    def test_persists_only_validated_key_fields_with_private_permissions(self):
        self.capture.response(self.flow(path='/1/user/-/devices/device/test-device/keys?token=private-query'))
        files = list(self.root.glob('device-keys-*.json'))
        self.assertEqual(len(files), 1)
        data = json.loads(files[0].read_text())
        self.assertEqual(set(data), {'capturedAt', 'keys'})
        self.assertEqual(files[0].stat().st_mode & 0o777, 0o600)
        saved = ''.join(p.read_text() for p in self.root.iterdir())
        for secret in ['do-not-save', 'private-query', 'test-device', 'Authorization']:
            self.assertNotIn(secret, saved)
        status = (self.root / 'status.jsonl').read_text()
        self.assertNotIn(base64.b64encode(bytes(range(16))).decode(), status)

    def test_unknown_schema_does_not_dump_body(self):
        self.capture.response(self.flow(bad=True))
        self.assertFalse(list(self.root.glob('device-keys-*.json')))
        status = (self.root / 'status.jsonl').read_text()
        self.assertIn('key_response_schema_unrecognized', status)
        self.assertNotIn('do-not-save', status)

    def test_android_compatible_decimal_id_and_unpadded_base64(self):
        key = base64.b64encode(bytes(range(16))).decode().rstrip('=') + '\n'
        item = {'key': key, 'keyId': str(2**40)}
        self.capture.save_key_response({'data': {'attributes': {'primaryKey': item, 'secondaryKey': item}}})
        files = list(self.root.glob('device-keys-*.json'))
        self.assertEqual(len(files), 1)
        saved = json.loads(files[0].read_text())['keys']['primaryKey']
        self.assertEqual(saved['keyId'], 2**40)
        self.assertEqual(base64.b64decode(saved['key'], validate=True), bytes(range(16)))
        shape = self.capture.key_schema_shape({'keyId': 2**40, 'private-id': 'private-value'})
        self.assertFalse(shape['keyId']['fits_u32'])
        self.assertNotIn('private-id', json.dumps(shape))
        self.assertNotIn('private-value', json.dumps(shape))

    def test_json_suffix_from_android_url_builder_is_captured(self):
        self.capture.response(self.flow(path='/1/user/-/devices/device/test-device/keys.json'))
        self.assertEqual(len(list(self.root.glob('device-keys-*.json'))), 1)
        self.capture.response(self.flow(path='/1/user/-/devices/device/test-device/keys.json/extra'))
        self.assertEqual(len(list(self.root.glob('device-keys-*.json'))), 1)

    def test_unrelated_connect_not_logged(self):
        self.capture.http_connect(self.flow(host='unrelated.example'))
        self.assertFalse(list(self.root.iterdir()))

    def test_rpc_metadata_excludes_query_resource_ids_and_body(self):
        host = 'fitbit-pa.googleapis.com'
        self.capture.response(self.flow(host=host, path='/$rpc/google.internal.fitbit.devices.v1.DeviceService/GetDeviceKeys?token=private-query'))
        self.capture.response(self.flow(host=host, path='/users/private-user-id/health'))
        saved = (self.root / 'status.jsonl').read_text()
        self.assertIn('DeviceService/GetDeviceKeys', saved)
        for value in ['private-user-id', 'private-query', 'unrelatedHealthData', 'do-not-save']:
            self.assertNotIn(value, saved)
        self.assertFalse(list(self.root.glob('device-keys-*.json')))

    def test_tls_failure_restores_passthrough_for_affected_host(self):
        host = 'fitbit-pa.googleapis.com'
        data = SimpleNamespace(context=SimpleNamespace(server=SimpleNamespace(address=(host,443))))
        with patch.object(self.capture, 'apply_host_scope') as update:
            self.capture.tls_failed_client(data)
            update.assert_called_once()
        self.assertNotIn(host, self.capture.ACTIVE_HOSTS)
        self.assertIn('api.fitbit.com', self.capture.ACTIVE_HOSTS)

    def test_host_filter_is_exact_and_empty_scope_intercepts_nothing(self):
        from mitmproxy import ctx
        options = SimpleNamespace(update=lambda **kw: setattr(options, 'allow_hosts', kw['allow_hosts']))
        with patch.object(ctx, 'options', options, create=True):
            self.capture.apply_host_scope()
            pattern = re.compile(options.allow_hosts[0])
            self.assertTrue(pattern.fullmatch('fitbit-pa.googleapis.com:443'))
            for host in ['mail.googleapis.com', 'api.fitbit.com.evil.test', 'evil-api.fitbit.com', 'fitbit-pa.googleapis.com:8443']:
                self.assertIsNone(pattern.fullmatch(host))
            self.capture.ACTIVE_HOSTS.clear()
            self.capture.apply_host_scope()
            self.assertIsNone(re.compile(options.allow_hosts[0]).search('api.fitbit.com'))

    def test_unrelated_response_bodies_stream_without_buffering(self):
        flow = self.flow(host='fitbit-pa.googleapis.com', path='/users/private-user-id/health')
        flow.response.headers = {'content-type': 'application/grpc'}
        self.capture.requestheaders(flow)
        self.capture.responseheaders(flow)
        self.assertTrue(flow.request.stream)
        self.assertTrue(flow.response.stream)
        self.assertNotIn('private-user-id', (self.root / 'status.jsonl').read_text())
        key_flow = self.flow()
        key_flow.response.headers = {'content-type': 'application/json'}
        self.capture.responseheaders(key_flow)
        self.assertFalse(getattr(key_flow.response, 'stream', False))

    def test_certificate_download_serves_only_public_certificate_at_exact_url(self):
        from mitmproxy import ctx
        public = b'PUBLIC CERTIFICATE FIXTURE'
        (self.root / 'mitmproxy-ca-cert.cer').write_bytes(public)
        (self.root / 'mitmproxy-ca.pem').write_bytes(b'PRIVATE KEY MUST NEVER BE SERVED')
        options = SimpleNamespace(listen_host='192.0.2.1', listen_port=8080,
                                  confdir=str(self.root))
        with patch.object(ctx, 'options', options, create=True):
            for change in [{}, {'path': '/mitmproxy-ca.pem'}, {'host': 'example.com'},
                           {'port': 80}, {'scheme': 'https'}, {'method': 'POST'}]:
                request = dict(method='GET', scheme='http', host='192.0.2.1',
                               port=8080, path='/air-research.cer')
                request.update(change)
                flow = SimpleNamespace(request=SimpleNamespace(**request), response=None)
                self.capture.request(flow)
                if change:
                    self.assertIsNone(flow.response)
                else:
                    self.assertEqual(flow.response.status_code, 200)
                    self.assertEqual(flow.response.content, public)

    def test_certificate_download_can_arm_once_without_rearming_consumed_probe(self):
        from mitmproxy import ctx
        (self.root / 'mitmproxy-ca-cert.cer').write_bytes(b'PUBLIC FIXTURE')
        options = SimpleNamespace(listen_host='192.0.2.1', listen_port=8080, confdir=str(self.root))
        flow = SimpleNamespace(request=SimpleNamespace(method='GET', scheme='http',
                               host='192.0.2.1', port=8080, path='/air-research.cer'), response=None)
        trigger = self.root / 'read-keys-on-certificate-download'
        marker = self.root / 'read-keys-once'
        with patch.object(ctx, 'options', options, create=True):
            self.capture.request(flow)
            self.assertFalse(marker.exists())
            trigger.touch()
            self.capture.request(flow)
            self.assertFalse(trigger.exists())
            self.assertGreater(float(marker.read_text()), time.time() + 590)
            deadline = marker.read_text()
            self.capture.request(flow)
            self.assertEqual(marker.read_text(), deadline)
            marker.unlink()
            (self.root / 'read-keys-consumed').touch()
            trigger.touch()
            self.capture.request(flow)
            self.assertFalse(marker.exists())

    @staticmethod
    def varint(value):
        result = bytearray()
        while value >= 128:
            result.append((value & 127) | 128)
            value >>= 7
        result.append(value)
        return bytes(result)

    def field(self, number, value):
        if isinstance(value, int):
            return self.varint(number << 3) + self.varint(value)
        return self.varint(number << 3 | 2) + self.varint(len(value)) + value

    def frame(self, message, compressed=False):
        payload = gzip.compress(message) if compressed else message
        return bytes([int(compressed)]) + len(payload).to_bytes(4, 'big') + payload

    def rpc_flow(self, compressed=False):
        flow = self.flow(host='fitbitvestibuleshim-pa.googleapis.com', path='/' + self.capture.HTTP_RPC)
        flow.request.method = 'POST'
        flow.request.headers['grpc-encoding'] = 'gzip' if compressed else 'identity'
        flow.response.headers = {'grpc-encoding': flow.request.headers['grpc-encoding'],
                                 'content-type': 'application/grpc'}
        return flow

    def forward(self, observer, payload):
        # Include arbitrary fragmentation, not just aligned protobuf/gRPC frames.
        forwarded = b''.join(observer(payload[i:i+7]) for i in range(0, len(payload), 7))
        self.assertEqual(observer(b''), b'')
        self.assertEqual(forwarded, payload)

    def test_grpc_key_capture_uncompressed_and_gzip_forwards_unchanged(self):
        for compressed in (False, True):
            with self.subTest(compressed=compressed):
                flow = self.rpc_flow(compressed)
                message = (self.field(1, b'GET') + self.field(2,
                    b'https://android-cdn-api.fitbit.com/1/user/-/devices/device/private-device/keys.json?secret=query')
                    + self.field(3, b'private-inner-authorization') + self.field(9, b'private-account'))
                self.capture.requestheaders(flow)
                self.forward(flow.request.stream, self.frame(message, compressed))
                self.assertTrue(flow.metadata['air_key_request'])
                self.capture.responseheaders(flow)
                body = json.dumps(flow.response.json()).encode()
                self.forward(flow.response.stream, self.frame(
                    self.field(1, 200) + self.field(2, b'private-response-header') + self.field(3, body), compressed))
        self.assertEqual(len(list(self.root.glob('device-keys-*.json'))), 2)
        persisted = ''.join(p.read_text() for p in self.root.iterdir())
        for secret in ('private-device', 'secret=query', 'private-inner', 'private-account',
                       'private-response-header', 'unrelatedHealthData', 'do-not-save'):
            self.assertNotIn(secret, persisted)

    def test_non_key_rpc_requests_never_observe_responses(self):
        for url in (b'https://api.fitbit.com/1/user/-/sleep.json',
                    b'https://api.fitbit.com.evil.test/1/user/-/devices/device/test/keys',
                    b'http://api.fitbit.com/1/user/-/devices/device/test/keys',
                    b'https://api.fitbit.com:8443/1/user/-/devices/device/test/keys'):
            flow = self.rpc_flow()
            self.capture.requestheaders(flow)
            self.forward(flow.request.stream, self.frame(self.field(1, b'GET') + self.field(2, url)))
            self.assertFalse(flow.metadata['air_key_request'])
            self.capture.responseheaders(flow)
            self.assertIs(flow.response.stream, True)
        self.assertFalse(list(self.root.glob('device-keys-*.json')))

    def test_malformed_oversized_and_ambiguous_envelopes_fail_closed(self):
        good = self.field(1, b'GET') + self.field(2, b'https://api.fitbit.com/1/user/-/devices/device/test/keys')
        fixtures = [b'\x00\x00', self.frame(good) + self.frame(good),
                    self.frame(good + self.field(2, b'duplicate-url')),
                    self.frame(b'\x12\xff'), self.frame(b'\x00'),
                    self.frame(b'\x08' + b'\xff' * 10),
                    self.frame(b'x' * (self.capture.MAX_ENVELOPE + 1)),
                    self.frame(b'x' * (self.capture.MAX_ENVELOPE + 1), True)]
        for payload in fixtures:
            flow = self.rpc_flow(compressed=True)
            self.capture.requestheaders(flow)
            self.forward(flow.request.stream, payload)
            self.assertFalse(flow.metadata.get('air_key_request', False))
        self.assertFalse(list(self.root.glob('device-keys-*.json')))

    def test_inner_error_response_does_not_save_keys(self):
        flow = self.rpc_flow()
        flow.metadata['air_key_request'] = True
        self.capture.responseheaders(flow)
        self.forward(flow.response.stream, self.frame(self.field(1, 401) +
                     self.field(3, json.dumps(flow.response.json()).encode())))
        self.assertFalse(list(self.root.glob('device-keys-*.json')))

    def real_rpc_flow(self):
        from mitmproxy import http, connection
        flow = http.HTTPFlow(connection.Client(peername=('192.0.2.2', 1234),
                             sockname=('192.0.2.1', 8080), alpn=b'grpc-exp'),
                             connection.Server(address=(self.capture.PROBE_HOST, 443)), live=True)
        header = self.field(1, b'Authorization') + self.field(2, b'private-inner-token')
        cache_header = self.field(1, b'If-None-Match') + self.field(2, b'private-etag')
        message = (self.field(1, b'GET') + self.field(2, b'https://api.fitbit.com/1/user/-/profile.json')
                   + self.field(3, header) + self.field(3, cache_header) + self.field(9, b'private-account'))
        flow.request = http.Request.make('POST', 'https://' + self.capture.PROBE_HOST + '/' + self.capture.HTTP_RPC,
                                         self.frame(message), {'Authorization': 'Bearer private-outer-token',
                                                              'Content-Type': 'application/grpc'})
        flow.request.http_version = 'HTTP/2.0'
        return flow

    def test_cloud_probe_requires_unexpired_single_use_marker_and_leaves_original_unchanged(self):
        flow = self.real_rpc_flow()
        original = flow.request.get_state()
        with patch.object(self.capture, 'queue_cloud_read') as queue:
            self.capture.classify_inner_request(flow, flow.request.content)
            queue.assert_not_called()
            marker = self.root / 'read-keys-once'
            marker.write_text(str(time.time() - 1))
            self.capture.classify_inner_request(flow, flow.request.content)
            queue.assert_not_called()
            marker.write_text(str(time.time() + 120))
            self.capture.classify_inner_request(flow, flow.request.content)
            self.capture.classify_inner_request(flow, flow.request.content)
            queue.assert_called_once()
            copied = queue.call_args.args[0]
        self.assertEqual(flow.request.get_state(), original)
        self.assertFalse(copied.live)
        self.assertEqual(copied.request.host, flow.request.host)
        fields = self.capture.grpc_message(copied.request.content, 'identity')
        self.assertEqual(self.capture.one_field(fields, 1, 2), b'GET')
        self.assertEqual(self.capture.one_field(fields, 2, 2), b'https://api.fitbit.com/1/user/-/devices.json')
        self.assertNotIn(b'private-etag', copied.request.content)
        self.assertFalse(marker.exists())
        saved = ''.join(p.read_text() for p in self.root.iterdir())
        for secret in ('private-inner-token', 'private-outer-token', 'private-account'):
            self.assertNotIn(secret, saved)

    def test_cloud_probe_only_unique_air_keys_and_at_most_one_followup(self):
        from mitmproxy import http
        flow = self.real_rpc_flow()
        fields = self.capture.grpc_message(flow.request.content, 'identity')
        for models, expected in [([], 0), (['Charge 6'], 0), (['Air', 'Fitbit Air'], 0), (['Air'], 1)]:
            copied = self.capture.build_cloud_read(flow, fields, 'https://api.fitbit.com', 'devices')
            copied.response = http.Response.make(200, b'', {'content-type': 'application/grpc'})
            body = [{'deviceVersion': m, 'type': 'TRACKER', 'id': 'private-device'} for m in models]
            payload = self.frame(self.field(1, 200) + self.field(3, json.dumps(body).encode()))
            with patch.object(self.capture, 'queue_cloud_read') as queue:
                self.capture.probe_response(copied, payload)
                self.capture.probe_response(copied, payload)
                self.assertEqual(queue.call_count, expected)
                if expected:
                    key_flow = queue.call_args.args[0]
                    key_fields = self.capture.grpc_message(key_flow.request.content, 'identity')
                    self.assertEqual(self.capture.one_field(key_fields, 1, 2), b'GET')
                    self.assertTrue(self.capture.one_field(key_fields, 2, 2).endswith(b'/private-device/keys.json'))
        self.assertNotIn('private-device', (self.root / 'status.jsonl').read_text())

    def test_cloud_probe_rejects_other_operations_origins_ids_and_outer_hosts(self):
        flow = self.real_rpc_flow()
        fields = self.capture.grpc_message(flow.request.content, 'identity')
        for origin, stage, device in [('https://evil.test', 'devices', None),
                                      ('https://api.fitbit.com/path', 'devices', None),
                                      ('https://api.fitbit.com', 'reset', None),
                                      ('https://api.fitbit.com', 'keys', '../other'),
                                      ('https://api.fitbit.com', 'keys', 'id?redirect=evil')]:
            with self.assertRaises(ValueError):
                self.capture.build_cloud_read(flow, fields, origin, stage, device)
        flow.request.host = 'evil.test'
        with self.assertRaises(ValueError):
            self.capture.build_cloud_read(flow, fields, 'https://api.fitbit.com', 'devices')


if __name__ == '__main__': unittest.main()

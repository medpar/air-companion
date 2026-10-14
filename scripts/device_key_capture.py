"""Scoped mitmproxy addon; never persist request credentials or unrelated bodies.

Run only after the user authorizes temporary iPhone proxy/certificate setup.
By default this addon only observes normal app responses. A short-lived,
single-use read-keys-once marker enables at most two additional cloud GETs:
paired devices, then the unique Air's keys. Original traffic is never changed.
"""
import base64
import json
import os
from pathlib import Path
import re
import time
from urllib.parse import urlsplit
import zlib

from mitmproxy import http

# Android's shz URL builder appends .json; keep the extensionless form for
# potential iOS parity without admitting unrelated API resources.
KEY_ROUTE = re.compile(r"^/1/user/[^/]+/devices/device/[^/]+/keys(?:\.json)?/?$")
CAPTURE_HOSTS = frozenset({
    'api.fitbit.com', 'fitbit-pa.googleapis.com',
    'fitbitvestibuleshim-pa.googleapis.com',
    'web-api.fitbit.com',
    'iphone-cdn-api.fitbit.com',
})
ACTIVE_HOSTS = set(CAPTURE_HOSTS)
# Only schema-like RPC service/method identifiers, never user resource paths.
RPC_ROUTE = re.compile(r'^/(?:\$rpc/)?((?:google|fitbit)\.[A-Za-z0-9_.]+/[A-Z][A-Za-z0-9_]*)$')
HTTP_RPC = 'fitbit.platform.vestibuleshim.proto.GaiaToFitbitAuthProxyService/HTTPRequest'
INNER_HOSTS = frozenset({'api.fitbit.com', 'android-api.fitbit.com',
                         'android-cdn-api.fitbit.com', 'web-api.fitbit.com',
                         'iphone-cdn-api.fitbit.com'})
MAX_ENVELOPE = 64 * 1024
PROBE_HOST = 'fitbitvestibuleshim-pa.googleapis.com'
ROOT = Path(os.environ["AIR_CAPTURE_DIR"])
ROOT.mkdir(parents=True, exist_ok=True, mode=0o700)


def append_status(event, **fields):
    line = json.dumps({"time": time.time(), "event": event, **fields}) + "\n"
    fd = os.open(ROOT / "status.jsonl", os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o600)
    with os.fdopen(fd, "a") as out:
        out.write(line)


def apply_host_scope():
    from mitmproxy import ctx
    pattern = r'^(?:' + '|'.join(re.escape(h) for h in sorted(ACTIVE_HOSTS)) + r')(?::443)?$' if ACTIVE_HOSTS else r'(?!)'
    ctx.options.update(allow_hosts=[pattern])


def running():
    if (ROOT / 'passthrough-only').exists():
        ACTIVE_HOSTS.clear()
    apply_host_scope()
    append_status('capture_scope_ready', hosts=sorted(ACTIVE_HOSTS))
    retry = ROOT / 'retry-key-read-once'
    if ACTIVE_HOSTS and retry.exists():
        retry.unlink()
        from mitmproxy import ctx
        playback = ctx.master.addons.get('clientplayback')
        previous = playback.inflight if playback else None
        if (previous and previous.metadata.get('air_probe_stage') == 'keys'
                and previous.response and previous.response.status_code == 200):
            fields = grpc_message(previous.request.content, 'identity')
            inner = urlsplit(one_field(fields, 2, 2).decode('utf-8'))
            if KEY_ROUTE.fullmatch(inner.path):
                candidate = build_cloud_read(previous, fields,
                    previous.metadata['air_probe_origin'], 'keys', inner.path.split('/')[-2])
                queue_cloud_read(candidate)
        else:
            append_status('key_read_retry_unavailable')
    reconnect = ROOT / 'reconnect-fitbit-cloud-once'
    if ACTIVE_HOSTS and reconnect.exists():
        reconnect.unlink()
        from mitmproxy import ctx
        proxy = ctx.master.addons.get('proxyserver')
        count = 0
        if proxy:
            for handler in list(proxy.connections.values()):
                if any(getattr(conn, 'address', None) == (PROBE_HOST, 443)
                       for conn in handler.transports):
                    transport = handler.transports.get(handler.client)
                    if transport and transport.writer:
                        transport.writer.close()
                        count += 1
        append_status('fitbit_cloud_connections_closed_once', count=count)
    if not ACTIVE_HOSTS:
        # End-of-experiment protocol metadata only; no payloads or credentials.
        from mitmproxy import ctx
        proxy = ctx.master.addons.get('proxyserver')
        if proxy:
            for handler in list(proxy.connections.values()):
                for conn in list(handler.transports):
                    address = getattr(conn, 'address', None)
                    if address and address[0] in CAPTURE_HOSTS:
                        def protocol(value):
                            return value.decode() if value in (b'h2', b'http/1.1', b'grpc-exp') else ('none' if value is None else 'other')
                        append_status('connection_protocol_at_cleanup', host=address[0],
                                      client_alpn=protocol(handler.client.alpn),
                                      server_alpn=protocol(conn.alpn), http2=ctx.options.http2)


def http_connect(flow: http.HTTPFlow):
    host = flow.request.host.lower()
    if "fitbit" in host or "health" in host:
        append_status("connect", host=host)


def requestheaders(flow: http.HTTPFlow):
    host = flow.request.host.lower()
    if host not in CAPTURE_HOSTS:
        return
    if flow.metadata.get('air_probe_stage'):
        # Locally generated, bounded unary request already has complete content.
        flow.request.stream = False
        return
    flow.request.stream = True
    rpc = RPC_ROUTE.fullmatch(flow.request.path.split('?', 1)[0])
    if rpc and rpc.group(1) == HTTP_RPC:
        # Inspect a bounded copy while forwarding every byte unchanged. Keep only
        # a boolean route classification; never persist the URL or inner headers.
        flow.request.stream = envelope_observer(
            lambda data: classify_inner_request(flow, data))
    method = getattr(flow.request, 'method', '')
    append_status('request_headers', host=host, rpc=rpc.group(1) if rpc else None,
                  method=method if method in {'GET', 'POST', 'PUT', 'DELETE', 'HEAD', 'OPTIONS', 'CONNECT', 'PATCH'} else 'other',
                  key_route=bool(KEY_ROUTE.fullmatch(flow.request.path.split('?', 1)[0])))


def error(flow: http.HTTPFlow):
    host = flow.request.host.lower()
    if host not in CAPTURE_HOSTS:
        return
    message = str(flow.error).lower()
    category = next((s for s in ('timeout', 'reset', 'closed', 'http/2', 'tls', 'certificate') if s in message), 'other')
    append_status('request_error', host=host, category=category)


def responseheaders(flow: http.HTTPFlow):
    host = flow.request.host.lower()
    if host not in CAPTURE_HOSTS or flow.response is None:
        return
    if flow.metadata.get('air_probe_stage'):
        flow.response.stream = envelope_observer(lambda data: probe_response(flow, data))
        return
    if not KEY_ROUTE.fullmatch(flow.request.path.split('?', 1)[0]):
        flow.response.stream = True
    if flow.metadata.get('air_key_request') and flow.response.status_code == 200:
        flow.response.stream = envelope_observer(
            lambda data: capture_inner_response(flow, data))
    rpc = RPC_ROUTE.fullmatch(flow.request.path.split('?', 1)[0])
    content_type = flow.response.headers.get('content-type', '').split(';')[0].lower()
    category = content_type if content_type in {'application/grpc', 'application/grpc+proto', 'application/json', 'application/x-protobuf'} else 'other'
    append_status('response_headers', host=host, rpc=rpc.group(1) if rpc else None,
                  status=flow.response.status_code, format=category)


def tls_established_client(data):
    host = data.context.server.address[0] if data.context.server.address else 'unknown'
    if host in CAPTURE_HOSTS:
        append_status('fitbit_tls_established', host=host)


def response(flow: http.HTTPFlow):
    host = flow.request.host.lower()
    if host not in CAPTURE_HOSTS or flow.response is None:
        return
    if flow.metadata.get('air_probe_stage'):
        append_status('cloud_read_complete', stage=flow.metadata['air_probe_stage'],
                      status=flow.response.status_code)
        return
    path = flow.request.path.split("?", 1)[0]
    is_key = bool(KEY_ROUTE.fullmatch(path))
    rpc = RPC_ROUTE.fullmatch(path)
    append_status("response", route="device_keys" if is_key else "other_fitbit",
                  host=host, rpc=rpc.group(1) if rpc else None,
                  status=flow.response.status_code)
    if not is_key or flow.response.status_code != 200:
        return
    try:
        save_key_response(flow.response.json())
    except (ValueError, KeyError, TypeError):
        append_status("key_response_schema_unrecognized")


def save_key_response(body):
    try:
        attributes = body["data"]["attributes"]
        keys = {}
        for label in ("primaryKey", "secondaryKey"):
            item = attributes[label]
            key = item["key"]
            key_id = item["keyId"]
            # Android uses JSONObject.getLong and Base64.DEFAULT: decimal JSON
            # strings, whitespace and omitted padding are accepted there.
            if isinstance(key_id, str) and re.fullmatch(r'-?[0-9]{1,19}', key_id):
                key_id = int(key_id)
            if not isinstance(key, str) or type(key_id) is not int or not -(2**63) <= key_id < 2**63:
                raise ValueError("unexpected key field types")
            # Validate encoding, without displaying key material.
            key = re.sub(r'[\t\n\r ]', '', key)
            raw = base64.b64decode(key + '=' * (-len(key) % 4), validate=True)
            if len(raw) not in (16, 24, 32):
                raise ValueError("unexpected key length")
            keys[label] = {"key": base64.b64encode(raw).decode('ascii'), "keyId": key_id}
        name = f"device-keys-{time.time_ns()}.json"
        fd = os.open(ROOT / name, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "w") as out:
            json.dump({"capturedAt": time.time(), "keys": keys}, out)
        append_status("keys_saved", filename=name, count=len(keys))
    except (ValueError, KeyError, TypeError):
        # Unknown schemas are not dumped wholesale: they may contain health data.
        append_status("key_response_schema_unrecognized", shape=key_schema_shape(body))


def key_schema_shape(value, depth=0):
    """Only known schema labels, value types and lengths; never field values."""
    known = {'data', 'attributes', 'primaryKey', 'secondaryKey', 'key', 'keyId',
             'keys', 'primary', 'secondary', 'id', 'type', 'errors', 'success'}
    if depth > 5:
        return 'depth_limit'
    if isinstance(value, dict):
        shape = {name: key_schema_shape(item, depth + 1)
                 for name, item in value.items() if name in known}
        shape['other_field_count'] = sum(name not in known for name in value)
        return shape
    if isinstance(value, list):
        return {'type': 'list', 'count': len(value),
                'items': [key_schema_shape(item, depth + 1) for item in value[:2]]}
    if isinstance(value, str):
        return {'type': 'str', 'length': len(value)}
    if type(value) is int:
        return {'type': 'int', 'fits_u32': 0 <= value <= 0xFFFFFFFF,
                'fits_i64': -(2**63) <= value < 2**63}
    return type(value).__name__


def envelope_observer(consume):
    """Observe at most 64 KiB, without delaying, changing, or retaining a stream."""
    pending = bytearray()
    discarded = False

    def observe(chunk):
        nonlocal discarded
        if chunk and not discarded:
            if len(pending) + len(chunk) > MAX_ENVELOPE:
                pending.clear()
                discarded = True
                append_status('rpc_envelope_too_large')
            else:
                pending.extend(chunk)
        if not chunk:
            try:
                if not discarded:
                    consume(bytes(pending))
            except (ValueError, TypeError, KeyError, UnicodeError, zlib.error):
                append_status('rpc_envelope_unrecognized')
            finally:
                pending.clear()
                discarded = True
        return chunk

    return observe


def protobuf_fields(data):
    """Read bounded protobuf fields; reject ambiguous duplicates at call sites."""
    if len(data) > MAX_ENVELOPE:
        raise ValueError('oversized protobuf')
    pos = 0

    def varint():
        nonlocal pos
        value = 0
        for shift in range(0, 70, 7):
            if pos >= len(data):
                raise ValueError('truncated varint')
            byte = data[pos]
            pos += 1
            if shift == 63 and byte > 1:
                raise ValueError('overflow varint')
            value |= (byte & 127) << shift
            if byte < 128:
                return value
        raise ValueError('unterminated varint')

    fields = {}
    while pos < len(data):
        tag = varint()
        number, wire = tag >> 3, tag & 7
        if not 0 < number < 2**29:
            raise ValueError('invalid field')
        if wire == 0:
            value = varint()
        elif wire in (1, 2, 5):
            size = varint() if wire == 2 else (8 if wire == 1 else 4)
            if size > len(data) - pos:
                raise ValueError('truncated field')
            value = data[pos:pos + size]
            pos += size
        else:
            raise ValueError('unsupported wire type')
        fields.setdefault(number, []).append((wire, value))
    return fields


def one_field(fields, number, wire):
    values = fields.get(number, [])
    if len(values) != 1 or values[0][0] != wire:
        raise ValueError('missing or ambiguous field')
    return values[0][1]


def grpc_message(data, encoding):
    # This is a unary method. Do not guess through multiple frames or gRPC-Web.
    if len(data) < 5 or int.from_bytes(data[1:5], 'big') != len(data) - 5:
        raise ValueError('invalid unary frame')
    if len(data) > MAX_ENVELOPE or data[0] not in (0, 1):
        raise ValueError('invalid frame')
    payload = data[5:]
    if data[0] == 1:
        if encoding != 'gzip':
            raise ValueError('unsupported compression')
        decoder = zlib.decompressobj(16 + zlib.MAX_WBITS)
        payload = decoder.decompress(payload, MAX_ENVELOPE + 1)
        if len(payload) > MAX_ENVELOPE or not decoder.eof or decoder.unused_data:
            raise ValueError('invalid or oversized gzip')
    return protobuf_fields(payload)


def classify_inner_request(flow, data):
    fields = grpc_message(data, flow.request.headers.get('grpc-encoding', 'identity'))
    method = one_field(fields, 1, 2)
    url = urlsplit(one_field(fields, 2, 2).decode('utf-8'))
    is_key = (method == b'GET' and url.scheme == 'https'
              and url.hostname in INNER_HOSTS and url.port in (None, 443)
              and url.username is None and url.password is None
              and bool(KEY_ROUTE.fullmatch(url.path)))
    flow.metadata['air_key_request'] = is_key
    append_status('inner_request_classified', key_route=is_key,
                  known_host=url.hostname in INNER_HOSTS,
                  host=url.hostname if url.hostname and re.fullmatch(r'[a-z-]+\.fitbit\.com', url.hostname) else 'other',
                  key_path=bool(KEY_ROUTE.fullmatch(url.path)),
                  get_method=method == b'GET')
    maybe_start_probe(flow, fields, url, method)


def capture_inner_response(flow, data):
    fields = grpc_message(data, flow.response.headers.get('grpc-encoding', 'identity'))
    status = one_field(fields, 1, 0)
    append_status('inner_key_response', status=status)
    if status == 200:
        save_key_response(json.loads(one_field(fields, 3, 2)))


def encode_varint(value):
    out = bytearray()
    while value >= 128:
        out.append((value & 127) | 128)
        value >>= 7
    out.append(value)
    return bytes(out)


def encode_fields(fields):
    out = bytearray()
    for number, entries in fields.items():
        for wire, value in entries:
            out.extend(encode_varint(number << 3 | wire))
            if wire == 0:
                out.extend(encode_varint(value))
            elif wire == 2:
                out.extend(encode_varint(len(value)))
                out.extend(value)
            elif wire in (1, 5):
                out.extend(value)
            else:
                raise ValueError('unsupported field')
    if len(out) > MAX_ENVELOPE - 5:
        raise ValueError('oversized request')
    return bytes(out)


def build_cloud_read(original, fields, origin, stage, device_id=None):
    """Only two hard-coded GET resources, through the same observed RPC host."""
    rpc = RPC_ROUTE.fullmatch(original.request.path.split('?', 1)[0])
    if (original.request.host != PROBE_HOST or original.request.scheme != 'https'
            or original.request.port != 443 or not rpc or rpc.group(1) != HTTP_RPC):
        raise ValueError('unexpected outer endpoint')
    url = urlsplit(origin)
    if (url.scheme != 'https' or url.hostname not in INNER_HOSTS
            or url.port not in (None, 443) or url.username or url.password
            or url.path or url.query or url.fragment):
        raise ValueError('unexpected inner origin')
    if stage == 'devices' and device_id is None:
        path = '/1/user/-/devices.json'
    elif stage == 'keys' and isinstance(device_id, str) and re.fullmatch(r'[A-Za-z0-9_-]{1,64}', device_id):
        path = '/1/user/-/devices/device/' + device_id + '/keys.json'
    else:
        raise ValueError('unsupported read')
    # Preserve only known wrapper/account fields, replacing method, URL, and body.
    cleaned = {1: [(2, b'GET')], 2: [(2, (origin + path).encode())]}
    for number, wire in ((9, 2), (10, 0)):
        if number in fields:
            cleaned[number] = [(wire, one_field(fields, number, wire))]
    headers = []
    for wire, value in fields.get(3, []):
        if wire != 2:
            raise ValueError('unexpected inner header')
        header = protobuf_fields(value)
        name = one_field(header, 1, 2).decode('ascii').lower()
        if name in ('content-length', 'content-encoding', 'if-none-match', 'if-modified-since'):
            continue
        headers.append((2, value))
    if headers:
        cleaned[3] = headers
    payload = encode_fields(cleaned)
    copied = original.copy()
    copied.live = False
    copied.response = None
    copied.error = None
    copied.metadata = {'air_probe_stage': stage, 'air_probe_origin': origin}
    copied.request.method = 'POST'
    copied.request.stream = False
    copied.request.headers.pop('content-encoding', None)
    copied.request.headers['grpc-encoding'] = 'identity'
    copied.request.headers['grpc-timeout'] = '15S'
    copied.request.content = b'\x00' + len(payload).to_bytes(4, 'big') + payload
    copied.request.trailers = None
    return copied


def queue_cloud_read(flow):
    from mitmproxy import ctx
    ctx.master.commands.call('replay.client', [flow])
    append_status('cloud_read_queued', stage=flow.metadata['air_probe_stage'])


def maybe_start_probe(flow, fields, url, method):
    marker = ROOT / 'read-keys-once'
    if (not marker.exists() or flow.metadata.get('air_probe_stage') or method != b'GET'
            or url.scheme != 'https' or url.hostname not in INNER_HOSTS
            or url.port not in (None, 443) or url.username or url.password):
        return
    deadline = float(marker.read_text())
    if not 0 < deadline - time.time() <= 600:
        marker.unlink()
        append_status('cloud_read_marker_expired')
        return
    origin = 'https://' + url.hostname
    candidate = build_cloud_read(flow, fields, origin, 'devices')
    # Consume before scheduling; no retries or additional reads on error/reload.
    marker.rename(ROOT / 'read-keys-consumed')
    queue_cloud_read(candidate)


def probe_response(flow, data):
    if flow.metadata.get('air_probe_handled'):
        return
    flow.metadata['air_probe_handled'] = True
    stage = flow.metadata['air_probe_stage']
    if flow.response.status_code != 200:
        append_status('cloud_read_failed', stage=stage, status=flow.response.status_code)
        return
    fields = grpc_message(data, flow.response.headers.get('grpc-encoding', 'identity'))
    status = one_field(fields, 1, 0)
    append_status('cloud_read_inner_status', stage=stage, status=status)
    if status != 200:
        return
    body = json.loads(one_field(fields, 3, 2))
    if stage == 'keys':
        save_key_response(body)
        return
    if stage != 'devices' or not isinstance(body, list):
        raise ValueError('unknown devices response')
    matches = [item for item in body if isinstance(item, dict)
               and item.get('deviceVersion') in ('Air', 'Fitbit Air', 'Google Fitbit Air')
               and item.get('type') == 'TRACKER']
    append_status('cloud_read_air_matches', count=len(matches))
    if len(matches) != 1:
        return
    # The captured device identifier never enters logs or filenames.
    request_fields = grpc_message(flow.request.content, 'identity')
    candidate = build_cloud_read(flow, request_fields, flow.metadata['air_probe_origin'],
                                 'keys', matches[0].get('id'))
    queue_cloud_read(candidate)


def tls_failed_client(data):
    # Do not persist the error string, which may contain arbitrary input.
    host = data.context.server.address[0] if data.context.server.address else "unknown"
    if host in CAPTURE_HOSTS:
        append_status("fitbit_tls_client_failure", host=host)
        if host in ACTIVE_HOSTS:
            ACTIVE_HOSTS.remove(host)
            apply_host_scope()
            append_status('interception_disabled_after_tls_failure', host=host)


def request(flow: http.HTTPFlow):
    """Serve only the public research CA at the proxy's own explicit HTTP URL."""
    from mitmproxy import ctx
    if (flow.request.method == 'GET' and flow.request.scheme == 'http'
            and flow.request.host == ctx.options.listen_host
            and flow.request.port == ctx.options.listen_port
            and flow.request.path == '/air-research.cer'):
        public_cert = Path(ctx.options.confdir) / 'mitmproxy-ca-cert.cer'
        flow.response = http.Response.make(200, public_cert.read_bytes(), {
            'Content-Type': 'application/x-x509-ca-cert',
            'Content-Disposition': 'attachment; filename="Air-Research-Temporary.cer"',
        })
        append_status('public_certificate_download')
        setup_trigger = ROOT / 'read-keys-on-certificate-download'
        if setup_trigger.exists():
            setup_trigger.unlink()
            if not (ROOT / 'read-keys-consumed').exists():
                fd = os.open(ROOT / 'read-keys-once',
                             os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
                with os.fdopen(fd, 'w') as output:
                    output.write(str(time.time() + 600))
                append_status('cloud_read_armed_after_certificate_download')

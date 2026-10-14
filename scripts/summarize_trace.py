#!/usr/bin/env python3
"""Offline metadata-only decoder for a selected PacketLogger connection.

Input: packetlogger convert --format imtphsfr. No device or network access.
Reassembles uncompressed IPv4 Gattlink streams; reports gaps instead of
inventing payloads. Deliberately excludes payload bytes and device identifiers.
"""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import struct


def checksum_ok(header):
    if len(header) % 2:
        return False
    total = sum(struct.unpack('!' + 'H' * (len(header) // 2), header))
    while total >> 16:
        total = (total & 0xffff) + (total >> 16)
    return total == 0xffff


class Stream:
    def __init__(self, record_observer=None):
        self.buffer = bytearray()
        self.expected = None
        self.last = None
        self.counts = Counter()
        self.records = Counter()
        self.versions = Counter()
        self.handshakes = Counter()
        self.hello_metadata = []
        self.record_observer = record_observer

    def feed(self, packet):
        if not packet:
            self.counts['empty_packets'] += 1
            return
        if packet[0] & 0x80:
            self.counts['control_packets'] += 1
            self.buffer.clear()
            self.expected = None
            self.last = None
            return
        offset = 1 if packet[0] & 0x40 else 0
        if len(packet) == offset:
            self.counts['ack_only_packets'] += 1
            return
        if len(packet) <= offset + 1:
            self.counts['malformed_data_packets'] += 1
            return
        seq, payload = packet[offset] & 0x1f, packet[offset + 1:]
        if self.last == (seq, payload):
            self.counts['immediate_retransmissions'] += 1
            return
        if self.expected is not None and seq != self.expected:
            self.counts['sequence_discontinuities'] += 1
            self.buffer.clear()
        self.expected = (seq + 1) & 0x1f
        self.last = (seq, payload)
        self.buffer.extend(payload)
        self.counts['data_fragments'] += 1
        self.drain()

    def drain(self):
        while len(self.buffer) >= 20:
            b = self.buffer
            ihl = (b[0] & 15) * 4
            # This implementation supports uncompressed IPv4 only.
            if b[0] >> 4 != 4 or ihl < 20 or ihl > 60:
                self.counts['discarded_unsynchronized_bytes'] += 1
                del b[0]
                continue
            if len(b) < ihl:
                return
            total = int.from_bytes(b[2:4], 'big')
            if total < ihl or not checksum_ok(b[:ihl]):
                self.counts['discarded_unsynchronized_bytes'] += 1
                del b[0]
                continue
            if len(b) < total:
                return
            frame = bytes(b[:total])
            del b[:total]
            self.counts['ipv4_datagrams'] += 1
            if frame[9] != 17 or int.from_bytes(frame[6:8], 'big') & 0x3fff:
                self.counts['unsupported_ip_protocol_or_fragment'] += 1
                continue
            udp = frame[ihl:]
            if len(udp) < 8 or int.from_bytes(udp[4:6], 'big') != len(udp):
                self.counts['invalid_udp_length'] += 1
                continue
            src, dst = struct.unpack('!HH', udp[:4])
            data = udp[8:]
            offset = 0
            while offset < len(data):
                if len(data) - offset < 13:
                    self.counts['incomplete_or_non_dtls_record'] += 1
                    break
                h = data[offset:offset + 13]
                size = int.from_bytes(h[11:13], 'big')
                if h[1:3] not in (b'\xfe\xfd', b'\xfe\xff') or h[0] not in (20, 21, 22, 23) or offset + 13 + size > len(data):
                    self.counts['incomplete_or_non_dtls_record'] += 1
                    break
                epoch = int.from_bytes(h[3:5], 'big')
                self.versions[h[1:3].hex()] += 1
                if h[1:3] == b'\xfe\xfd':
                    self.records[(src, dst, h[0], epoch)] += 1
                if h[0] == 22 and epoch == 0:
                    self.observe_handshake(data[offset + 13:offset + 13 + size])
                if self.record_observer is not None:
                    self.record_observer(bytes(data[offset:offset + 13 + size]))
                offset += 13 + size

    def observe_handshake(self, data):
        # RFC 6347 section 4.2.2. Only complete plaintext messages are parsed;
        # fragment metadata is counted, never guessed or treated as plaintext.
        while data:
            if len(data) < 12:
                self.counts['invalid_handshake_fragment'] += 1
                return
            kind = data[0]
            length = int.from_bytes(data[1:4], 'big')
            offset = int.from_bytes(data[6:9], 'big')
            size = int.from_bytes(data[9:12], 'big')
            if offset + size > length or 12 + size > len(data):
                self.counts['invalid_handshake_fragment'] += 1
                return
            body, data = data[12:12 + size], data[12 + size:]
            self.handshakes[kind] += 1
            if offset != 0 or size != length:
                self.counts['fragmented_handshake_messages'] += 1
                continue
            if kind in (1, 2):
                try:
                    result = hello_metadata(kind, body)
                except ValueError:
                    self.counts['invalid_hello'] += 1
                else:
                    if result not in self.hello_metadata:
                        self.hello_metadata.append(result)

    def summary(self):
        return {'counts': dict(self.counts), 'trailing_bytes': len(self.buffer),
                'record_versions': dict(self.versions),
                'plaintext_handshake_fragments': dict(self.handshakes),
                'hello_metadata': self.hello_metadata,
                'dtls12_records': [dict(source_port=s, destination_port=d,
                                       content_type=t, epoch=e, count=n)
                                   for (s, d, t, e), n in sorted(self.records.items())]}


def hello_metadata(kind, body):
    """Expose cipher/version choices only, never randoms, identities or cookies."""
    pos = 0
    def take(n):
        nonlocal pos
        if pos + n > len(body):
            raise ValueError('truncated hello')
        value = body[pos:pos + n]
        pos += n
        return value
    version = take(2).hex()
    if version not in ('fefd', 'feff'):
        raise ValueError('unknown DTLS version')
    take(32)  # random
    sid_length = take(1)[0]
    if sid_length > 32:
        raise ValueError('oversized session id')
    take(sid_length)
    result = {'role': 'client' if kind == 1 else 'server', 'version': version}
    if kind == 1:
        take(take(1)[0])  # DTLS cookie
        size = int.from_bytes(take(2), 'big')
        if not size or size % 2:
            raise ValueError('invalid cipher list')
        ciphers = take(size)
        result['offered_cipher_suites'] = [ciphers[i:i + 2].hex() for i in range(0, size, 2)]
        size = take(1)[0]
        if not size:
            raise ValueError('missing compression methods')
        take(size)
    else:
        result['selected_cipher_suite'] = take(2).hex()
        result['compression_method'] = take(1)[0]
    extensions = []
    if pos < len(body):
        end = pos + 2 + int.from_bytes(take(2), 'big')
        if end != len(body):
            raise ValueError('invalid extension block')
        while pos < end:
            extension = int.from_bytes(take(2), 'big')
            take(int.from_bytes(take(2), 'big'))
            if extension in extensions:
                raise ValueError('duplicate extension')
            extensions.append(extension)
    result['extension_types'] = extensions
    return result


def summarize(path, connection, tx_handle, rx_handle):
    streams = {'phone_to_band': Stream(), 'band_to_phone': Stream()}
    ignored = 0
    for line in path.read_text().splitlines():
        columns = line.rstrip('\n').split('\t')
        if len(columns) < 7 or columns[2].lower() != connection.lower():
            continue
        kind = columns[1]
        if kind not in ('ATT Send', 'ATT Receive'):
            continue
        try:
            raw = bytes.fromhex(columns[5])
        except ValueError:
            ignored += 1
            continue
        # Strictly accept complete ACL + L2CAP ATT frames. No HCI fragment guessing.
        if (len(raw) < 11 or int.from_bytes(raw[2:4], 'little') != len(raw) - 4
                or int.from_bytes(raw[4:6], 'little') != len(raw) - 8
                or raw[6:8] != b'\x04\x00'):
            ignored += 1
            continue
        attribute = int.from_bytes(raw[9:11], 'little')
        if kind == 'ATT Send' and raw[8] == 0x52 and attribute == tx_handle:
            streams['phone_to_band'].feed(raw[11:])
        elif kind == 'ATT Receive' and raw[8] == 0x1b and attribute == rx_handle:
            streams['band_to_phone'].feed(raw[11:])
    return {'schema_version': 1, 'input_sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
            'mode': 'offline_metadata_only', 'unsupported_att_frames': ignored,
            'streams': {k: v.summary() for k, v in streams.items()},
            'limitations': ['No decryption or CoAP/command identification.',
                            'Only uncompressed IPv4 is decoded; gaps discard partial data.',
                            'Only immediate identical retransmissions are deduplicated.',
                            'Attribute handles must come from this specific capture.']}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('input', type=Path)
    parser.add_argument('--connection', required=True)
    parser.add_argument('--tx-handle', required=True, type=lambda x: int(x, 0))
    parser.add_argument('--rx-handle', required=True, type=lambda x: int(x, 0))
    args = parser.parse_args()
    print(json.dumps(summarize(args.input, args.connection, args.tx_handle, args.rx_handle), indent=2))

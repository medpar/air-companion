import importlib.util
from pathlib import Path
import struct
import unittest

spec = importlib.util.spec_from_file_location('trace', Path(__file__).parents[1] / 'scripts/summarize_trace.py')
trace = importlib.util.module_from_spec(spec)
spec.loader.exec_module(trace)


def frame(payload=b'ciphertext', prefix=b'\x17\xfe\xfd\x00\x01'):
    dtls = prefix + (8).to_bytes(6, 'big') + len(payload).to_bytes(2, 'big') + payload
    udp = struct.pack('!HHHH', 5684, 5684, 8 + len(dtls), 0) + dtls
    ip = bytearray(struct.pack('!BBHHHBBH4s4s', 0x45, 0, 20 + len(udp), 1, 0, 64, 17, 0,
                               bytes([169, 254, 0, 2]), bytes([169, 254, 0, 3])))
    total = sum(struct.unpack('!10H', ip))
    while total >> 16: total = (total & 65535) + (total >> 16)
    ip[10:12] = ((~total) & 65535).to_bytes(2, 'big')
    return bytes(ip) + udp


class TraceTests(unittest.TestCase):
    def test_fragmentation_ack_and_sequence_wrap(self):
        s = trace.Stream(); f = frame()
        s.feed(bytes([31]) + f[:25]); s.feed(b'\x5f')
        s.feed(bytes([0x40, 0]) + f[25:])
        self.assertEqual(sum(s.records.values()), 1)
        self.assertEqual(s.counts['sequence_discontinuities'], 0)

    def test_retransmission_not_double_counted(self):
        s = trace.Stream(); packet = b'\x01' + frame()
        s.feed(packet); s.feed(packet)
        self.assertEqual(sum(s.records.values()), 1)
        self.assertEqual(s.counts['immediate_retransmissions'], 1)

    def test_missing_fragment_is_not_decoded(self):
        s = trace.Stream(); f = frame()
        s.feed(b'\x01' + f[:25]); s.feed(b'\x03' + f[30:])
        self.assertFalse(s.records)
        s.feed(b'\x04' + f)
        self.assertEqual(sum(s.records.values()), 1)
        self.assertEqual(s.counts['sequence_discontinuities'], 1)

    def test_bad_checksum_and_truncated_record_rejected(self):
        s = trace.Stream(); f = bytearray(frame()); f[10] ^= 1
        s.feed(b'\x01' + f)
        self.assertFalse(s.records)
        s = trace.Stream(); s.feed(b'\x01' + frame()[:-1])
        self.assertFalse(s.records)

    def test_concatenated_datagrams_and_reset(self):
        s = trace.Stream(); s.feed(b'\x01' + frame() + frame())
        self.assertEqual(sum(s.records.values()), 2)
        s.feed(b'\x02' + frame()[:22]); s.feed(b'\x80'); s.feed(b'\x00' + frame())
        self.assertEqual(sum(s.records.values()), 3)

    def test_summary_contains_no_payload(self):
        s = trace.Stream(); s.feed(b'\x01' + frame(b'private-health-payload'))
        self.assertNotIn('private-health', str(s.summary()))

    def test_dtls10_record_clienthello_and_server_cipher(self):
        random = b'private-random-material'.ljust(32, b'x')
        client = b'\xfe\xfd' + random + b'\x00\x00\x00\x04\xc0\xa4\x00\xa8\x01\x00'
        server = b'\xfe\xfd' + random + b'\x00\xc0\xa4\x00\x00\x04\x00\x17\x00\x00'
        s = trace.Stream()
        for seq, kind, body, version in ((0, 1, client, b'\xfe\xff'), (1, 2, server, b'\xfe\xfd')):
            message = bytes([kind]) + len(body).to_bytes(3, 'big') + b'\x00\x00\x00\x00\x00' + len(body).to_bytes(3, 'big') + body
            s.feed(bytes([seq]) + frame(message, b'\x16' + version + b'\x00\x00'))
        self.assertEqual(s.hello_metadata[0]['offered_cipher_suites'], ['c0a4', '00a8'])
        self.assertEqual(s.hello_metadata[1]['selected_cipher_suite'], 'c0a4')
        self.assertEqual(s.hello_metadata[1]['extension_types'], [23])
        self.assertEqual(s.versions, {'feff': 1, 'fefd': 1})
        self.assertNotIn('private-random', str(s.summary()))

    def test_encrypted_handshake_is_not_parsed(self):
        s = trace.Stream()
        s.feed(b'\x00' + frame(b'private-encrypted-finished', b'\x16\xfe\xfd\x00\x01'))
        self.assertFalse(s.handshakes)
        self.assertFalse(s.hello_metadata)

    def test_fragment_and_malformed_hello_are_not_invented(self):
        s = trace.Stream()
        s.observe_handshake(b'\x02\x00\x00\x30\x00\x00\x00\x00\x01\x00\x00\x01x')
        self.assertEqual(s.counts['fragmented_handshake_messages'], 1)
        s.observe_handshake(b'\x02\x00\x00\x01\x00\x00\x00\x00\x00\x00\x00\x01x')
        self.assertEqual(s.counts['invalid_hello'], 1)
        self.assertFalse(s.hello_metadata)

    def test_invalid_extension_lengths_rejected(self):
        server = b'\xfe\xfd' + bytes(32) + b'\x00\xc0\xa4\x00'
        for suffix in (b'\x00', b'\x00\x04\x00\x17\x00\x01', b'\x00\x00extra'):
            with self.assertRaises(ValueError): trace.hello_metadata(2, server + suffix)


if __name__ == '__main__': unittest.main()

# Native dependencies

This project's own code is MIT-licensed (see [`LICENSE`](../LICENSE)). The
dependencies below keep their own Apache-2.0 licenses, and
[`patches/golden-gate-nip-cleanup.patch`](patches/golden-gate-nip-cleanup.patch),
a modification of Golden Gate, is distributed under Apache-2.0.

The build fetches source into ignored `.private/references`. It does not bundle
device keys, research captures, or proprietary app code.

* [Golden Gate](https://github.com/Google-Health-API/golden-gate), commit
  `b8a6f2552e12aaf92c1549dc88a41c9b7e73f1aa`, Apache-2.0. Its `LICENSE` and
  `NOTICE` must accompany any distribution containing its code. The local patch
  frees the NIP interface wrapper during stack teardown.
* [Mbed TLS 3.6.7](https://github.com/Mbed-TLS/mbedtls/releases/tag/mbedtls-3.6.7),
  used under Apache-2.0. Preserve its `LICENSE` in binary distributions.
  Source archive SHA-256:
  `a7e8bcbec0e6f761b4af24f25677626b35f762f68eef79c08677a363212d11f6`.

Golden Gate's CMake configuration uses Mbed TLS for DTLS, NIP for IPv4/UDP,
and Gattlink for Bluetooth fragmentation. This project replaces Golden Gate's
standard-library random source with Apple's `SecRandomCopyBytes`.

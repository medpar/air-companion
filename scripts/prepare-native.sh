#!/bin/sh
# Fetch only public source. Never reads device credentials or starts Bluetooth.
set -eu
cd "$(dirname "$0")/.."
root="$PWD"
refs="$root/.private/references"
gg="$refs/golden-gate"
revision=b8a6f2552e12aaf92c1549dc88a41c9b7e73f1aa
archive="$refs/mbedtls-3.6.7.tar.bz2"
digest=a7e8bcbec0e6f761b4af24f25677626b35f762f68eef79c08677a363212d11f6
mkdir -p "$refs"
if [ ! -d "$gg" ]; then
    git init -q "$gg"
    git -C "$gg" remote add origin https://github.com/Google-Health-API/golden-gate.git
    git -C "$gg" fetch --depth 1 origin "$revision"
    git -C "$gg" checkout --detach FETCH_HEAD
fi
[ "$(git -C "$gg" rev-parse HEAD)" = "$revision" ] || {
    echo 'Golden Gate revision differs; leaving existing checkout untouched.' >&2; exit 1;
}
if [ ! -f "$archive" ]; then
    curl --fail --location --proto '=https' --tlsv1.2 \
        https://github.com/Mbed-TLS/mbedtls/releases/download/mbedtls-3.6.7/mbedtls-3.6.7.tar.bz2 \
        --output "$archive.download"
    [ "$(shasum -a 256 "$archive.download" | cut -d ' ' -f 1)" = "$digest" ] || {
        echo 'Mbed TLS checksum mismatch.' >&2; exit 1;
    }
    mv "$archive.download" "$archive"
fi
[ "$(shasum -a 256 "$archive" | cut -d ' ' -f 1)" = "$digest" ] || {
    echo 'Mbed TLS checksum mismatch.' >&2; exit 1;
}
if [ ! -d "$refs/mbedtls-3.6.7" ]; then tar -xjf "$archive" -C "$refs"; fi
link="$gg/external/mbedtls-3"
if [ -d "$link" ] && [ ! -L "$link" ]; then rmdir "$link"; fi
if [ ! -e "$link" ]; then ln -s ../../mbedtls-3.6.7 "$link"; fi
[ "$(readlink "$link")" = ../../mbedtls-3.6.7 ] || {
    echo 'Unexpected Mbed TLS source path; leaving it untouched.' >&2; exit 1;
}
patch="$root/Native/patches/golden-gate-nip-cleanup.patch"
if git -C "$gg" apply --reverse --check "$patch" 2>/dev/null; then :
else git -C "$gg" apply --check "$patch"; git -C "$gg" apply "$patch"; fi
echo 'Pinned native dependencies ready.'

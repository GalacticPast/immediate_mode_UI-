#!/bin/sh
# Use Odin's shipped bindings. Some Linux distributions omit the static archive.
set -eu
vendor_dir="$(odin root)/vendor"
pkg="$vendor_dir/kb_text_shape"
if [ -f "$pkg/lib/kb_text_shape.a" ]; then
    echo "$vendor_dir"
    exit 0
fi

cache="$1/kb_text_shape"
mkdir -p "$cache/lib"
for binding in "$pkg"/*.odin; do
    dest="$cache/${binding##*/}"
    if [ -L "$dest" ] || [ ! -f "$dest" ] || ! cmp -s "$binding" "$dest"; then
        cp "$binding" "$dest.$$"
        mv -f "$dest.$$" "$dest"
    fi
done
archive="$cache/lib/kb_text_shape.a"
if [ ! -f "$archive" ] || [ "$pkg/src/kb_text_shape.h" -nt "$archive" ] || [ "$pkg/src/kb_text_shape.c" -nt "$archive" ]; then
    scratch=$(mktemp -d "$cache/build.XXXXXXXX")
    trap 'rm -rf "$scratch"' EXIT
    "${CC:-cc}" -O2 -fPIC -c "$pkg/src/kb_text_shape.c" -o "$scratch/kb.o"
    "${AR:-ar}" rcs "$scratch/kb.a" "$scratch/kb.o"
    mv "$scratch/kb.a" "$archive"
fi
echo "$1"

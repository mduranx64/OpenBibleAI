#!/bin/sh
# Compiles catalog_key.swift when it changed (CryptoKit needs a compiled
# binary, not the interpreter) and runs it with the given arguments.
set -e
here=$(cd "$(dirname "$0")" && pwd)
binary="$here/.build/catalog_key"
if [ ! -x "$binary" ] || [ "$here/catalog_key.swift" -nt "$binary" ]; then
  mkdir -p "$here/.build"
  xcrun swiftc -O "$here/catalog_key.swift" -o "$binary"
fi
exec "$binary" "$@"

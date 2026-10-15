#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-14.0}"

echo "Compilando el motor Rust…"
(cd rust-core && cargo build --release)

echo "Compilando la app…"
SDK="$(xcrun --show-sdk-path --sdk macosx)"
swift build -c debug -Xswiftc -sdk -Xswiftc "$SDK"

BIN=".build/debug/DynamicIsland"
if [ ! -f "$BIN" ]; then
  BIN="$(find .build -type f -name DynamicIsland -path '*debug*' | head -n 1)"
fi
if [ -z "${BIN}" ] || [ ! -f "$BIN" ]; then
  echo "No se encontró el binario."
  exit 1
fi

APP="Dynamic Island.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/DynamicIsland"
cp Sources/DynamicIsland/Info.plist "$APP/Contents/Info.plist"
chmod +x "$APP/Contents/MacOS/DynamicIsland"
codesign --force --sign - --identifier com.uribe.DynamicIsland "$APP"

echo "Abriendo Dynamic Island."
echo "Tres veces Comando abren la isla junto al puntero."
open "$APP"

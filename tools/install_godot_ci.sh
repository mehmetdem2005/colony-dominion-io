#!/usr/bin/env bash
set -euo pipefail
VERSION="${GODOT_VERSION:-4.6.3}"
CHANNEL="stable"
BIN_DIR="${GODOT_BIN_DIR:-$PWD/.godot-bin}"
TEMPLATE_DIR="${HOME}/.local/share/godot/export_templates/${VERSION}.${CHANNEL}"
EDITOR_ZIP="Godot_v${VERSION}-${CHANNEL}_linux.x86_64.zip"
TEMPLATE_TPZ="Godot_v${VERSION}-${CHANNEL}_export_templates.tpz"
BASE="https://github.com/godotengine/godot-builds/releases/download/${VERSION}-${CHANNEL}"
mkdir -p "$BIN_DIR" "$TEMPLATE_DIR"
curl -fL --retry 4 --retry-all-errors -o /tmp/godot-editor.zip "$BASE/$EDITOR_ZIP"
unzip -q -o /tmp/godot-editor.zip -d "$BIN_DIR"
mv "$BIN_DIR/Godot_v${VERSION}-${CHANNEL}_linux.x86_64" "$BIN_DIR/godot"
chmod +x "$BIN_DIR/godot"
curl -fL --retry 4 --retry-all-errors -o /tmp/godot-templates.tpz "$BASE/$TEMPLATE_TPZ"
rm -rf /tmp/godot-template-unpack && mkdir /tmp/godot-template-unpack
unzip -q /tmp/godot-templates.tpz -d /tmp/godot-template-unpack
cp -a /tmp/godot-template-unpack/templates/. "$TEMPLATE_DIR/"
"$BIN_DIR/godot" --version
test -f "$TEMPLATE_DIR/linux_release.x86_64"
echo "GODOT_CI_INSTALL_OK"

#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
: "${GODOT_VERSION:?GODOT_VERSION is required}"
: "${ANDROID_SDK_ROOT:?ANDROID_SDK_ROOT is required}"

PLUGIN_ROOT="$PROJECT_ROOT/android_plugins/colony_google_identity"
TEMPLATE_DIR="$HOME/.local/share/godot/export_templates/${GODOT_VERSION}.stable"

command -v gradle >/dev/null 2>&1 || {
  echo "Gradle is required to build ColonyGoogleIdentity" >&2
  exit 2
}
test -f "$TEMPLATE_DIR/android_source.zip"

gradle --project-dir "$PLUGIN_ROOT" --no-daemon --stacktrace assembleRelease
mapfile -t PLUGIN_AARS < <(
  find "$PLUGIN_ROOT/build/outputs/aar" -maxdepth 1 -type f -name '*-release.aar' -print
)
if [ "${#PLUGIN_AARS[@]}" -ne 1 ]; then
  echo "Expected exactly one release AAR, found ${#PLUGIN_AARS[@]}" >&2
  exit 3
fi
PLUGIN_AAR="${PLUGIN_AARS[0]}"
test -s "$PLUGIN_AAR"
install -D -m 0644 "$PLUGIN_AAR" "$PROJECT_ROOT/android/plugins/ColonyGoogleIdentity.aar"

rm -rf "$PROJECT_ROOT/android/build"
mkdir -p "$PROJECT_ROOT/android/build"
unzip -q "$TEMPLATE_DIR/android_source.zip" -d "$PROJECT_ROOT/android/build"
# The Gradle template lives under the Godot project root. Without this marker,
# a preceding editor-settings pass imports template resources into the game and
# leaves invalid *.import files inside Android's res/ directories.
touch "$PROJECT_ROOT/android/build/.gdignore"
printf '%s.stable\n' "$GODOT_VERSION" > "$PROJECT_ROOT/android/.build_version"
printf 'sdk.dir=%s\n' "$ANDROID_SDK_ROOT" > "$PROJECT_ROOT/android/build/local.properties"
chmod +x "$PROJECT_ROOT/android/build/gradlew"

echo "COLONY_NATIVE_ANDROID_BUILD_READY"

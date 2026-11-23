#!/usr/bin/env bash
# Common project tasks.
#   tools/build.sh import       - import assets (first run / after asset changes)
#   tools/build.sh test [suites] - headless tests: physics track ai routes
#   tools/build.sh shots         - rendered screenshots (Xvfb + lavapipe Vulkan)
#   tools/build.sh apk           - export the Android debug APK to export/
#   tools/build.sh zip           - zip the project (without .godot cache) to export/
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-$HOME/tools/godot}"
[ -x "$GODOT" ] || GODOT="/home/user/tools/godot"
cd "$ROOT"
mkdir -p export

case "${1:-}" in
  import)
    "$GODOT" --headless --path . --import ;;
  test)
    shift
    "$GODOT" --headless --path . --fixed-fps 60 res://tests/test_main.tscn -- "$@" ;;
  shots)
    export VK_ICD_FILENAMES=/opt/lavapipe/lvp_icd.json
    xvfb-run -a -s "-screen 0 1600x720x24" "$GODOT" --path . --rendering-driver vulkan --resolution 1600x720 res://tests/screenshots.tscn ;;
  apk)
    export GODOT_ANDROID_KEYSTORE_DEBUG_PATH="${GODOT_ANDROID_KEYSTORE_DEBUG_PATH:-$(dirname "$GODOT")/debug.keystore}"
    export GODOT_ANDROID_KEYSTORE_DEBUG_USER=androiddebugkey
    export GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD=android
    "$GODOT" --headless --path . --export-debug "Android" export/WildsparkKart.apk
    ls -la export/WildsparkKart.apk ;;
  zip)
    rm -f export/WildsparkKart_project.zip
    git ls-files -z | xargs -0 zip -q export/WildsparkKart_project.zip
    ls -la export/WildsparkKart_project.zip ;;
  *)
    sed -n '2,8p' "$0" ;;
esac

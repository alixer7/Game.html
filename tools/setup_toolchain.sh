#!/usr/bin/env bash
# Sets up everything needed to run tests and export the Android APK (Linux x86_64).
#   tools/setup_toolchain.sh [install_dir]      (default: $HOME/tools)
# Downloads the OFFICIAL Godot 4.7.2-stable editor + export templates from the
# godotengine/godot GitHub release, verifies SHA-512 against the release's own
# checksum file, installs Android SDK build-tools/platform-tools, and creates a
# debug keystore. Requires network access to github.com + dl.google.com.
set -euo pipefail
VER="4.7.2-stable"
DIR="${1:-$HOME/tools}"
BASE="https://github.com/godotengine/godot/releases/download/${VER}"
mkdir -p "$DIR" && cd "$DIR"

fetch() { curl -fL --retry 4 --retry-delay 3 -o "$2" "$1"; }

if [ ! -x "$DIR/godot" ]; then
  fetch "$BASE/SHA512-SUMS.txt" SHA512-SUMS.txt
  fetch "$BASE/Godot_v${VER}_linux.x86_64.zip" godot.zip
  grep "Godot_v${VER}_linux.x86_64.zip" SHA512-SUMS.txt | awk '{print $1"  godot.zip"}' | sha512sum -c -
  unzip -o -q godot.zip && mv "Godot_v${VER}_linux.x86_64" godot && chmod +x godot && rm godot.zip
fi
TPL_DIR="$HOME/.local/share/godot/export_templates/${VER/-/.}"
if [ ! -f "$TPL_DIR/android_release.apk" ]; then
  [ -f SHA512-SUMS.txt ] || fetch "$BASE/SHA512-SUMS.txt" SHA512-SUMS.txt
  fetch "$BASE/Godot_v${VER}_export_templates.tpz" templates.tpz
  grep "Godot_v${VER}_export_templates.tpz" SHA512-SUMS.txt | awk '{print $1"  templates.tpz"}' | sha512sum -c -
  mkdir -p "$TPL_DIR" && unzip -o -q templates.tpz -d tpl_tmp && cp -r tpl_tmp/templates/* "$TPL_DIR/" && rm -rf tpl_tmp templates.tpz
fi

export ANDROID_HOME="$DIR/android-sdk"
if [ ! -d "$ANDROID_HOME/build-tools/35.0.1" ]; then
  mkdir -p "$ANDROID_HOME/cmdline-tools"
  fetch https://dl.google.com/android/repository/commandlinetools-linux-16111833_latest.zip cmdline.zip
  unzip -q -o cmdline.zip -d "$ANDROID_HOME/cmdline-tools" && rm cmdline.zip
  mv "$ANDROID_HOME/cmdline-tools/cmdline-tools" "$ANDROID_HOME/cmdline-tools/latest" 2>/dev/null || true
  yes | "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" --sdk_root="$ANDROID_HOME" --licenses >/dev/null || true
  "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" --sdk_root="$ANDROID_HOME" "platform-tools" "build-tools;35.0.1" "platforms;android-35"
fi

KS="$DIR/debug.keystore"
if [ ! -f "$KS" ]; then
  keytool -genkeypair -v -keystore "$KS" -storepass android -alias androiddebugkey -keypass android \
    -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Android Debug,O=Android,C=US"
fi

# Godot editor settings: SDK + Java paths, debug keystore
JAVA_HOME_GUESS="$(dirname "$(dirname "$(readlink -f "$(which javac)")")")"
CFG="$HOME/.config/godot"
mkdir -p "$CFG"
ES="$CFG/editor_settings-4.7.tres"
if [ ! -f "$ES" ]; then
  cat > "$ES" <<EOF
[gd_resource type="EditorSettings" format=3]

[resource]
export/android/android_sdk_path = "$ANDROID_HOME"
export/android/java_sdk_path = "$JAVA_HOME_GUESS"
export/android/debug_keystore = "$KS"
export/android/debug_keystore_user = "androiddebugkey"
export/android/debug_keystore_pass = "android"
EOF
fi
echo "Toolchain ready: $DIR/godot  (templates: $TPL_DIR, SDK: $ANDROID_HOME)"

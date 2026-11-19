#!/bin/bash
# Parse-checks every GDScript file with the Godot binary given in $GODOT.
cd "$(dirname "$0")/.."
fail=0
for f in $(find scripts -name "*.gd"); do
  out=$("$GODOT" --headless --path . --check-only --script "res://$f" 2>&1 | grep -E "SCRIPT ERROR|Parse Error|error\(" | grep -v "ALSA" | grep -v "Identifier not found: Game" | grep -v "Failed to compile depended")
  if [ -n "$out" ]; then echo "== $f"; echo "$out" | head -8; fail=1; fi
done
exit $fail

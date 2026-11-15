#!/bin/bash
# تشغيل اللعبة بنافذة افتراضية لالتقاط لقطات: tools/shot.sh WxH -- args...
RES=$1; shift
xvfb-run -a -s "-screen 0 ${RES}x24" timeout ${TMO:-240} /home/claude/tools_bin/godot --path . --rendering-driver opengl3 --resolution $RES --fixed-fps 60 "$@" 2>&1 | grep -E "SCRIPT|ERROR: [^CI]|at: [a-zA-Z_]+ \(res|saved|PLAY|fingerbot" | grep -v "gl_manager\|alsa\|audio_server" | head -${LINES_MAX:-12}

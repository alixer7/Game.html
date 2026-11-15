#!/bin/bash
# اختبار حركة: tools/anim.sh name n dt cam cols [WxH]
NAME=$1; N=$2; DT=$3; CAM=$4; COLS=$5; RES=${6:-520x420}
rm -f /tmp/shots/anim_${NAME%%:*}_*
xvfb-run -a -s "-screen 0 ${RES}x24" timeout ${TMO:-400} /home/claude/tools_bin/godot --path . --rendering-driver opengl3 --resolution $RES --fixed-fps 60 -- --anim=$NAME --animn=$N --animdt=$DT --animcam=$CAM 2>&1 | grep -E "ANIM|SCRIPT ERROR|at: [a-zA-Z_]+ \(res" | head -8
python3 tools/sheet.py ${NAME%%:*} $COLS

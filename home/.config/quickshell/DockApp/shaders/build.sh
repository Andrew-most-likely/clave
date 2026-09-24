#!/bin/sh
# Recompile the genie shaders after editing genie.vert / genie.frag.
cd "$(dirname "$0")"
for s in genie.vert genie.frag; do
    /usr/lib/qt6/bin/qsb --qt6 -o "$s.qsb" "$s" || exit 1
done

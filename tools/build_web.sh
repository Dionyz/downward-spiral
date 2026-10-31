#!/usr/bin/env bash
# Build the Godot web export template from source (single-threaded, 2D-only, size-optimized),
# then export Downward Spiral to build/web/. Needs: Godot source at $GODOT_SRC, emsdk 4.0.11
# activated (source emsdk_env.sh), and the Godot editor binary as $GODOT.
#
#   GODOT_SRC=~/tools-src/godot GODOT=~/bin/godot ./tools/build_web.sh
set -euo pipefail
cd "$(dirname "$0")/.."
: "${GODOT_SRC:?set GODOT_SRC to the Godot 4.7.2 source checkout}"
: "${GODOT:=godot}"
VER="4.7.2.stable"
TPL="$HOME/.local/share/godot/export_templates/$VER"

( cd "$GODOT_SRC" && scons platform=web target=template_release threads=no \
	optimize=size disable_3d=yes lto=full \
	module_text_server_adv_enabled=no module_text_server_fb_enabled=yes \
	module_openxr_enabled=no module_webrtc_enabled=no module_websocket_enabled=no \
	module_multiplayer_enabled=no module_navigation_2d_enabled=no module_navigation_3d_enabled=no \
	module_jolt_physics_enabled=no module_godot_physics_3d_enabled=no module_csg_enabled=no \
	module_gridmap_enabled=no module_basis_universal_enabled=no module_theora_enabled=no -j"$(nproc)" )

mkdir -p "$TPL"
cp "$GODOT_SRC/bin/godot.web.template_release.wasm32.nothreads.zip" "$TPL/web_nothreads_release.zip"
cp "$GODOT_SRC/bin/godot.web.template_release.wasm32.nothreads.zip" "$TPL/web_nothreads_debug.zip"

mkdir -p build/web
"$GODOT" --headless --path . --export-release "Web" build/web/index.html
ls -la build/web

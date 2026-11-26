# Fake extracted AppImage whose AppRun reports what the real client would see.
{ runCommand }:
runCommand "fake-phoenix-appimage" { } ''
    mkdir -p $out/usr/share/icons/hicolor/64x64/apps
    touch $out/usr/share/icons/hicolor/64x64/apps/com.discord.libdiscord.png
    cat > $out/AppRun <<'SH'
  #!/bin/sh
  echo "LD_PRELOAD=$LD_PRELOAD"
  echo "SUNBIRD_GATE_ONLY=''${SUNBIRD_GATE_ONLY:-}"
  echo "SUNBIRD_PRELOAD=''${SUNBIRD_PRELOAD:-}"
  echo "args=$*"
  for c in curl python3 zenity kdialog wl-copy xclip notify-send xdg-open; do command -v $c >/dev/null && echo "have $c" || echo "MISSING $c"; done
  ls /usr/lib/libcurl.so.4 /usr/lib/libgcc_s.so.1 2>&1
  python3 -I -c 'import gi; gi.require_version("Gtk","3.0"); gi.require_version("AyatanaAppIndicator3","0.1"); from gi.repository import Gtk, AyatanaAppIndicator3; print("tray deps ok")' 2>&1 | tail -1
  SH
    chmod +x $out/AppRun
''

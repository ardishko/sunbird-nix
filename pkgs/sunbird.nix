{
  lib,
  symlinkJoin,
  writeShellScriptBin,
  makeDesktopItem,
  phoenix,
  sunbird-loader,
  # "pinned": preload the loader from the Nix store (reproducible, no self-update).
  # "mutable": behave like upstream's launcher and keep a self-updating copy in
  #            $XDG_DATA_HOME/sunbird, falling back to the pinned one when offline.
  loaderMode ? "pinned",
  site ? "https://assets.sunbird.tools",
  curl,
  gnused,
  coreutils,
}:

assert lib.assertOneOf "loaderMode" loaderMode [
  "pinned"
  "mutable"
];

let
  phoenixExe = lib.getExe phoenix;
  # Absolute path: works in every launcher, no icon-theme lookup involved.
  iconPath = "${phoenix}/share/icons/hicolor/512x512/apps/com.discord.libdiscord.png";
  pinned = "${sunbird-loader}/lib/libphoenix.so";

  # Mirrors the update block of upstream's generated launcher.
  mutableFetch = ''
    home=''${XDG_DATA_HOME:-$HOME/.local/share}/sunbird
    mkdir -p "$home"
    fetch() { ${curl}/bin/curl -fsSL --proto =https --proto-redir =https "$@" 2>/dev/null; }
    version=$(fetch --max-time 5 "${site}/version.json" |
      ${gnused}/bin/sed -n 's/.*"loader": *"\([^"]*\)".*/\1/p')
    if [ -n "$version" ] && [ "$version" != "$(cat "$home/version" 2>/dev/null)" ]; then
      tmp=$(${coreutils}/bin/mktemp "$home/libphoenix.so.XXXXXX")
      if fetch --max-time 60 -o "$tmp" "${site}/plugins/libphoenix-linux-x86_64.so"; then
        mv "$tmp" "$home/libphoenix.so"
        echo "$version" >"$home/version"
      else
        rm -f "$tmp"
      fi
    fi
    loader=${pinned}
    [ -f "$home/libphoenix.so" ] && loader=$home/libphoenix.so
  '';

  launcher = writeShellScriptBin "sunbird" ''
    set -eu
    ${if loaderMode == "mutable" then mutableFetch else "loader=${pinned}"}
    [ "''${1:-}" = --update ] && exit 0
    while [ "''${1:-}" = --no-runtime ] || [ "''${1:-}" = --gate-only ]; do
      export SUNBIRD_GATE_ONLY=1
      shift
    done
    # Picked up by phoenix's FHS profile and turned into LD_PRELOAD there.
    export SUNBIRD_PRELOAD=$loader
    exec ${phoenixExe} "$@"
  '';

  gateOnly = writeShellScriptBin "sunbird-gate-only" ''
    exec ${launcher}/bin/sunbird --gate-only "$@"
  '';

  desktopItems = [
    (makeDesktopItem {
      name = "sunbird";
      desktopName = "Sunbird";
      comment = "Phoenix with Sunbird";
      exec = "sunbird %U";
      icon = iconPath;
      categories = [
        "Network"
        "InstantMessaging"
      ];
      mimeTypes = [ "x-scheme-handler/discord" ];
      startupWMClass = "com.discord.libdiscord";
    })
    (makeDesktopItem {
      name = "sunbird-gate-only";
      desktopName = "Sunbird (access gate only)";
      comment = "Phoenix past the access gate, without plugins";
      exec = "sunbird-gate-only %U";
      icon = iconPath;
      categories = [
        "Network"
        "InstantMessaging"
      ];
      startupWMClass = "com.discord.libdiscord";
    })
    # The client registers itself as the discord:// handler on every launch by
    # writing this exact file to ~/.local/share/applications, pointing at its
    # bare binary (no sandbox, no loader) and resetting mimeapps.list. If a file
    # it didn't write is already there, it leaves both alone. The modules link
    # this one into place; it routes links through Sunbird instead.
    (makeDesktopItem {
      name = "com.discord.libdiscord.url-handler";
      desktopName = "Sunbird";
      noDisplay = true;
      exec = "${launcher}/bin/sunbird --url -- %u";
      icon = iconPath;
      mimeTypes = [ "x-scheme-handler/discord" ];
    })
  ];
in
symlinkJoin {
  name = "sunbird-${sunbird-loader.version}";
  paths = [
    launcher
    gateOnly
    phoenix
  ]
  ++ desktopItems;
  # Hide the plain client's launcher entry; `phoenix` stays on PATH.
  postBuild = ''
    rm -f $out/share/applications/phoenix.desktop
  '';
  passthru = {
    inherit phoenix sunbird-loader loaderMode;
    # File name of the link-handler entry, for linking it into ~/.local/share/applications.
    urlHandler = "com.discord.libdiscord.url-handler.desktop";
  };
  meta = {
    description = "Phoenix started with the Sunbird loader preloaded";
    homepage = "https://sunbird.tools";
    license = lib.licenses.unfree;
    platforms = [ "x86_64-linux" ];
    mainProgram = "sunbird";
  };
}

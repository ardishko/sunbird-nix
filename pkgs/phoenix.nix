{
  lib,
  appimageTools,
  fetchurl,
  makeDesktopItem,
  sources,
  # Override with an already-extracted tree (used by tests, or a local AppImage).
  contentsOverride ? null,
}:

let
  pname = "phoenix";
  inherit (sources.phoenix) version;

  src = fetchurl {
    inherit (sources.phoenix) url hash;
    name = "phoenix-${version}.AppImage";
  };

  contents =
    if contentsOverride != null then
      contentsOverride
    else
      appimageTools.extract { inherit pname version src; };

  desktopItem = makeDesktopItem {
    name = "com.discord.libdiscord"; # matches the window's app id
    desktopName = "Phoenix";
    comment = "Phoenix desktop client (build ${version})";
    exec = "${pname} %U";
    icon = "${contents}/usr/share/icons/hicolor/512x512/apps/com.discord.libdiscord.png";
    categories = [
      "Network"
      "InstantMessaging"
    ];
    mimeTypes = [ "x-scheme-handler/discord" ];
    startupWMClass = "com.discord.libdiscord";
    startupNotify = true;
  };
in
appimageTools.wrapAppImage {
  inherit pname version contents;

  # Helpers the Sunbird loader shells out to or dlopens at runtime.
  # libcurl, zenity, gtk3 and xdg-utils already come with appimageTools.
  extraPkgs =
    pkgs: with pkgs; [
      (python3.withPackages (ps: [ ps.pygobject3 ])) # tray icon
      libayatana-appindicator
      gobject-introspection
      kdePackages.kdialog
      wl-clipboard
      xclip
      xsel
      libnotify
      libva # hardware video decode
      pipewire # Wayland screen sharing
    ];

  # Sourced inside the bubblewrap sandbox right before the AppImage runs.
  # The sunbird launcher passes the loader as SUNBIRD_PRELOAD so it is only
  # preloaded in here, not into bwrap or the outer wrapper.
  profile = ''
    export GI_TYPELIB_PATH=/usr/lib/girepository-1.0''${GI_TYPELIB_PATH:+:$GI_TYPELIB_PATH}
    if [ -n "''${SUNBIRD_PRELOAD:-}" ]; then
      export LD_PRELOAD="$SUNBIRD_PRELOAD''${LD_PRELOAD:+:$LD_PRELOAD}"
      unset SUNBIRD_PRELOAD
    fi
  '';

  extraInstallCommands = ''
    # Full hicolor set shipped in the AppImage (icon name: com.discord.libdiscord).
    mkdir -p $out/share
    cp -r --no-preserve=mode ${contents}/usr/share/icons $out/share/
    install -Dm444 ${desktopItem}/share/applications/*.desktop -t $out/share/applications
  '';

  passthru = { inherit src contents; };

  meta = {
    description = "Phoenix desktop client (third-party mirror build)";
    homepage = "https://sunbird.tools";
    license = lib.licenses.unfree;
    platforms = [ "x86_64-linux" ];
    mainProgram = pname;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}

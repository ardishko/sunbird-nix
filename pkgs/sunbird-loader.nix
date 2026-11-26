{
  lib,
  stdenvNoCC,
  fetchurl,
  sources,
}:

# NOTE: upstream serves the loader from an unversioned URL that changes on every
# release. The hash below pins the build that was current when sources.json was
# last updated; run ./update.sh (or the CI job) to bump it. A fresh machine
# without this exact file in its store will fail to fetch once upstream moves on.
stdenvNoCC.mkDerivation {
  pname = "sunbird-loader";
  inherit (sources.loader) version;

  src = fetchurl {
    inherit (sources.loader) url hash;
    name = "libphoenix-linux-x86_64-${sources.loader.version}.so";
  };

  dontUnpack = true;
  # Loaded into the FHS sandbox, where libc/libgcc_s/libcurl come from /usr/lib.
  dontFixup = true;

  installPhase = ''
    runHook preInstall
    install -Dm555 $src $out/lib/libphoenix.so
    runHook postInstall
  '';

  meta = {
    description = "Sunbird plugin runtime / access-gate loader for Phoenix";
    homepage = "https://sunbird.tools";
    license = lib.licenses.unfree;
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}

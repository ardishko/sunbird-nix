{
  lib,
  rustPlatform,
  fetchFromGitHub,
  sources,
}:

# Built from source, pinned to a commit. Upstream serves its prebuilt loader from
# one URL that it overwrites on every release, so a pinned hash of that file breaks
# as soon as they push; a commit never changes.
rustPlatform.buildRustPackage {
  pname = "sunbird-loader";
  inherit (sources.loader) version;

  src = fetchFromGitHub {
    owner = "sunbird-tools";
    repo = "sunbird";
    inherit (sources.loader) rev hash;
  };

  inherit (sources.loader) cargoHash;

  # crates/runtime/build.rs reads the version from `git log` and falls back to "0"
  # (older than any site build) without git, as in the Nix sandbox. Stamp the same
  # string upstream's build would produce for this commit instead.
  postPatch = ''
    substituteInPlace crates/runtime/build.rs \
      --replace-fail '.unwrap_or_else(|| "0".to_owned())' '.unwrap_or_else(|| "${sources.loader.version}".to_owned())'
  '';

  cargoBuildFlags = [
    "-p"
    "phoenix-loader"
  ];
  doCheck = false;
  # nixpkgs' cargo hook exports LIBSQLITE3_SYS_USE_PKG_CONFIG=1, which overrides
  # rusqlite's "bundled" feature and links a system libsqlite3. This library is
  # injected into another program, so build it like upstream does: SQLite static,
  # no extra shared libraries.
  preBuild = ''
    unset LIBSQLITE3_SYS_USE_PKG_CONFIG
  '';

  installPhase = ''
    runHook preInstall
    install -Dm555 "$(find target -path '*/release/libphoenix.so' -print -quit)" $out/lib/libphoenix.so
    runHook postInstall
  '';

  meta = {
    description = "Sunbird plugin runtime / access-gate loader for Phoenix";
    homepage = "https://github.com/sunbird-tools/sunbird";
    license = lib.licenses.eupl12;
    platforms = [ "x86_64-linux" ];
  };
}

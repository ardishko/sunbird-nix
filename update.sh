#!/usr/bin/env nix-shell
#!nix-shell -i bash -p curl jq python3 nix git
# Refresh sources.json from upstream. No binaries are stored in the repo, only
# URLs, commits and hashes; Nix fetches everything at build time.
#
# Phoenix: build number, URL and SHA-256 are scraped from sunbird.tools (the
#          hash comes from Sunbird, the file from the mirror, so Nix checks one
#          against the other). Nothing is downloaded here.
# Loader:  built from source. assets.sunbird.tools/version.json names the release
#          as <UTC date>-<short commit>; that commit is pinned, so the pin never
#          breaks when upstream pushes again.
#
# Exit code 0 with "unchanged" on stdout means there was nothing to do.
set -euo pipefail
cd "$(dirname "$0")"

page=${SUNBIRD_PAGE:-https://sunbird.tools/}
site=${SUNBIRD_SITE:-https://assets.sunbird.tools}
repo=${SUNBIRD_REPO:-https://github.com/sunbird-tools/sunbird}
nix() { command nix --extra-experimental-features 'nix-command flakes' "$@"; }

# --- Phoenix AppImage ---------------------------------------------------------
html=$(curl -fsSL --proto =https "$page")
read -r build url hex < <(printf %s "$html" | python3 -I -c '
import re, sys
s = sys.stdin.read()
m = re.search(r"https://dl\.redeem\.saarland/desktop/(\d+)/linux-x64\.AppImage", s)
if not m:
    sys.exit("no linux-x64 AppImage link on the page")
h = re.search(r"\b[0-9a-f]{64}\b", s[m.end():m.end() + 2000])
if not h:
    sys.exit("no SHA-256 next to the AppImage link")
print(m.group(1), m.group(0), h.group(0))
')
phoenix_hash=$(nix hash convert --hash-algo sha256 --to sri "$hex")

# --- Sunbird loader (source) --------------------------------------------------
loader_ver=$(curl -fsSL --proto =https "$site/version.json" | jq -er .loader)
short=${loader_ver##*-}
[[ $short =~ ^[0-9a-f]{7,40}$ ]] || { echo "unexpected loader version: $loader_ver" >&2; exit 1; }

if [ "$loader_ver" = "$(jq -r .loader.version sources.json)" ]; then
  rev=$(jq -r .loader.rev sources.json)
  src_hash=$(jq -r .loader.hash sources.json)
  cargo_hash=$(jq -r .loader.cargoHash sources.json)
else
  # Resolve the short commit with plain git (no API token or rate limit needed).
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  git -C "$tmp" init -q
  git -C "$tmp" fetch -q --filter=blob:none --depth 500 "$repo" HEAD
  rev=$(git -C "$tmp" rev-parse --verify "$short^{commit}")
  # Same version string upstream's build.rs derives from the commit.
  stamp=$(TZ=UTC0 git -C "$tmp" log -1 --format=%cd-%h --date=format-local:%Y.%m.%d.%H%M "$rev")
  [ "$stamp" = "$loader_ver" ] || { echo "commit $rev stamps as $stamp, site says $loader_ver" >&2; exit 1; }

  src_hash=$(nix flake prefetch --json "github:sunbird-tools/sunbird/$rev" | jq -r .hash)

  # cargoHash: build the vendor step against a placeholder and take the hash Nix reports.
  cp sources.json "$tmp/sources.json.bak"
  jq --arg v "$loader_ver" --arg r "$rev" --arg h "$src_hash" \
    '.loader = {version: $v, rev: $r, hash: $h, cargoHash: "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="}' \
    sources.json >"$tmp/sources.json" && cp "$tmp/sources.json" sources.json
  git add sources.json 2>/dev/null || true # flakes only see tracked content
  cargo_hash=$(nix build --no-link .#sunbird-loader.cargoDeps.vendorStaging 2>&1 \
    | sed -n 's/.*got: *\(sha256-[A-Za-z0-9+/=]*\).*/\1/p' | head -1) || true
  cp "$tmp/sources.json.bak" sources.json
  git add sources.json 2>/dev/null || true
  [ -n "$cargo_hash" ] || { echo "could not determine cargoHash" >&2; exit 1; }
fi

new=$(jq -n \
  --arg pv "$build" --arg pu "$url" --arg ph "$phoenix_hash" \
  --arg lv "$loader_ver" --arg lr "$rev" --arg lh "$src_hash" --arg lc "$cargo_hash" \
  '{phoenix: {version: $pv, url: $pu, hash: $ph}, loader: {version: $lv, rev: $lr, hash: $lh, cargoHash: $lc}}')

if [ "$new" = "$(jq . sources.json)" ]; then
  echo unchanged
  exit 0
fi

printf '%s\n' "$new" >sources.json
echo "phoenix: $build ($phoenix_hash)"
echo "loader:  $loader_ver ($rev)"

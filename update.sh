#!/usr/bin/env nix-shell
#!nix-shell -i bash -p curl jq python3 nix
# Refresh sources.json from upstream. No binaries are stored in the repo, only
# URLs and hashes; Nix downloads the files from their CDNs at build time.
#
# Phoenix: build number, URL and SHA-256 are scraped from sunbird.tools (the
#          hash comes from Sunbird, the file from the mirror, so Nix checks one
#          against the other). Nothing is downloaded here.
# Loader:  version from assets.sunbird.tools/version.json. Sunbird publishes no
#          hash for it, so the file is downloaded once and hashed (trust on
#          first use).
#
# Exit code 0 with "unchanged" on stdout means there was nothing to do.
set -euo pipefail
cd "$(dirname "$0")"

page=${SUNBIRD_PAGE:-https://sunbird.tools/}
site=${SUNBIRD_SITE:-https://assets.sunbird.tools}

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
phoenix_hash=$(nix --extra-experimental-features nix-command hash convert --hash-algo sha256 --to sri "$hex")

loader_ver=$(curl -fsSL --proto =https "$site/version.json" | jq -er .loader)
old_loader_ver=$(jq -r .loader.version sources.json)
if [ "$loader_ver" = "$old_loader_ver" ]; then
  loader_hash=$(jq -r .loader.hash sources.json)
else
  loader_hash=$(nix --extra-experimental-features nix-command store prefetch-file --json \
    "$site/plugins/libphoenix-linux-x86_64.so" | jq -r .hash)
fi

new=$(jq -n \
  --arg pv "$build" --arg pu "$url" --arg ph "$phoenix_hash" \
  --arg lv "$loader_ver" --arg lu "$site/plugins/libphoenix-linux-x86_64.so" --arg lh "$loader_hash" \
  '{phoenix: {version: $pv, url: $pu, hash: $ph}, loader: {version: $lv, url: $lu, hash: $lh}}')

if [ "$new" = "$(jq . sources.json)" ]; then
  echo unchanged
  exit 0
fi

printf '%s\n' "$new" >sources.json
echo "phoenix: $build ($phoenix_hash)"
echo "loader:  $loader_ver ($loader_hash)"

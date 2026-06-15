#!/usr/bin/env bash
set -euo pipefail
REPO="waccit/os-client"
VERSION="latest"
GITHUB_TOKEN=""
DOPPLER_TOKEN=""
DOPPLER_CONFIG=""
DOPPLER_PROJECT="os-client"
LIST_VERSIONS=0
usage() {
  cat <<'EOF'
Usage:
  install.sh --github-token TOKEN --doppler-token TOKEN --doppler-config CONFIG [--version vX.Y.Z]
  install.sh --github-token TOKEN --list-versions
Options:
  --github-token TOKEN     GitHub token with repo/package read access
  --doppler-token TOKEN    Doppler service token
  --doppler-config CONFIG  Doppler config, e.g. dev or prod
  --doppler-project NAME   Doppler project, default: os-client
  --version VERSION        Release tag, default: latest
  --list-versions          List available release versions
EOF
}
while [[ $# -gt 0 ]]; do
  case "$1" in
    --github-token) GITHUB_TOKEN="$2"; shift 2 ;;
    --doppler-token) DOPPLER_TOKEN="$2"; shift 2 ;;
    --doppler-config) DOPPLER_CONFIG="$2"; shift 2 ;;
    --doppler-project) DOPPLER_PROJECT="$2"; shift 2 ;;
    --version) VERSION="$2"; shift 2 ;;
    --list-versions) LIST_VERSIONS=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done
if [ -z "$GITHUB_TOKEN" ]; then
  echo "--github-token is required because waccit/os-client is private" >&2
  exit 1
fi
api_base="https://api.github.com/repos/${REPO}"
github_api() {
  curl -fsSL \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    "$1"
}
if [ "$LIST_VERSIONS" = "1" ]; then
  github_api "${api_base}/releases?per_page=50" \
    | python3 -c 'import json,sys; [print(r["tag_name"]) for r in json.load(sys.stdin) if not r.get("draft")]'
  exit 0
fi
if [ -z "$DOPPLER_TOKEN" ] || [ -z "$DOPPLER_CONFIG" ]; then
  echo "--doppler-token and --doppler-config are required for install" >&2
  exit 1
fi
if [ "$VERSION" = "latest" ]; then
  release_api_url="${api_base}/releases/latest"
else
  release_api_url="${api_base}/releases/tags/${VERSION}"
fi
asset_url="$(
  github_api "$release_api_url" \
    | python3 -c '
import json, sys
release = json.load(sys.stdin)
for asset in release.get("assets", []):
    if asset.get("name") == "install-os-client.sh":
        print(asset["url"])
        break
'
)"
if [ -z "$asset_url" ]; then
  echo "install-os-client.sh asset not found for ${VERSION}" >&2
  exit 1
fi
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
curl -fL \
  -H "Authorization: Bearer ${GITHUB_TOKEN}" \
  -H "Accept: application/octet-stream" \
  "$asset_url" \
  -o "${tmp_dir}/install-os-client.sh"
chmod +x "${tmp_dir}/install-os-client.sh"
export GH_TOKEN="${GITHUB_TOKEN}"
export GITHUB_TOKEN="${GITHUB_TOKEN}"
export GHCR_TOKEN="${GHCR_TOKEN:-$GITHUB_TOKEN}"
export GHCR_USERNAME="${GHCR_USERNAME:-x-access-token}"
export DOPPLER_TOKEN
export DOPPLER_CONFIG
export DOPPLER_PROJECT
export OS_CLIENT_VERSION="$VERSION"
bash "${tmp_dir}/install-os-client.sh"

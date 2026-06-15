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
  echo "Error: --github-token is required because ${REPO} is private." >&2
  exit 1
fi

api_base="https://api.github.com/repos/${REPO}"

github_api() {
  local url="$1"
  local response_file
  local status

  response_file="$(mktemp)"
  status="$(
    curl -sS -L \
      -H "Authorization: Bearer ${GITHUB_TOKEN}" \
      -H "Accept: application/vnd.github+json" \
      -o "$response_file" \
      -w "%{http_code}" \
      "$url"
  )"

  if [ "$status" != "200" ]; then
    echo "Error: GitHub API request failed with HTTP ${status}: ${url}" >&2
    echo "Check that your token is valid and has repo Contents: Read access." >&2
    rm -f "$response_file"
    exit 1
  fi

  cat "$response_file"
  rm -f "$response_file"
}

if [ "$LIST_VERSIONS" = "1" ]; then
  github_api "${api_base}/releases?per_page=50" \
    | python3 -c 'import json,sys; [print(r["tag_name"]) for r in json.load(sys.stdin) if not r.get("draft")]'
  exit 0
fi

if [ -z "$DOPPLER_TOKEN" ] || [ -z "$DOPPLER_CONFIG" ]; then
  echo "Error: --doppler-token and --doppler-config are required for install." >&2
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
  echo "Error: install-os-client.sh asset not found for ${VERSION}." >&2
  exit 1
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

status="$(
  curl -sS -L \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "Accept: application/octet-stream" \
    -o "${tmp_dir}/install-os-client.sh" \
    -w "%{http_code}" \
    "$asset_url"
)"

if [ "$status" != "200" ]; then
  echo "Error: failed to download install-os-client.sh with HTTP ${status}." >&2
  exit 1
fi

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

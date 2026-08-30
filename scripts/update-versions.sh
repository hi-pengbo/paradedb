#!/usr/bin/env bash
# Fetch the latest ParadeDB and VectorChord releases and rewrite Dockerfile (and README markers).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCKERFILE="${ROOT}/Dockerfile"
README="${ROOT}/README.md"

PARADEDB_REPO="${PARADEDB_REPO:-paradedb/paradedb}"
VCHORD_REPO="${VCHORD_REPO:-supervc-stack/VectorChord}"
PG_VERSION="${PG_VERSION:-$(grep -E '^ARG PG_VERSION=' "$DOCKERFILE" | head -1 | cut -d= -f2 | tr -d '"')}"

github_api() {
  local url="$1"
  local args=(-fsSL -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28")
  if [[ -n "${GITHUB_TOKEN:-}${GH_TOKEN:-}" ]]; then
    args+=(-H "Authorization: Bearer ${GITHUB_TOKEN:-${GH_TOKEN}}")
  fi
  curl "${args[@]}" "$url"
}

latest_release_tag() {
  local repo="$1"
  local tag
  tag="$(github_api "https://api.github.com/repos/${repo}/releases/latest" | jq -r '.tag_name // empty')"
  if [[ -z "$tag" || "$tag" == "null" ]]; then
    echo "failed to resolve latest release for ${repo}" >&2
    return 1
  fi
  if [[ "$tag" =~ (rc|alpha|beta|preview) ]]; then
    echo "latest tag for ${repo} looks like a prerelease: ${tag}" >&2
    return 1
  fi
  printf '%s\n' "$tag"
}

current_arg() {
  local name="$1"
  grep -E "^ARG ${name}=" "$DOCKERFILE" | head -1 | cut -d= -f2 | tr -d '"'
}

dockerhub_tag_exists() {
  local tag="$1"
  curl -fsSL "https://hub.docker.com/v2/repositories/paradedb/paradedb/tags/${tag}" >/dev/null
}

vchord_deb_exists() {
  local version="$1"
  local url="https://github.com/${VCHORD_REPO}/releases/download/${version}/postgresql-${PG_VERSION}-vchord_${version}-1_amd64.deb"
  curl -fsI "$url" >/dev/null
}

CURRENT_PARADEDB="$(current_arg PARADEDB_VERSION)"
CURRENT_VCHORD="$(current_arg VCHORD_VERSION)"

if [[ -n "${PARADEDB_VERSION_OVERRIDE:-}" ]]; then
  NEW_PARADEDB="$PARADEDB_VERSION_OVERRIDE"
else
  NEW_PARADEDB="$(latest_release_tag "$PARADEDB_REPO")"
fi

if [[ -n "${VCHORD_VERSION_OVERRIDE:-}" ]]; then
  NEW_VCHORD="$VCHORD_VERSION_OVERRIDE"
else
  NEW_VCHORD="$(latest_release_tag "$VCHORD_REPO")"
fi

echo "ParadeDB:    ${CURRENT_PARADEDB} -> ${NEW_PARADEDB}"
echo "VectorChord: ${CURRENT_VCHORD} -> ${NEW_VCHORD}"
echo "Postgres:    ${PG_VERSION}"

IMAGE_TAG="${NEW_PARADEDB}-pg${PG_VERSION}"
if ! dockerhub_tag_exists "$IMAGE_TAG"; then
  echo "ParadeDB image tag not published yet: paradedb/paradedb:${IMAGE_TAG}" >&2
  exit 1
fi

if ! vchord_deb_exists "$NEW_VCHORD"; then
  echo "VectorChord deb not published yet for pg${PG_VERSION}: ${NEW_VCHORD}" >&2
  exit 1
fi

if [[ "$CURRENT_PARADEDB" == "$NEW_PARADEDB" && "$CURRENT_VCHORD" == "$NEW_VCHORD" ]]; then
  echo "already up to date"
  CHANGED=false
else
  CHANGED=true
  tmp="$(mktemp)"
  sed -E \
    -e "s/^ARG PARADEDB_VERSION=.*/ARG PARADEDB_VERSION=${NEW_PARADEDB}/" \
    -e "s/^ARG VCHORD_VERSION=.*/ARG VCHORD_VERSION=${NEW_VCHORD}/" \
    "$DOCKERFILE" >"$tmp"
  mv "$tmp" "$DOCKERFILE"

  if [[ -f "$README" ]]; then
    python3 - "$README" "$NEW_PARADEDB" "$NEW_VCHORD" "$PG_VERSION" <<'PY'
import pathlib, re, sys
path, paradedb, vchord, pg = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4]
text = path.read_text()
block = (
    "<!-- VERSIONS:START -->\n"
    f"- ParadeDB: `{paradedb}`\n"
    f"- VectorChord: `{vchord}`\n"
    f"- PostgreSQL: `{pg}`\n"
    "<!-- VERSIONS:END -->"
)
updated, n = re.subn(
    r"<!-- VERSIONS:START -->.*?<!-- VERSIONS:END -->",
    block,
    text,
    count=1,
    flags=re.S,
)
if n:
    path.write_text(updated)
PY
  fi
fi

SUMMARY="Bump ParadeDB to ${NEW_PARADEDB} and VectorChord to ${NEW_VCHORD} (pg${PG_VERSION})"
if [[ "$CURRENT_PARADEDB" != "$NEW_PARADEDB" && "$CURRENT_VCHORD" == "$NEW_VCHORD" ]]; then
  SUMMARY="Bump ParadeDB to ${NEW_PARADEDB} (pg${PG_VERSION})"
elif [[ "$CURRENT_PARADEDB" == "$NEW_PARADEDB" && "$CURRENT_VCHORD" != "$NEW_VCHORD" ]]; then
  SUMMARY="Bump VectorChord to ${NEW_VCHORD} (pg${PG_VERSION})"
fi

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "changed=${CHANGED}"
    echo "paradedb=${NEW_PARADEDB}"
    echo "vchord=${NEW_VCHORD}"
    echo "pg=${PG_VERSION}"
    echo "summary=${SUMMARY}"
  } >>"$GITHUB_OUTPUT"
fi

echo "$SUMMARY"

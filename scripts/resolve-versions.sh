#!/usr/bin/env bash
# Resolve kitsune2 and lair tags from a holochain release's Cargo.lock and
# rewrite versions.json.
#
# Reads the Cargo.lock at the given holochain tag, extracts the resolved
# versions of the kitsune2 and lair_keystore crates, validates that matching
# git tags exist on the upstream repos (with a sha->tag fallback for git
# pins), and rewrites versions.json. Refuses to downgrade the holochain
# version unless --force is given.
#
# Requires: bash, curl, jq, taplo, gh (with GH_TOKEN set).

set -euo pipefail
export LC_ALL=C

usage() {
  cat <<EOF
Usage: $0 [--force] <holochain-tag>

Options:
  --force          Allow downgrading the holochain version.

Environment:
  VERSIONS_FILE    Path to versions.json (default: versions.json).
  GH_TOKEN         Token for gh CLI calls.
EOF
}

FORCE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --force) FORCE=1; shift;;
    -h|--help) usage; exit 0;;
    --) shift; break;;
    -*) echo "Unknown option: $1" >&2; usage >&2; exit 64;;
    *) break;;
  esac
done

if [[ $# -ne 1 ]]; then
  usage >&2
  exit 64
fi

TAG="$1"
VERSIONS_FILE="${VERSIONS_FILE:-versions.json}"

HC_TAG_RE='^holochain-([0-9]+)\.([0-9]+)\.([0-9]+)(-([a-z]+)\.([0-9]+))?$'

# Convert a holochain tag into a fixed-width sortable key. Lexicographic
# comparison of two such keys matches the intended version ordering:
# release > pre-release; within pre, alpha label compare then numeric.
parse_hc_key() {
  local t="$1"
  if ! [[ "$t" =~ $HC_TAG_RE ]]; then
    echo "Unrecognized holochain tag: $t" >&2
    return 1
  fi
  local maj="${BASH_REMATCH[1]}" min="${BASH_REMATCH[2]}" pat="${BASH_REMATCH[3]}"
  local label="${BASH_REMATCH[5]:-}" num="${BASH_REMATCH[6]:-0}"
  local rel=1
  [[ -n "$label" ]] && rel=0
  printf '%03d.%03d.%03d %d %-10s %09d' "$maj" "$min" "$pat" "$rel" "$label" "$num"
}

if ! [[ "$TAG" =~ $HC_TAG_RE ]]; then
  echo "Unrecognized holochain tag: $TAG" >&2
  exit 1
fi

CURRENT_HC=$(jq -r '.holochain' "$VERSIONS_FILE")
INCOMING_KEY=$(parse_hc_key "$TAG")
CURRENT_KEY=$(parse_hc_key "$CURRENT_HC")

if [[ "$INCOMING_KEY" < "$CURRENT_KEY" && $FORCE -ne 1 ]]; then
  echo "Refusing downgrade: $CURRENT_HC -> $TAG (pass --force to override)" >&2
  exit 2
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

CARGO_LOCK="$WORK/Cargo.lock"
PACKAGES_JSON="$WORK/packages.json"

echo "Fetching Cargo.lock for $TAG..." >&2
curl --fail --silent --show-error --location \
  --user-agent "binaries-version-resolver" \
  --output "$CARGO_LOCK" \
  "https://raw.githubusercontent.com/holochain/holochain/$TAG/Cargo.lock"

taplo get --file-path "$CARGO_LOCK" --output-format json \
  | jq '.package' > "$PACKAGES_JSON"

# Extract version and source for the first matching package. Multiple
# kitsune2_* crates share the same workspace version, so picking any is fine.
extract() {
  jq -r --arg expr "$1" '
    map(select(.name | test($expr))) | .[0]
    | if . == null then "" else "\(.version)\t\(.source // "")" end
  ' "$PACKAGES_JSON"
}

KITSUNE2_LINE=$(extract '^kitsune2_')
LAIR_LINE=$(extract '^lair_keystore$')

if [[ -z "$KITSUNE2_LINE" ]]; then
  echo "No kitsune2_* package found in Cargo.lock for $TAG" >&2
  exit 1
fi
if [[ -z "$LAIR_LINE" ]]; then
  echo "No lair_keystore package found in Cargo.lock for $TAG" >&2
  exit 1
fi

KITSUNE2_VERSION="${KITSUNE2_LINE%%$'\t'*}"
KITSUNE2_SOURCE="${KITSUNE2_LINE#*$'\t'}"
LAIR_VERSION="${LAIR_LINE%%$'\t'*}"
LAIR_SOURCE="${LAIR_LINE#*$'\t'}"

# Resolve "<version>" + "<source>" -> upstream git tag.
resolve_tag() {
  local repo="$1" version="$2" source="$3"
  if [[ "$source" == git+* ]]; then
    if [[ "$source" != *"#"* ]]; then
      echo "$repo: git source without sha: $source" >&2
      return 1
    fi
    local sha="${source##*#}"
    local found
    found=$(gh api --paginate "repos/holochain/$repo/tags" \
      --jq ".[] | select(.commit.sha==\"$sha\") | .name" | head -n1)
    if [[ -z "$found" ]]; then
      echo "$repo: no tag points at commit $sha (source: $source)" >&2
      return 1
    fi
    echo "$found"
    return 0
  fi
  local candidate="v$version"
  if ! gh api "repos/holochain/$repo/git/refs/tags/$candidate" >/dev/null 2>&1; then
    echo "$repo: tag $candidate does not exist on remote (crate version $version, source $source)" >&2
    return 1
  fi
  echo "$candidate"
}

echo "Resolving kitsune2 (crate version $KITSUNE2_VERSION)..." >&2
KITSUNE2_TAG=$(resolve_tag kitsune2 "$KITSUNE2_VERSION" "$KITSUNE2_SOURCE")
echo "Resolving lair (crate version $LAIR_VERSION)..." >&2
LAIR_TAG=$(resolve_tag lair "$LAIR_VERSION" "$LAIR_SOURCE")

NEW_JSON=$(jq -n \
  --arg holochain "$TAG" \
  --arg kitsune2 "$KITSUNE2_TAG" \
  --arg lair "$LAIR_TAG" \
  '{holochain: $holochain, kitsune2: $kitsune2, lair: $lair}')

if diff -q <(jq -S . "$VERSIONS_FILE") <(printf '%s' "$NEW_JSON" | jq -S .) >/dev/null; then
  echo "versions.json already up to date" >&2
  exit 0
fi

printf '%s\n' "$NEW_JSON" > "$VERSIONS_FILE"
printf '%s\n' "$NEW_JSON"

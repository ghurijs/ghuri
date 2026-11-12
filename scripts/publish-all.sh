#!/usr/bin/env bash
# Publish every Ghuri package to npm in dependency order.
# npm asks you to approve each publish in the browser (or for a 2FA code).
#
# Usage:
#   scripts/publish-all.sh                 dist-tag chosen per package (see below)
#   scripts/publish-all.sh <dist-tag>      force a dist-tag for every package (e.g. next)
#   scripts/publish-all.sh --sync-latest   don't publish; point `latest` at each package's current version
#                                          where the package has no stable release yet (one-time fix)
#
# Dist-tag per package, when none is forced: a stable version goes to `latest`. A prerelease goes to `latest`
# while the package has no stable release at all (so `npm install` and `npm create ghuri` get the newest alpha
# instead of the first one), and to `next` once a stable release exists (so it never replaces stable users).

# Needs bash (process substitution below). `sh scripts/publish-all.sh` runs bash in POSIX mode (macOS) or another
# shell, which fails with "syntax error near unexpected token `>'", so re-run under bash in that case.
case "${BASH_VERSION:-}:${SHELLOPTS:-}" in
  :* | *posix*) exec bash "$0" "$@" ;;
esac
set -euo pipefail
cd "$(dirname "$0")/.."
MODE=publish
FORCED_TAG=""
case "${1:-}" in
  --sync-latest) MODE=sync ;;
  "") ;;
  -*) echo "Unknown option: $1"; exit 1 ;;
  *) FORCED_TAG="$1" ;;
esac
if [ ! -t 0 ]; then
  echo "publish-all.sh needs an interactive terminal: npm's browser approval (--auth-type=web) can't run here,"
  echo "so npm would fail with EOTP. Type the command into a terminal window yourself and press Enter at each prompt."
  exit 1
fi
ORDER=(core mail orm storage auth rest admin agents graphql realtime oauth oauth-provider socialauth tenants cli create-ghuri)

is_prerelease() { [[ "$1" == *-* ]]; }

# Does `name` have any stable (non-prerelease) version on npm?
has_stable_release() {
  local versions
  versions=$(npm view "$1" versions --json 2>/dev/null || echo '[]')
  node -e 'const v = JSON.parse(process.argv[1]); process.exit([].concat(v).some((x) => !String(x).includes("-")) ? 0 : 1)' "$versions"
}

tag_for() {
  local name=$1 version=$2
  if [ -n "$FORCED_TAG" ]; then echo "$FORCED_TAG"; return; fi
  if ! is_prerelease "$version" || ! has_stable_release "$name"; then echo latest; else echo next; fi
}

npm whoami >/dev/null || { echo "Run: npm login"; exit 1; }

if [ "$MODE" = sync ]; then
  for p in "${ORDER[@]}"; do
    name=$(node -p "require('./packages/$p/package.json').name")
    version=$(node -p "require('./packages/$p/package.json').version")
    if ! npm view "$name@$version" version >/dev/null 2>&1; then
      echo "skip $name@$version (not published)"; continue
    fi
    current=$(npm view "$name" dist-tags.latest 2>/dev/null || true)
    if [ "$current" = "$version" ]; then echo "ok   $name latest=$version"; continue; fi
    if has_stable_release "$name" && is_prerelease "$version"; then
      echo "skip $name (has a stable release; latest stays $current)"; continue
    fi
    echo "tag  $name@$version latest (was $current)"
    npm dist-tag add "$name@$version" latest --auth-type=web
  done
  echo "Done."
  exit 0
fi

npm run build
for p in "${ORDER[@]}"; do
  name=$(node -p "require('./packages/$p/package.json').name")
  version=$(node -p "require('./packages/$p/package.json').version")
  if npm view "$name@$version" version >/dev/null 2>&1; then
    echo "skip $name@$version (already published)"; continue
  fi
  TAG=$(tag_for "$name" "$version")
  echo "publishing $name@$version --tag $TAG"
  log=$(mktemp)
  # npm's browser approval only runs when its stdin and stdout are a terminal (lib/utils/auth.js otplease):
  # piping stdout makes it fail with EOTP. Keep stdout on the terminal and copy only stderr to the log.
  if ! (cd "packages/$p" && npm publish --access public --tag "$TAG" --auth-type=web 2> >(tee "$log" >&2)); then
    sleep 1 # let tee finish writing the log
    # npm holds a fresh upload as "staged" for several minutes: `npm view` says 404 but a re-publish gets 409.
    if grep -q 'previously staged version' "$log"; then
      echo "skip $name@$version (staged by an earlier run; npm will show it within ~20 minutes)"
    else
      rm -f "$log"; exit 1
    fi
  fi
  rm -f "$log"
done
echo "Done. Try: npm create ghuri@latest mysite"

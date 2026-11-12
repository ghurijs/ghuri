#!/usr/bin/env bash
# Publish every Ghuri package to npm in dependency order.
# npm asks for your 2FA code (or opens the browser) for each package.
# Usage: scripts/publish-all.sh [dist-tag]   (default: next)
set -euo pipefail
cd "$(dirname "$0")/.."
TAG="${1:-next}"
if [ ! -t 0 ]; then
  echo "publish-all.sh needs an interactive terminal: npm's browser approval (--auth-type=web) can't run here,"
  echo "so npm would fail with EOTP. Type the command into a terminal window yourself and press Enter at each prompt."
  exit 1
fi
ORDER=(core mail orm storage auth rest admin agents graphql realtime oauth socialauth tenants cli create-ghuri)
npm whoami >/dev/null || { echo "Run: npm login"; exit 1; }
npm run build
for p in "${ORDER[@]}"; do
  name=$(node -p "require('./packages/$p/package.json').name")
  version=$(node -p "require('./packages/$p/package.json').version")
  if npm view "$name@$version" version >/dev/null 2>&1; then
    echo "skip $name@$version (already published)"; continue
  fi
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
echo "Done. Try: npm create ghuri@$TAG mysite"

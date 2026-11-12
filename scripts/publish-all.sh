#!/usr/bin/env bash
# Publish every Ghuri package to npm in dependency order.
# npm asks for your 2FA code (or opens the browser) for each package.
# Usage: scripts/publish-all.sh [dist-tag]   (default: next)
set -euo pipefail
cd "$(dirname "$0")/.."
TAG="${1:-next}"
ORDER=(core orm storage auth rest admin agents graphql realtime oauth socialauth cli create-ghuri)
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
  if ! (cd "packages/$p" && npm publish --access public --tag "$TAG" --auth-type=web 2>&1 | tee "$log"; exit "${PIPESTATUS[0]}"); then
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

#!/usr/bin/env bash
# Publish every Ghuri package to npm in dependency order.
# npm asks for your 2FA code (or opens the browser) for each package.
# Usage: scripts/publish-all.sh [dist-tag]   (default: next)
set -euo pipefail
cd "$(dirname "$0")/.."
TAG="${1:-next}"
ORDER=(core orm storage auth rest admin agents cli create-ghuri)
npm whoami >/dev/null || { echo "Run: npm login"; exit 1; }
npm run build
for p in "${ORDER[@]}"; do
  name=$(node -p "require('./packages/$p/package.json').name")
  version=$(node -p "require('./packages/$p/package.json').version")
  if npm view "$name@$version" version >/dev/null 2>&1; then
    echo "skip $name@$version (already published)"; continue
  fi
  echo "publishing $name@$version --tag $TAG"
  (cd "packages/$p" && npm publish --access public --tag "$TAG" --auth-type=web)
done
echo "Done. Try: npm create ghuri@$TAG mysite"

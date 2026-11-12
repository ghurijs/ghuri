#!/usr/bin/env bash
# Clone every Ghuri package repo into packages/ and install the workspace.
set -euo pipefail
cd "$(dirname "$0")/.."
REPOS=(core orm auth rest storage admin agents graphql realtime oauth socialauth cli create-ghuri)
mkdir -p packages
for r in "${REPOS[@]}"; do
  [ -d "packages/$r/.git" ] || git clone "https://github.com/ghurijs/$r.git" "packages/$r"
done
[ -d "examples/.git" ] || git clone https://github.com/ghurijs/examples.git examples
npm install
npm run build

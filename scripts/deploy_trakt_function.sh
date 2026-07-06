#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if ! command -v supabase >/dev/null 2>&1; then
  echo "supabase CLI is not installed."
  echo "Install it, then rerun this script from the repo root."
  exit 1
fi

if [[ ! -f "supabase/functions/trakt/index.ts" ]]; then
  echo "Missing supabase/functions/trakt/index.ts"
  exit 1
fi

supabase functions deploy trakt --no-verify-jwt

echo
echo "Deployed trakt function. Test it with:"
echo "curl -i https://api.nuvio.tv/functions/v1/trakt"

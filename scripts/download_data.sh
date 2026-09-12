#!/usr/bin/env bash
# Downloads the Olist dataset from Kaggle into data/raw/ (skips if already present).
# Requires the Kaggle CLI (`uv tool install kaggle`) and a Kaggle API token
# (KAGGLE_API_TOKEN env var or ~/.kaggle/access_token).
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p data/raw
if ls data/raw/olist_orders_dataset.csv >/dev/null 2>&1; then
  echo "data/raw already populated, skipping download"
  exit 0
fi
if [ -z "${KAGGLE_API_TOKEN:-}" ] && [ -f "$HOME/.kaggle/access_token" ]; then
  export KAGGLE_API_TOKEN="$(cat "$HOME/.kaggle/access_token")"
fi
kaggle datasets download -d olistbr/brazilian-ecommerce -p data/raw
unzip -oq data/raw/brazilian-ecommerce.zip -d data/raw
rm data/raw/brazilian-ecommerce.zip
ls -l data/raw

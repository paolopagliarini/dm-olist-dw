#!/usr/bin/env bash
# Regenerates the DFM and star schema diagrams (SVG) from docs/dfm/draw_diagrams.py.
# The star schema is read from the dw catalog, so the olist_dw database must be built (scripts/run_all.sh).
set -euo pipefail
cd "$(dirname "$0")/../.."
uv run docs/dfm/draw_diagrams.py

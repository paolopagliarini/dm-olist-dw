#!/usr/bin/env bash
# Regenerates the DFM and star schema diagrams (SVG) from docs/dfm/draw_diagrams.py
set -euo pipefail
cd "$(dirname "$0")/../.."
uv run docs/dfm/draw_diagrams.py

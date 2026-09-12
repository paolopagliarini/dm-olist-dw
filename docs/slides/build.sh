#!/usr/bin/env bash
# Renders docs/slides/index.html to a 16:9 PDF (960x540 pt per slide) with headless Chrome.
# Output: docs/slides/build/olist-dw-slides.pdf
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
CHROME="${CHROME:-$(ls -d "$HOME"/.cache/puppeteer/chrome-headless-shell/*/chrome-headless-shell-mac-*/chrome-headless-shell 2>/dev/null | tail -1)}"
[ -x "$CHROME" ] || { echo "chrome-headless-shell not found; set CHROME=/path/to/chrome"; exit 1; }
"$CHROME" --headless --disable-gpu --no-pdf-header-footer --print-to-pdf="$PWD/build/olist-dw-slides.pdf" "file://$PWD/index.html" >/dev/null 2>&1
pdfinfo build/olist-dw-slides.pdf | grep -E "Pages|Page size"

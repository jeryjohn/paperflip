#!/usr/bin/env bash
# Fetches the public-domain EPUBs used by the example app and the EPUB tests.
# They are not committed: together they are several megabytes, and the example
# streams them over the network anyway.
set -euo pipefail
dir="$(cd "$(dirname "$0")/.." && pwd)/test/fixtures"
mkdir -p "$dir"
for id in 19033 19002 28885; do
  out="$dir/pg${id}.epub"
  if [ -f "$out" ]; then
    echo "have  pg${id}.epub"
    continue
  fi
  echo "fetch pg${id}.epub"
  curl -fsSL -o "$out" "https://www.gutenberg.org/cache/epub/${id}/pg${id}-images.epub"
done
echo "done -> $dir"

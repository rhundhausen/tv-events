#!/usr/bin/env bash
# Cloudflare Workers build script for the Hugo site.
# Runs from the website/ folder (set as the project root directory in Cloudflare).
# Pin HUGO_VERSION to the version you run locally (hugo version).

set -euo pipefail

HUGO_VERSION=0.162.1
export TZ=America/Boise
export HUGO_CACHEDIR="${PWD}/.cache/hugo"

mkdir -p ~/.local/bin
echo "Installing Hugo ${HUGO_VERSION}..."
curl -sfL "https://github.com/gohugoio/hugo/releases/download/v${HUGO_VERSION}/hugo_extended_${HUGO_VERSION}_linux-amd64.tar.gz" \
  | tar -xz -C ~/.local/bin hugo
export PATH="${HOME}/.local/bin:${PATH}"

hugo version

# Mounts in hugo.toml reach ../data and ../ingestion, so the full repo clone is required.
# Cloudflare clones the whole repo and runs this from website/, so those paths resolve.
hugo build --gc --minify

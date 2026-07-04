#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../backend/api"
python3 -m app.seed

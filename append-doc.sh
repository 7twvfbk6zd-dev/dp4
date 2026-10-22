#!/usr/bin/env bash
set -euo pipefail
cd /mapdata1/tools/ds4-main
if ! grep -q 'TP-MULTI-RANK.md' OPTIMIZATION-168.md; then
  cat >> OPTIMIZATION-168.md <<'EOF'

## Multi-rank TP (4/8 GPUs)

V4.1 Flash now supports expert-parallel TP on 4 or 8 GPUs. See
`TP-MULTI-RANK.md` for launch commands, measured t/s, and troubleshooting.
EOF
fi
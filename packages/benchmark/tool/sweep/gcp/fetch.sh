#!/usr/bin/env bash
# Lists the sweeps in the bucket, or copies one down.
#
#   tool/sweep/gcp/fetch.sh                 # list
#   tool/sweep/gcp/fetch.sh <run> [dest]    # copy gs://<bucket>/<run> to dest
set -euo pipefail
BUCKET=${BUCKET:-relic-bench-nights}
if [[ $# -eq 0 ]]; then
  gcloud storage ls "gs://$BUCKET/"
else
  DEST=${2:-sweep-out/$1}
  mkdir -p "$DEST"
  gcloud storage cp -r "gs://$BUCKET/$1/*" "$DEST/"
  echo "$DEST"
fi

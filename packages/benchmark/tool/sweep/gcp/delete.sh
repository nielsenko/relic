#!/usr/bin/env bash
# Deletes a stopped sweep instance and its boot disk. A shut down instance
# stays in the project and its disk stays billed until this runs.
#
#   tool/sweep/gcp/delete.sh [name] [zone]
#
# Defaults: relic-bench, europe-west4-a. An instance that has not stopped
# is left alone.
set -euo pipefail
NAME=${1:-relic-bench}
ZONE=${2:-europe-west4-a}
PROJECT=${PROJECT:-relic-bench}
STATUS=$(gcloud compute instances describe "$NAME" \
  --project="$PROJECT" --zone="$ZONE" --format='value(status)')
if [[ $STATUS != TERMINATED ]]; then
  echo "$NAME is $STATUS, not deleting it" >&2
  exit 1
fi
gcloud compute instances delete "$NAME" \
  --project="$PROJECT" --zone="$ZONE" --quiet

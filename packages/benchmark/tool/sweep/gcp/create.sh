#!/usr/bin/env bash
# Creates a GCP instance that runs the sweep once and shuts down.
#
#   tool/sweep/gcp/create.sh [name] [machine-type] [zone]
#
# Defaults: relic-bench, c4d-standard-32, europe-west4-a. A VM gets one
# thread per core and spot pricing. A -metal type gets neither, since the
# platform has no such flags for bare metal; the OS turns SMT off there.
# A VM also stops after MAX_RUN, 8h by default.
# An arm type (c4a-) gets the arm64 image. Metadata attributes for the
# startup script come from the environment: RELIC_BRANCH, SWEEP_ENV,
# SWEEP_ONLY, KEEP. RELIC_PATCH names a file to apply to the clone.
set -euo pipefail
NAME=${1:-relic-bench}
TYPE=${2:-c4d-standard-32}
ZONE=${3:-europe-west4-a}
PROJECT=${PROJECT:-relic-bench}
S=$(cd "$(dirname "$0")" && pwd)
case $TYPE in
  c4a-*) IMAGE=ubuntu-2404-lts-arm64 ;;
  *) IMAGE=ubuntu-2404-lts-amd64 ;;
esac
FLAGS=()
case $TYPE in
  *-metal) ;;
  *) FLAGS+=(--threads-per-core=1 --provisioning-model=SPOT --instance-termination-action=STOP "--max-run-duration=${MAX_RUN:-8h}") ;;
esac
META="relic-branch=${RELIC_BRANCH:-chore-benchmark-sweep},sweep-env=${SWEEP_ENV:-QUIET=0 PAUSE=5 OHA_THREADS=8},keep=${KEEP:-0}"
[[ -n ${SWEEP_ONLY:-} ]] && META="$META,sweep-only=$SWEEP_ONLY"
FILES="startup-script=$S/startup.sh"
[[ -n ${RELIC_PATCH:-} ]] && FILES="$FILES,relic-patch=$RELIC_PATCH"
gcloud compute instances create "$NAME" \
  --project="$PROJECT" --zone="$ZONE" --machine-type="$TYPE" \
  --image-family="$IMAGE" --image-project=ubuntu-os-cloud \
  --boot-disk-type=hyperdisk-balanced --boot-disk-size=50GB \
  --service-account="relic-bench-runner@$PROJECT.iam.gserviceaccount.com" \
  --scopes=storage-rw \
  --metadata="$META" \
  --metadata-from-file="$FILES" \
  "${FLAGS[@]}"
echo "follow with: gcloud compute instances tail-serial-port-output $NAME --zone=$ZONE --project=$PROJECT"
echo "delete it when it has stopped: $S/delete.sh $NAME $ZONE"

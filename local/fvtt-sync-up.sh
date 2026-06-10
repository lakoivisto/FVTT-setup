#!/usr/bin/env bash
# Mirrors the local FoundryVTT data dir up to S3 (--delete makes the bucket
# match local exactly). Run via ./ex.sh local-down before stopping the container.
set -euo pipefail

aws s3 sync /opt/foundrydata/Data/ "s3://${FVTT_BACKUP_BUCKET}/Data/" --delete --region "${AWS_DEFAULT_REGION:-eu-north-1}"

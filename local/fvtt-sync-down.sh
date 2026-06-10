#!/usr/bin/env bash
# Pulls FoundryVTT world/system/module data from S3 into the local data dir.
# Additive only (no --delete) — never removes local files, so it's safe to
# run on every container start without risking data loss from a stale bucket.
set -euo pipefail

aws s3 sync "s3://${FVTT_BACKUP_BUCKET}/Data/" /opt/foundrydata/Data/ --region "${AWS_DEFAULT_REGION:-eu-north-1}"

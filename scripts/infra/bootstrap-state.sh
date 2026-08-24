#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

environment="${ENV:-}"
tfvars=$(infra::require_environment "$environment")
infra::require_command gcloud

project_id=$(infra::read_tfvar "$tfvars" project_id)
region=$(infra::read_tfvar "$tfvars" region)
bucket="${project_id}-proxy-builder-tfstate"

active_account=$(gcloud auth list --filter=status:ACTIVE --format='value(account)' | head -n 1)
[[ -n "$active_account" ]] || infra::die "gcloud 没有活动账号，请先完成本地登录"

if ! gcloud storage buckets describe "gs://${bucket}" >/dev/null 2>&1; then
    printf '创建 state bucket: gs://%s (%s)\n' "$bucket" "$region"
    gcloud storage buckets create "gs://${bucket}" \
        --project="$project_id" \
        --location="$region" \
        --uniform-bucket-level-access \
        --public-access-prevention \
        --quiet
else
    printf '复用 state bucket: gs://%s\n' "$bucket"
fi

gcloud storage buckets update "gs://${bucket}" \
    --versioning \
    --uniform-bucket-level-access \
    --public-access-prevention \
    --update-labels="application=proxy-builder,environment=${environment}" \
    --quiet

printf 'state bucket 已就绪: gs://%s\n' "$bucket"

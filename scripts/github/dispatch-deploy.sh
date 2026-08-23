#!/usr/bin/env bash
set -euo pipefail

environment="${ENV:-}"
git_ref="${GIT_REF:-}"
case "$environment" in development|production) ;; *) printf '%s\n' 'ENV must be development or production' >&2; exit 2 ;; esac
command -v gh >/dev/null 2>&1 || { printf '%s\n' 'missing command: gh' >&2; exit 1; }
[[ -n "$git_ref" ]] || git_ref="$(git rev-parse HEAD)"
workflow_ref="$(git symbolic-ref --quiet --short HEAD || printf '%s' main)"
gh workflow run deploy.yml --ref "$workflow_ref" -f "environment=${environment}" -f "git_ref=${git_ref}"
printf 'deploy workflow dispatched for %s at %s\n' "$environment" "$git_ref"


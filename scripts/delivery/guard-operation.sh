#!/usr/bin/env bash
set -euo pipefail

environment="${1:-}"
git_sha="${2:-}"

case "$environment" in
  development) ;;
  production)
    [[ "${GITHUB_REF:-}" == "refs/heads/main" ]] || {
      printf '%s\n' 'production operations require the workflow from main' >&2
      exit 1
    }
    [[ "${PRODUCTION_OPERATIONS_ENABLED:-}" == "true" ]] || {
      printf '%s\n' 'production operations are disabled' >&2
      exit 1
    }
    if [[ -n "$git_sha" ]]; then
      git fetch --quiet origin main
      git merge-base --is-ancestor "$git_sha" origin/main || {
        printf '%s\n' 'production git SHA is not reachable from origin/main' >&2
        exit 1
      }
    fi
    ;;
  *) printf '%s\n' 'environment must be development or production' >&2; exit 2 ;;
esac


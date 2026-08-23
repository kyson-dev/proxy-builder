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
      main_ref="origin/main"
      if [[ "${PROXY_BUILDER_TESTING:-0}" == "1" ]]; then
        main_ref="${PRODUCTION_MAIN_REF:?PRODUCTION_MAIN_REF is required in test mode}"
      else
        git fetch --quiet origin main
      fi
      git merge-base --is-ancestor "$git_sha" "$main_ref" || {
        printf '%s\n' 'production git SHA is not reachable from origin/main' >&2
        exit 1
      }
    fi
    ;;
  *) printf '%s\n' 'environment must be development or production' >&2; exit 2 ;;
esac

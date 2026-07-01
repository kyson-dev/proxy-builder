#!/bin/bash
# ==============================================================================
# GCP startup-script: deploy the current package without SSH/SCP.
# Expects instance metadata keys:
#   proxy-builder-deploy-bucket
#   proxy-builder-deploy-object
#   proxy-builder-deploy-run-id
# ==============================================================================
set -euo pipefail

LOG_FILE="/var/log/proxy-bootstrap.log"
READY_FILE="/var/lib/proxy/ready"
FAILED_FILE="/var/lib/proxy/failed"
APP_DIR="/opt/proxy/app"
BACKUP_DIR="/opt/proxy/app.backup"
DATA_DIR="/opt/proxy/data"
DATA_BACKUP_DIR="/opt/proxy/data.backup"
PACKAGE_FILE="/tmp/proxy-app.tar.gz"
METADATA_BASE="http://metadata.google.internal/computeMetadata/v1"

mkdir -p "$(dirname "$READY_FILE")" "$DATA_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1

log() {
    echo "[$(date -Is)] $*"
}

metadata() {
    local key="$1"
    curl -fsS -H "Metadata-Flavor: Google" \
        "${METADATA_BASE}/instance/attributes/${key}"
}

oauth_token() {
    curl -fsS -H "Metadata-Flavor: Google" \
        "${METADATA_BASE}/instance/service-accounts/default/token" |
        sed -n 's/.*"access_token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'
}

upload_log() {
    local status="$1"
    local bucket run_id token
    bucket="$(metadata proxy-deploy-bucket || true)"
    run_id="$(metadata proxy-deploy-run-id || true)"
    token="$(oauth_token || true)"

    if [[ -n "$bucket" && -n "$run_id" && -n "$token" ]]; then
        log "Uploading deployment result log to GCS: gs://${bucket}/deploy-${run_id}-${status}.log"
        # 使用 GCS 媒体上传 API 投递纯文本日志文件
        curl -fsS -X POST \
            -H "Authorization: Bearer ${token}" \
            -H "Content-Type: text/plain" \
            --data-binary @"$LOG_FILE" \
            "https://storage.googleapis.com/upload/storage/v1/b/${bucket}/o?uploadType=media&name=deploy-${run_id}-${status}.log" || true
    else
        log "Missing metadata or token; unable to upload result to GCS"
    fi
}

stop_existing_services() {
    # 使用 stop 而非 down：只停止进程，保留容器/网络/卷
    # 优势：减少服务中断时间（容器无需重建），down 会额外删除容器和网络
    local compose_dir
    for compose_dir in "$APP_DIR" "$BACKUP_DIR" /root/app /home/*/app; do
        if [[ -f "${compose_dir}/docker-compose.yml" ]]; then
            log "Gracefully stopping services in ${compose_dir}"
            (cd "$compose_dir" && docker compose stop --timeout 30) || true
        fi
    done
}

download_package() {
    local bucket="$1"
    local object="$2"
    local token
    token="$(oauth_token)"
    if [[ -z "$token" ]]; then
        log "Failed to obtain instance service account token"
        return 1
    fi

    log "Downloading deployment package gs://${bucket}/${object}"
    curl -fL \
        -H "Authorization: Bearer ${token}" \
        "https://storage.googleapis.com/storage/v1/b/${bucket}/o/${object}?alt=media" \
        -o "$PACKAGE_FILE"
}

deploy_package() {
    rm -f "$READY_FILE" "$FAILED_FILE"
    stop_existing_services

    log "Backing up current deployment"
    rm -rf "$BACKUP_DIR" "$DATA_BACKUP_DIR"
    [[ -d "$APP_DIR" ]] && mv "$APP_DIR" "$BACKUP_DIR"
    [[ -d "${DATA_DIR}/sing-box" ]] && cp -a "${DATA_DIR}/sing-box" "$DATA_BACKUP_DIR"

    log "Extracting new deployment"
    mkdir -p "$APP_DIR"
    tar -xzf "$PACKAGE_FILE" -C "$APP_DIR"
    chmod +x "${APP_DIR}/deploy.sh"

    # 首次部署或检测到系统级日志配置缺失时，自动供给主机环境
    local need_provision=false
    if ! command -v docker &>/dev/null; then
        need_provision=true
    elif [[ ! -f "/etc/docker/daemon.json" ]]; then
        need_provision=true
    elif [[ ! -f "/etc/google-cloud-ops-agent/config.yaml" ]] || ! grep -q "systemd_journald" "/etc/google-cloud-ops-agent/config.yaml"; then
        need_provision=true
    fi

    if [[ "$need_provision" == "true" ]]; then
        log "Host configuration missing or incomplete, running provision.sh"
        chmod +x "${APP_DIR}/provision.sh"
        if ! (
            cd "$APP_DIR"
            export DATA_ROOT="$DATA_DIR"
            export SING_BOX_DATA_DIR="${DATA_DIR}/sing-box"
            ./provision.sh
        ); then
            log "Provisioning failed"
            exit 1
        fi
        log "Provisioning completed"
    else
        log "Host already provisioned and configured, skipping provision.sh"
    fi

    log "Running deploy.sh"
    if ! (
        cd "$APP_DIR"
        export DATA_ROOT="$DATA_DIR"
        export SING_BOX_DATA_DIR="${DATA_DIR}/sing-box"
        ./deploy.sh
    ); then
        log "deploy.sh failed"
        rollback
        exit 1
    fi

    log "Deployment succeeded"
    rm -rf "$BACKUP_DIR" "$DATA_BACKUP_DIR" "$PACKAGE_FILE"
    date -Is > "$READY_FILE"
    upload_log success
}

rollback() {
    log "Deployment failed, rolling back"
    echo "$(date -Is) deployment failed" > "$FAILED_FILE"

    # 先停止失败的新版本（如果已经启动了部分服务）
    if [[ -f "${APP_DIR}/docker-compose.yml" ]]; then
        log "Stopping failed new services"
        (cd "$APP_DIR" && docker compose stop --timeout 15) || true
    fi

    rm -rf "$APP_DIR"
    [[ -d "$BACKUP_DIR" ]] && mv "$BACKUP_DIR" "$APP_DIR"

    rm -rf "${DATA_DIR}/sing-box"
    if [[ -d "$DATA_BACKUP_DIR" ]]; then
        mv "$DATA_BACKUP_DIR" "${DATA_DIR}/sing-box"
    fi

    if [[ -f "${APP_DIR}/docker-compose.yml" ]]; then
        log "Restarting previous deployment"
        (cd "$APP_DIR" && docker compose up -d) || true
    fi

    upload_log failed
}

main() {
    log "Proxy bootstrap started"

    local bucket object run_id
    bucket="$(metadata proxy-deploy-bucket)"
    object="$(metadata proxy-deploy-object)"
    run_id="$(metadata proxy-deploy-run-id || true)"

    log "Deploy run: ${run_id:-unknown}"
    if [[ -z "$bucket" || -z "$object" ]]; then
        log "Missing deployment metadata"
        exit 1
    fi

    # 明确导出路径变量，覆盖 deploy.sh 内 init_env() 的默认值（/opt/proxy/data）
    # 使 deploy.sh 及其 source 的子脚本（init-data-dir.sh 等）使用 bootstrap 指定的路径
    export DATA_ROOT="$DATA_DIR"
    export SING_BOX_DATA_DIR="${DATA_DIR}/sing-box"
    log "DATA_ROOT=${DATA_ROOT}"
    log "SING_BOX_DATA_DIR=${SING_BOX_DATA_DIR}"

    download_package "$bucket" "$object"
    if ! deploy_package; then
        rollback
        exit 1
    fi

    log "Proxy bootstrap finished"
}

main "$@"

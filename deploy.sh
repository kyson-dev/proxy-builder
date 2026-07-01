#!/bin/bash
# ==============================================================================
# 代理服务部署脚本 (Sing-box)
#
# 前置条件: 主机已由 provision.sh 完成供给（Docker 已安装、jq 已安装）。
# 此脚本只负责应用层部署，不做任何系统级初始化。
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="${SCRIPT_DIR}/scripts"

# 加载通用库
source "${SCRIPTS_DIR}/lib/common.sh"
source "${SCRIPTS_DIR}/lib/docker.sh"

# 加载部署所需模块
source "${SCRIPTS_DIR}/deploy/validate-env.sh"
source "${SCRIPTS_DIR}/deploy/init-env.sh"
source "${SCRIPTS_DIR}/deploy/init-data-dir.sh"
source "${SCRIPTS_DIR}/deploy/generate-certs.sh"
source "${SCRIPTS_DIR}/deploy/build-config.sh"
source "${SCRIPTS_DIR}/deploy/start-services.sh"
source "${SCRIPTS_DIR}/deploy/health-check.sh"

# ==============================================================================
# 前置断言：检查主机环境是否已就绪
# ==============================================================================
assert_provisioned() {
    local failed=false

    if ! command -v docker &>/dev/null; then
        log_error "前置条件未满足: Docker 未安装"
        failed=true
    elif ! docker info &>/dev/null && ! sudo docker info &>/dev/null; then
        log_error "前置条件未满足: Docker daemon 未运行"
        failed=true
    fi

    if ! command -v jq &>/dev/null; then
        log_error "前置条件未满足: jq 未安装"
        failed=true
    fi

    if [[ "$failed" == "true" ]]; then
        die "请先运行 ./provision.sh 完成主机初始化后再执行此脚本"
    fi
}

# ==============================================================================
# 主流程
# ==============================================================================
main() {
    local start_time
    start_time=$(date +%s)

    print_header "部署 Sing-box 代理服务"

    # 前置断言：确认主机已就绪
    assert_provisioned

    # Step 1: 初始化环境变量（补充默认路径并写入 .env）
    init_env "${SCRIPT_DIR}/.env"

    # Step 2: 验证必要配置（REALITY_PRIVATE_KEY 等核心参数）
    validate_env "${SCRIPT_DIR}/.env"
    echo ""

    # Step 3: 初始化数据目录
    init_data_dir
    echo ""

    # Step 4: 生成自签名证书
    generate_certs "${SING_BOX_DATA_DIR}/cert"
    echo ""

    # Step 5: 构建 sing-box config.json
    build_config
    echo ""

    # Step 6: 启动服务
    start_services "docker-compose.yml"
    echo ""

    # Step 7: 健康检查
    if health_check 5; then
        local end_time duration
        end_time=$(date +%s)
        duration=$((end_time - start_time))
        echo ""
        print_separator
        log_success "部署成功！耗时: ${duration}s"
        print_separator
        exit 0
    else
        echo ""
        log_error "健康检查失败"
        exit 1
    fi
}

main "$@"

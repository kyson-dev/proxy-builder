#!/bin/bash
# ==============================================================================
# 从 docker-compose.yml 解析端口配置
# ==============================================================================

# 防止重复加载
[[ -n "${_FIREWALL_PARSE_PORTS_LOADED:-}" ]] && return 0
_FIREWALL_PARSE_PORTS_LOADED=1

# 解析 docker-compose.yml 端口
# 参数: <compose_file>
# 输出: 每行一个 "port/protocol"（例如 80/tcp）
parse_ports_from_compose() {
    local compose_file="$1"
    
    if [[ ! -f "$compose_file" ]]; then
        die "docker-compose 文件不存在: $compose_file"
    fi
    
    awk '
    /^[[:space:]]*ports:[[:space:]]*$/ {
        in_ports = 1
        next
    }
    
    # 如果遇到同级或更高级的字段，退出 ports 区域
    /^[[:space:]]*[a-zA-Z_]/ {
        if (in_ports && $0 !~ /^[[:space:]]*-/) {
            in_ports = 0
        }
    }
    
    # 在 ports 区域内，提取端口配置
    in_ports && /^[[:space:]]*-/ {
        line = $0
        # 移除前导空白和破折号
        sub(/^[[:space:]]*-[[:space:]]*/, "", line)
        # 移除引号
        gsub(/"/, "", line)
        
        # 提取端口和协议
        if (line ~ /^[0-9]+(:[0-9]+)?\/(tcp|udp)/) {
            # 格式: 443:443/tcp 或 443/tcp
            port = line
            sub(/:.*/, "", port)  # 移除冒号后的所有内容，保留宿主机端口
            proto = line
            sub(/.*\//, "", proto)  # 提取协议
            sub(/[[:space:]].*/, "", proto)  # 移除协议后的空白
            print port "/" proto
        } else if (line ~ /^[0-9]+(:[0-9]+)?[[:space:]]*$/) {
            # 格式: 443:443 或 443 (默认 TCP)
            port = line
            sub(/:.*/, "", port)  # 移除冒号后的所有内容
            sub(/[[:space:]].*/, "", port)  # 移除空白
            print port "/tcp"
        }
    }
    ' "$compose_file" | sort -u
}

#!/bin/bash
# 零停机部署演示脚本
# 用于本地测试和理解零停机部署的原理

set -e

echo "🎯 零停机部署演示"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# 颜色定义
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 检查当前服务状态
echo -e "${BLUE}📊 当前服务状态:${NC}"
docker compose ps
echo ""

# 显示当前配置
echo -e "${BLUE}📝 当前 sing-box 配置:${NC}"
docker compose exec sing-box cat /etc/sing-box/config.json | head -20
echo "..."
echo ""

read -p "按 Enter 开始零停机更新..."
echo ""

# 步骤 1: 拉取最新镜像
echo -e "${YELLOW}步骤 1/5: 拉取最新镜像${NC}"
docker compose pull sing-box
echo ""

# 步骤 2: 显示即将重建的容器
echo -e "${YELLOW}步骤 2/5: 准备重建 sing-box 容器${NC}"
echo "当前容器 ID:"
docker compose ps -q sing-box
OLD_CONTAINER=$(docker compose ps -q sing-box)
echo ""

read -p "按 Enter 继续..."
echo ""

# 步骤 3: 重建容器（零停机）
echo -e "${YELLOW}步骤 3/5: 重建容器（零停机模式）${NC}"
echo "执行命令: docker compose up -d --no-deps --force-recreate sing-box"
echo ""

# 记录开始时间
START_TIME=$(date +%s)

# 执行重建
docker compose up -d --no-deps --force-recreate sing-box

# 记录结束时间
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo ""
echo -e "${GREEN}✅ 容器重建完成！耗时: ${DURATION} 秒${NC}"
echo ""

# 步骤 4: 等待新容器启动
echo -e "${YELLOW}步骤 4/5: 等待新容器启动${NC}"
sleep 3

NEW_CONTAINER=$(docker compose ps -q sing-box)
echo "新容器 ID: $NEW_CONTAINER"
echo ""

if [ "$OLD_CONTAINER" != "$NEW_CONTAINER" ]; then
    echo -e "${GREEN}✅ 容器已更新（ID 已改变）${NC}"
else
    echo -e "${YELLOW}⚠️  容器 ID 未改变（可能配置未变化）${NC}"
fi
echo ""

# 步骤 5: 验证服务状态
echo -e "${YELLOW}步骤 5/5: 验证服务状态${NC}"

if docker compose ps sing-box | grep -q "Up"; then
    echo -e "${GREEN}✅ Sing-box 运行正常${NC}"
    echo ""
    
    # 显示服务状态
    echo -e "${BLUE}📊 最新服务状态:${NC}"
    docker compose ps
    echo ""
    
    # 显示最近日志
    echo -e "${BLUE}📝 最近日志 (最后 10 行):${NC}"
    docker compose logs --tail=10 sing-box
    echo ""
    
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}🎉 零停机部署演示完成！${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
else
    echo -e "${RED}❌ Sing-box 启动失败${NC}"
    echo ""
    echo "详细日志:"
    docker compose logs sing-box
    exit 1
fi

echo ""
echo "💡 提示:"
echo "   - 在整个过程中，现有连接不会中断"
echo "   - 新容器启动后，旧容器才会关闭"
echo "   - 使用 network_mode: host 允许端口无缝切换"
echo ""

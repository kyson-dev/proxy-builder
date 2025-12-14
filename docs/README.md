# WIF 配置文档索引

## 📖 文档导航

根据您的需求选择合适的文档：

### 🚀 快速开始（推荐从这里开始）

**[WIF-SUMMARY.md](./WIF-SUMMARY.md)** - 配置总结
- ✅ 最简洁的配置说明
- ✅ 3 步完成配置
- ✅ 清晰的对比表格
- **适合：首次配置，想快速上手**

---

### 📋 配置清单

**[WIF-CHECKLIST.md](./WIF-CHECKLIST.md)** - 快速参考清单
- ✅ 配置项清单
- ✅ GitHub Secrets 列表
- ✅ 验证步骤
- ✅ 常见问题
- **适合：配置时对照检查**

---

### 📚 完整指南

**[WIF-SETUP-GUIDE.md](./WIF-SETUP-GUIDE.md)** - 详细配置指南
- ✅ 前置准备说明
- ✅ 详细的步骤说明
- ✅ 故障排查指南
- ✅ 安全最佳实践
- **适合：想深入了解每个步骤**

---

### 📊 流程图

**[WIF-FLOWCHART.md](./WIF-FLOWCHART.md)** - 可视化流程
- ✅ ASCII 流程图
- ✅ 配置对比表
- ✅ Secrets 清单
- **适合：理解整体架构**

---

### ❓ 常见问题

**[WIF-FAQ.md](./WIF-FAQ.md)** - 常见问题解答
- ✅ Service Account 会重复创建吗？
- ✅ VM_NAME/VM_ZONE 可以跳过吗？
- ✅ 什么是 OS Login？
- ✅ 部署失败怎么办？
- **适合：遇到问题或有疑问时查看**

---

## 🎯 推荐阅读顺序

### 首次配置
1. **[WIF-SUMMARY.md](./WIF-SUMMARY.md)** - 了解概况（5 分钟）
2. **[WIF-CHECKLIST.md](./WIF-CHECKLIST.md)** - 准备配置信息（3 分钟）
3. 运行 `make setup-wif` - 执行配置（5 分钟）
4. 运行 `make push-env` - 上传环境变量（1 分钟）
5. `git push origin main` - 触发部署（自动）

### 遇到问题
1. **[WIF-FAQ.md](./WIF-FAQ.md)** - 查看常见问题解答
2. **[WIF-CHECKLIST.md](./WIF-CHECKLIST.md)** - 查看配置清单
3. **[WIF-SETUP-GUIDE.md](./WIF-SETUP-GUIDE.md)** - 查看故障排查章节

### 深入了解
1. **[WIF-FLOWCHART.md](./WIF-FLOWCHART.md)** - 理解架构
2. **[WIF-SETUP-GUIDE.md](./WIF-SETUP-GUIDE.md)** - 了解每个步骤的细节

---

## 🔧 核心文件

| 文件 | 作用 |
|------|------|
| `scripts/setup-wif.sh` | WIF 自动配置脚本 |
| `.github/workflows/deploy.yml` | GitHub Actions 部署流程 |
| `Makefile` | 便捷命令工具 |

---

## 📝 快速命令参考

```bash
# 查看所有可用命令
make help

# WIF 配置（一次性）
make setup-wif

# 上传环境变量
make push-env

# 生成工具
make uuid          # UUID
make short-id      # Short ID
make password      # 密码
make reality-key   # REALITY 密钥对
```

---

## ✅ 配置检查清单

- [ ] 已阅读 [WIF-SUMMARY.md](./WIF-SUMMARY.md)
- [ ] 已准备好 GCP Project ID、VM Name、VM Zone
- [ ] 已运行 `make setup-wif`
- [ ] 已运行 `make push-env`
- [ ] GitHub Secrets 中有 6 个必需的 Secret
- [ ] 已推送代码触发部署
- [ ] 部署成功

---

## 🆘 需要帮助？

1. 查看 [WIF-CHECKLIST.md](./WIF-CHECKLIST.md) 的常见问题部分
2. 查看 [WIF-SETUP-GUIDE.md](./WIF-SETUP-GUIDE.md) 的故障排查章节
3. 检查 GitHub Actions 日志
4. 检查 GCP Audit Logs

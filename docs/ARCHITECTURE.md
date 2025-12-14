# 配置文件架构说明

## 🏗️ 统一的配置管理模式

本项目采用**统一的配置模板 + entrypoint 脚本**模式，确保所有服务的配置方式一致且易于理解。

---

## 📐 架构设计

### 核心原则

1. **单一配置源（Single Source of Truth）**
   - 所有配置变量只在 `.env` 文件中定义
   - 其他文件通过环境变量引用

2. **模板化配置**
   - 配置文件使用 `.template` 后缀
   - 包含 `${VARIABLE}` 占位符

3. **启动时生成**
   - 通过 `entrypoint.sh` 脚本在容器启动时动态生成最终配置
   - 生成的配置文件不提交到 Git

---

## 🔄 工作流程

```
.env 文件
  ↓ (docker-compose.yml 读取)
环境变量
  ↓ (传递给容器)
entrypoint.sh
  ↓ (读取模板)
*.template
  ↓ (替换变量)
最终配置文件
  ↓ (启动服务)
服务运行
```

---

## 📁 文件结构

### Nginx 服务

```
nginx/
├── entrypoint.sh           # 启动脚本
├── nginx.conf.template     # 配置模板（包含 ${DOMAIN}）
└── nginx.conf              # 生成的配置（.gitignore）
```

**工作流程：**
1. Docker Compose 启动 nginx 容器
2. 执行 `entrypoint.sh`
3. 从 `nginx.conf.template` 生成 `nginx.conf`
4. 替换 `${DOMAIN}` 为实际域名
5. 验证配置：`nginx -t`
6. 启动 Nginx

### Sing-box 服务

```
sing-box/
├── entrypoint.sh              # 启动脚本
├── config.json.template       # 配置模板（包含多个变量）
└── config.json                # 生成的配置（运行时创建）
```

**工作流程：**
1. Docker Compose 启动 sing-box 容器
2. 执行 `entrypoint.sh`
3. 从 `config.json.template` 生成 `config.json`
4. 替换所有 `${VARIABLE}` 占位符
5. 验证配置：`sing-box check`
6. 启动 Sing-box

---

## 🔧 entrypoint.sh 脚本结构

两个服务的 entrypoint 脚本遵循相同的模式：

```bash
#!/bin/sh
set -e

# 1. 检查模板文件是否存在
if [ ! -f /path/to/template ]; then
  echo "Error: template not found"
  exit 1
fi

# 2. 检查必需的环境变量
if [ -z "$REQUIRED_VAR" ]; then
  echo "Error: REQUIRED_VAR is missing"
  exit 1
fi

# 3. 生成配置
echo "Generating configuration from template..."
cp /path/to/template /path/to/config
sed -i "s|\${VAR}|$VAR|g" /path/to/config

# 4. 验证配置
echo "Validating configuration..."
if ! validate-command; then
  echo "Error: Invalid configuration"
  cat /path/to/config
  exit 1
fi

# 5. 启动服务
echo "Starting service..."
exec service-command
```

---

## 📝 配置变量

### Nginx 需要的变量

| 变量 | 说明 | 示例 |
|------|------|------|
| `DOMAIN` | 域名 | `example.com` |

### Sing-box 需要的变量

| 变量 | 说明 | 示例 |
|------|------|------|
| `DOMAIN` | 域名 | `example.com` |
| `VLESS_UUID` | VLESS UUID | `123e4567-e89b-...` |
| `REALITY_PRIVATE_KEY` | Reality 私钥 | `abc123...` |
| `REALITY_SHORT_ID` | Reality Short ID | `a1b2c3d4` |
| `H2_PASSWORD` | Hysteria2 密码 | `secure_pass` |
| `TUIC_UUID` | TUIC UUID | `123e4567-e89b-...` |
| `TUIC_PASSWORD` | TUIC 密码 | `secure_pass` |

---

## 🎯 优势

### 1. **一致性**
- 所有服务使用相同的配置模式
- 降低学习成本
- 易于维护

### 2. **安全性**
- 敏感信息只在 `.env` 中
- `.env` 在 `.gitignore` 中
- 生成的配置文件不提交

### 3. **灵活性**
- 修改配置只需编辑 `.env`
- 无需修改模板文件
- 支持多环境部署

### 4. **可调试性**
- 启动时验证配置
- 配置错误会输出详细信息
- 容易定位问题

---

## 🔄 更新配置流程

### 本地开发

```bash
# 1. 修改 .env
vim .env

# 2. 重启服务
docker compose down
docker compose up -d

# entrypoint.sh 会自动重新生成配置
```

### 生产环境（GitHub Actions）

```bash
# 1. 修改本地 .env
vim .env

# 2. 同步到 GitHub Secrets
make push-env

# 3. 推送代码触发部署
git push origin main

# GitHub Actions 会：
# - 在 VM 上创建新的 .env
# - 重启 Docker Compose
# - entrypoint.sh 自动生成配置
```

---

## 🛠️ 添加新服务

如果要添加新服务，遵循相同模式：

1. **创建模板文件**
   ```
   service/config.template
   ```

2. **创建 entrypoint 脚本**
   ```bash
   #!/bin/sh
   set -e
   # 检查 → 生成 → 验证 → 启动
   ```

3. **更新 docker-compose.yml**
   ```yaml
   service:
     entrypoint: /entrypoint.sh
     volumes:
       - ./service/entrypoint.sh:/entrypoint.sh:ro
       - ./service/config.template:/config.template:ro
     environment:
       - VAR=${VAR}
   ```

4. **更新 .env**
   ```bash
   VAR=value
   ```

---

## 📚 相关文档

- [WIF 配置指南](./WIF-SETUP-GUIDE.md)
- [域名更换指南](../scripts/change-domain.sh)
- [部署流程](../deploy.sh)

---

## ✅ 检查清单

配置新环境时，确保：

- [ ] `.env` 文件包含所有必需变量
- [ ] 模板文件使用 `${VARIABLE}` 格式
- [ ] entrypoint.sh 有执行权限（`chmod +x`）
- [ ] docker-compose.yml 正确挂载模板和脚本
- [ ] 生成的配置文件在 `.gitignore` 中
- [ ] 环境变量正确传递给容器

---

## 🎓 设计理念

这种架构设计遵循了以下软件工程原则：

1. **DRY (Don't Repeat Yourself)**
   - 配置只定义一次

2. **Separation of Concerns**
   - 配置（.env）与模板（.template）分离

3. **Fail Fast**
   - 启动时验证配置，尽早发现错误

4. **Convention over Configuration**
   - 统一的命名和结构约定

5. **Infrastructure as Code**
   - 所有配置都是代码，可版本控制

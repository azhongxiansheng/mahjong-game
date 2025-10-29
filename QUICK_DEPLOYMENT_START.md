# 🚀 麻将游戏 v1.0.0 - 快速部署指南

**难度**: ⭐ 非常简单  
**时间**: ⏱️ 5-10 分钟  
**前提**: 已安装 Docker 和 Docker Compose  

---

## 📋 部署前检查清单

在开始部署前，请确保您有：

- [ ] Docker 已安装 (查看下面的安装方法)
- [ ] Docker Compose 已安装
- [ ] 稳定的网络连接
- [ ] 至少 5GB 的磁盘空间
- [ ] 管理员权限 (某些操作需要)

### 检查是否已安装 Docker

打开终端/命令行，输入：

```bash
docker --version
docker-compose --version
```

如果显示版本号，说明已安装。如果没有，请看下面的安装说明。

---

## 💾 第一步: 安装 Docker（如果未安装）

### Windows 用户

1. **下载 Docker Desktop**
   - 访问: https://www.docker.com/products/docker-desktop
   - 点击 "Download for Windows"

2. **安装**
   - 运行下载的安装程序
   - 按照提示完成安装
   - 可能需要重启电脑

3. **启动 Docker Desktop**
   - 安装完成后启动应用
   - 等待 Docker 启动完成 (看到"Docker is running"提示)

### Mac 用户

```bash
# 使用 Homebrew 安装
brew install --cask docker
```

### Linux 用户

```bash
# Ubuntu/Debian
sudo apt-get update
sudo apt-get install docker.io docker-compose

# 启动 Docker
sudo systemctl start docker
```

---

## 📥 第二步: 获取项目代码

### 方式 1: 使用 Git 克隆（推荐）

```bash
# 打开终端/命令行

# 1. 进入你想放置项目的目录
cd D:\projects
# 或者 Mac/Linux: cd ~/projects

# 2. 克隆项目
git clone https://github.com/yourusername/mahjong-game.git

# 3. 进入项目目录
cd mahjong-game

# 4. 切换到最新发布版本
git checkout v1.0.0
```

### 方式 2: 下载 ZIP 文件

1. 访问 GitHub: https://github.com/yourusername/mahjong-game
2. 点击 "Code" → "Download ZIP"
3. 解压到你的计算机
4. 进入解压后的目录

### 验证项目结构

进入项目目录后，你应该看到：

```
mahjong-game/
├── docker-compose.yml      ✅ Docker 编排文件
├── Dockerfile              ✅ 镜像定义
├── backend/                ✅ 后端代码
├── godot/                  ✅ 前端代码
├── README.md               ✅ 项目说明
└── ...其他文件
```

---

## ⚙️ 第三步: 配置环境变量

### 步骤 1: 创建 .env 文件

在项目根目录创建一个 `.env` 文件：

```bash
# Windows (PowerShell)
New-Item -Path ".env" -ItemType File

# Mac/Linux
touch .env
```

### 步骤 2: 填写配置

用文本编辑器打开 `.env` 文件，添加以下内容：

```env
# 数据库配置
DB_HOST=db
DB_PORT=3306
DB_USER=root
DB_PASSWORD=mahjong123456
DB_NAME=mahjong

# API 配置
API_PORT=8080
API_HOST=0.0.0.0

# JWT 配置
JWT_SECRET=your-secret-key-here-change-this-in-production

# 环境
ENVIRONMENT=production
LOG_LEVEL=info
```

### 步骤 3: 保存文件

保存并关闭 `.env` 文件。

---

## 🐳 第四步: 启动 Docker 容器

### 步骤 1: 启动所有服务

打开终端/命令行，确保你在项目目录中：

```bash
# 确认位置
pwd  # Mac/Linux 显示当前目录
cd   # Windows PowerShell 显示当前目录

# 应该在 .../mahjong-game

# 启动所有服务
docker-compose up -d
```

### 预期输出

```
Creating mahjong_db_1     ... done
Creating mahjong_backend_1 ... done
Creating mahjong_nginx_1   ... done
```

### 步骤 2: 等待服务完全启动

```bash
# 查看日志（确认没有错误）
docker-compose logs -f backend
```

等待看到类似的输出：

```
backend_1  | 2025-11-16 10:00:00 Server running on :8080
backend_1  | ✅ Database connected successfully
backend_1  | ✅ All systems ready
```

按 `Ctrl+C` 退出日志查看。

---

## ✅ 第五步: 验证部署成功

### 检查 1: 服务状态

```bash
# 查看所有容器状态
docker-compose ps

# 预期输出
# NAME                COMMAND                STATUS      PORTS
# mahjong_backend_1   "go run main.go"      Up 2 mins   0.0.0.0:8080->8080/tcp
# mahjong_db_1        "docker-entrypoint"   Up 2 mins   0.0.0.0:3306->3306/tcp
# mahjong_nginx_1     "nginx -g daemon off" Up 2 mins   0.0.0.0:80->80/tcp
```

所有服务应该显示 `Up` 状态。

### 检查 2: 健康检查

在浏览器中打开，或使用命令行：

```bash
# 方法 1: 使用 curl（命令行）
curl http://localhost:8080/api/health

# 预期响应
# {"status":"ok","timestamp":"2025-11-16T10:00:00Z"}
```

或者在浏览器中访问：
```
http://localhost:8080/api/health
```

### 检查 3: 数据库连接

```bash
# 检查数据库连接
curl http://localhost:8080/api/db/health

# 预期响应
# {"database":"connected","latency":"5ms"}
```

### 检查 4: 查看应用日志

```bash
# 查看后端日志
docker-compose logs backend

# 查看数据库日志
docker-compose logs db

# 查看所有日志
docker-compose logs
```

---

## 🎮 第六步: 访问应用

### 后端 API

```
API 地址: http://localhost:8080
API 文档: http://localhost:8080/api/docs
```

### 健康检查端点

```bash
# 系统状态
curl http://localhost:8080/api/health

# 数据库状态
curl http://localhost:8080/api/db/health

# WebSocket 状态
curl http://localhost:8080/api/ws/health
```

### 测试 API 端点

```bash
# 1. 注册用户
curl -X POST http://localhost:8080/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "username": "testuser",
    "password": "Test@123456",
    "email": "test@example.com"
  }'

# 2. 登录
curl -X POST http://localhost:8080/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "username": "testuser",
    "password": "Test@123456"
  }'

# 预期响应包含 JWT token
# {"token":"eyJhbGc...","user":{"id":1,"username":"testuser"}}

# 3. 获取排行榜
curl http://localhost:8080/api/leaderboard/daily

# 4. 获取用户信息（需要 token）
curl http://localhost:8080/api/user/profile \
  -H "Authorization: Bearer YOUR_JWT_TOKEN"
```

---

## 🔄 常见操作

### 查看日志

```bash
# 实时查看后端日志
docker-compose logs -f backend

# 查看最后 100 行日志
docker-compose logs --tail 100

# 只查看错误日志
docker-compose logs backend | grep ERROR
```

### 停止服务

```bash
# 停止所有服务（但数据保存）
docker-compose stop

# 停止特定服务
docker-compose stop backend
```

### 重启服务

```bash
# 重启所有服务
docker-compose restart

# 重启特定服务
docker-compose restart backend
```

### 完全删除（谨慎操作）

```bash
# 删除所有容器和网络（数据保存在卷中）
docker-compose down

# 删除所有容器、网络和数据卷（⚠️ 会删除数据库数据）
docker-compose down -v
```

### 查看资源使用

```bash
# 查看 CPU 和内存使用
docker stats

# 查看磁盘使用
docker system df
```

---

## 🔌 数据库访问

### 使用 MySQL 客户端连接

```bash
# 连接信息
Host: localhost
Port: 3306
Username: root
Password: mahjong123456
Database: mahjong

# 命令行连接
mysql -h 127.0.0.1 -u root -p
# 输入密码: mahjong123456
```

### 查看数据库中的数据

```bash
# 进入 MySQL 容器
docker-compose exec db mysql -u root -pmahjong123456

# 在 MySQL 中执行
USE mahjong;
SHOW TABLES;
SELECT * FROM users LIMIT 5;
```

---

## 🧪 测试部署

### 完整测试流程

```bash
# 1. 检查所有容器运行状态
docker-compose ps

# 2. 检查系统健康
curl http://localhost:8080/api/health

# 3. 创建测试用户
curl -X POST http://localhost:8080/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "username": "testplayer",
    "password": "Test@123456",
    "email": "player@test.com"
  }'

# 4. 登录获取 token
TOKEN=$(curl -s -X POST http://localhost:8080/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "username": "testplayer",
    "password": "Test@123456"
  }' | grep -o '"token":"[^"]*' | cut -d'"' -f4)

echo "Token: $TOKEN"

# 5. 使用 token 获取排行榜
curl http://localhost:8080/api/leaderboard/daily \
  -H "Authorization: Bearer $TOKEN"

# 6. 获取用户信息
curl http://localhost:8080/api/user/profile \
  -H "Authorization: Bearer $TOKEN"

# 7. 查看日志确保没有错误
docker-compose logs --tail 50
```

---

## ⚠️ 常见问题和解决方案

### 问题 1: "Docker daemon is not running"

**症状**: 执行 Docker 命令时出现此错误

**解决方案**:
```bash
# Windows: 启动 Docker Desktop 应用
# Mac: 启动 Docker Desktop 应用
# Linux: 启动 Docker 服务
sudo systemctl start docker
```

### 问题 2: "Port 8080 is already in use"

**症状**: 端口被占用

**解决方案**:
```bash
# 方法 1: 使用不同的端口
# 编辑 docker-compose.yml，改变 8080 映射

# 方法 2: 停止占用端口的进程
# Windows: netstat -ano | findstr :8080
# Mac/Linux: lsof -i :8080
```

### 问题 3: "Cannot connect to database"

**症状**: API 返回数据库连接错误

**解决方案**:
```bash
# 1. 检查数据库容器状态
docker-compose ps db

# 2. 查看数据库日志
docker-compose logs db

# 3. 等待数据库完全启动（可能需要 30 秒）
sleep 30

# 4. 重启数据库
docker-compose restart db
```

### 问题 4: "Out of memory" 错误

**症状**: 容器因内存不足而崩溃

**解决方案**:
```bash
# 1. 检查系统内存
docker stats

# 2. 删除未使用的镜像和容器
docker system prune

# 3. 增加 Docker 内存限制
# Windows/Mac: Docker Desktop → Preferences → Resources
```

### 问题 5: 部署后网页无法访问

**症状**: 浏览器访问 localhost:8080 无响应

**解决方案**:
```bash
# 1. 检查容器是否运行
docker-compose ps

# 2. 检查日志
docker-compose logs backend

# 3. 检查端口映射
docker port <container-name>

# 4. 尝试使用 127.0.0.1 而不是 localhost
curl http://127.0.0.1:8080/api/health
```

---

## 📊 监控和维护

### 实时监控

```bash
# 查看资源使用情况
watch docker stats

# 查看容器网络连接
docker network inspect mahjong_default
```

### 日志管理

```bash
# 查看最近的日志
docker-compose logs --tail 100

# 查看特定时间范围的日志
docker-compose logs --since 2025-11-16T10:00:00

# 保存日志到文件
docker-compose logs > deployment.log
```

### 性能测试

```bash
# 查看 API 响应时间
time curl http://localhost:8080/api/health

# 并发连接测试
ab -n 1000 -c 100 http://localhost:8080/api/health
```

---

## 🔐 安全建议

### 部署到生产环境前

- [ ] 更改 `.env` 中的所有默认密码
- [ ] 更改 JWT_SECRET 为强随机字符串
- [ ] 启用 HTTPS/SSL
- [ ] 配置防火墙规则
- [ ] 设置自动备份
- [ ] 启用监控告警

### 生成强密码

```bash
# Linux/Mac
openssl rand -base64 32

# 或使用在线工具
# https://www.random.org/strings/
```

### 更新 .env 文件

```env
# 生成新的安全密钥
DB_PASSWORD=<use-strong-password>
JWT_SECRET=<generate-random-string>
```

---

## 🚀 下一步

### 部署成功后

1. **配置监控**
   ```bash
   # 访问 Prometheus
   http://localhost:9090
   
   # 访问 Grafana (如果配置)
   http://localhost:3000
   ```

2. **检查日志**
   ```bash
   docker-compose logs -f
   ```

3. **创建备份**
   ```bash
   docker-compose exec db mysqldump -u root -pmahjong123456 mahjong > backup.sql
   ```

4. **文档阅读**
   - 完整部署指南: `DEPLOYMENT_GUIDE.md`
   - 发布后操作: `POST_LAUNCH_GUIDE.md`
   - 故障排除: `TROUBLESHOOTING.md`

---

## 📞 获取帮助

遇到问题？

1. **查看日志**: `docker-compose logs`
2. **阅读文档**: 查看项目的 MD 文件
3. **常见问题**: 本指南的"常见问题"部分
4. **提交 Issue**: GitHub Issues

---

## ✨ 总结

```
部署步骤:
1. ✅ 安装 Docker
2. ✅ 获取项目代码
3. ✅ 配置环境变量
4. ✅ 启动 Docker 容器
5. ✅ 验证部署成功
6. ✅ 访问应用

预期时间:  5-10 分钟
技术要求:  低 (只需一条命令)
可靠性:    高 (Docker 保证)
```

---

**🎉 恭喜！您已成功部署麻将游戏 v1.0.0！**

现在您可以：
- ✅ 访问 API 端点
- ✅ 创建用户账户
- ✅ 测试游戏功能
- ✅ 监控系统运行
- ✅ 收集用户反馈

祝您使用愉快！🎲



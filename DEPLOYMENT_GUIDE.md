# 🚀 部署指南 - Phase 12 Day 2

**日期**: 2025-11-14  
**目标**: 完整的部署说明和配置  
**涵盖**: 开发、测试、生产环境

---

## 📋 部署架构

```
┌─────────────────────────────────────────────────────────┐
│                    Godot 游戏客户端                       │
│                   (Windows/Mac/Linux)                    │
└────────────────────┬────────────────────────────────────┘
                     │
        HTTP + WebSocket (ws://, wss://)
                     │
        ┌────────────▼────────────┐
        │   Nginx/Caddy (反向代理)  │
        │  (SSL/TLS 终止)         │
        └────────────┬────────────┘
                     │
┌────────────────────▼─────────────────────────┐
│          Go 后端服务器 (Gin)                   │
├───────────────────────────────────────────────┤
│  • API 处理器                                 │
│  • WebSocket 连接池                          │
│  • 业务逻辑                                   │
│  • 数据库连接                                │
│  • 日志和监控                                │
└────────────────────┬──────────────────────────┘
                     │
        ┌────────────▼────────────┐
        │   MySQL/PostgreSQL      │
        │   (主从复制)             │
        └─────────────────────────┘
```

---

## 1️⃣ 本地开发环境

### 1.1 前端开发

#### 安装 Godot 4.x
```bash
# macOS
brew install godot

# Windows (使用 scoop 或直接下载)
scoop install godot

# Linux
sudo apt install godot4
```

#### 打开项目
```bash
# 进入 Godot 项目目录
cd D:\MahjongGame\godot

# 使用 Godot 编辑器打开
godot -e
```

#### 运行游戏
```bash
# 方式 1: 在编辑器中按 F5
# 方式 2: 通过命令行
godot --main-scene=scenes/main.tscn
```

### 1.2 后端开发

#### 安装 Go
```bash
# 下载 Go 1.20+ 从 https://golang.org/dl

# 验证安装
go version  # go version go1.20 linux/amd64
```

#### 配置环境

```bash
# 设置环境变量
export GO111MODULE=on
export GOPROXY=https://proxy.golang.org

# Windows PowerShell
$env:GO111MODULE="on"
$env:GOPROXY="https://proxy.golang.org"
```

#### 初始化后端

```bash
# 进入后端目录
cd D:\MahjongGame\backend

# 下载依赖
go mod download

# 安装依赖
go get ./...
```

#### 运行本地服务器

```bash
# 开发模式（自动重载）
# 安装 air
go install github.com/cosmtrek/air@latest

# 运行 air
air

# 或直接运行
go run main.go

# 访问 API
curl http://localhost:8080/api/health
```

### 1.3 数据库设置

#### 安装 SQLite (开发)

```bash
# macOS
brew install sqlite3

# Windows (使用 chocolatey)
choco install sqlite

# Linux
sudo apt install sqlite3
```

#### 初始化开发数据库

```bash
# 进入数据库目录
cd D:\MahjongGame\backend\database

# 创建数据库
sqlite3 mahjong.db < schema.sql

# 验证
sqlite3 mahjong.db ".tables"
```

#### 导入初始数据

```bash
sqlite3 mahjong.db
sqlite> .mode csv
sqlite> .import users.csv users
sqlite> SELECT COUNT(*) FROM users;
```

---

## 2️⃣ 测试环境

### 2.1 Docker 容器化

#### 创建 Dockerfile

```dockerfile
# 后端 Dockerfile
FROM golang:1.20-alpine AS builder

WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o main .

FROM alpine:latest
RUN apk --no-cache add ca-certificates
WORKDIR /root/

COPY --from=builder /app/main .

EXPOSE 8080
CMD ["./main"]
```

#### 构建镜像

```bash
# 构建后端镜像
docker build -t mahjong-backend:latest .

# 运行容器
docker run -p 8080:8080 \
  -e DB_HOST=localhost \
  -e DB_USER=root \
  -e DB_PASSWORD=password \
  mahjong-backend:latest
```

### 2.2 Docker Compose

#### docker-compose.yml

```yaml
version: '3.8'

services:
  db:
    image: mysql:8.0
    environment:
      MYSQL_ROOT_PASSWORD: rootpass
      MYSQL_DATABASE: mahjong
    ports:
      - "3306:3306"
    volumes:
      - db_data:/var/lib/mysql

  backend:
    build: .
    ports:
      - "8080:8080"
    environment:
      DB_HOST: db
      DB_USER: root
      DB_PASSWORD: rootpass
      DB_NAME: mahjong
    depends_on:
      - db
    command: ./main

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"

volumes:
  db_data:
```

#### 启动服务

```bash
# 启动所有服务
docker-compose up -d

# 查看日志
docker-compose logs -f backend

# 停止服务
docker-compose down
```

### 2.3 配置管理

#### 环境配置文件 (.env)

```bash
# 开发环境
ENV=development
DEBUG=true
LOG_LEVEL=debug

# 数据库
DB_HOST=localhost
DB_PORT=3306
DB_USER=root
DB_PASSWORD=devpassword
DB_NAME=mahjong_dev

# API
API_PORT=8080
API_TIMEOUT=30

# WebSocket
WS_TIMEOUT=60
WS_MAX_CONNECTIONS=10000

# JWT
JWT_SECRET=dev-secret-key
JWT_EXPIRY=86400

# CORS
CORS_ALLOWED_ORIGINS=http://localhost:8080,http://localhost:3000
```

#### 加载配置

```go
import "github.com/joho/godotenv"

func init() {
    godotenv.Load(".env")
}

func getConfig(key string) string {
    return os.Getenv(key)
}
```

---

## 3️⃣ 生产环境

### 3.1 服务器准备

#### 云服务器选择

推荐配置:
- **CPU**: 4+ 核心
- **内存**: 8GB+
- **存储**: 100GB SSD
- **带宽**: 10Mbps+
- **操作系统**: Ubuntu 20.04 LTS

#### 服务器初始化

```bash
# 更新系统
sudo apt update
sudo apt upgrade -y

# 安装基础工具
sudo apt install -y build-essential
sudo apt install -y git
sudo apt install -y curl
sudo apt install -y wget

# 安装 Go
wget https://golang.org/dl/go1.20.linux-amd64.tar.gz
sudo tar -C /usr/local -xzf go1.20.linux-amd64.tar.gz
echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
source ~/.bashrc

# 安装 Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# 安装 Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
```

### 3.2 数据库生产部署

#### MySQL 安装

```bash
# 使用 Docker
docker run -d \
  --name mahjong-mysql \
  -e MYSQL_ROOT_PASSWORD=<strong-password> \
  -e MYSQL_DATABASE=mahjong \
  -v mysql_data:/var/lib/mysql \
  -p 3306:3306 \
  mysql:8.0

# 或直接安装
sudo apt install -y mysql-server
sudo mysql_secure_installation
```

#### 数据库优化

```sql
-- 创建用户
CREATE USER 'mahjong'@'localhost' IDENTIFIED BY '<strong-password>';
GRANT ALL PRIVILEGES ON mahjong.* TO 'mahjong'@'localhost';
FLUSH PRIVILEGES;

-- 导入架构
SOURCE /path/to/schema.sql;

-- 创建索引
CREATE INDEX idx_user_email ON users(email);
CREATE INDEX idx_game_status ON games(status);
CREATE INDEX idx_friend_user ON friends(user_id);

-- 优化性能
SET GLOBAL max_connections=1000;
SET GLOBAL innodb_buffer_pool_size=4G;
```

### 3.3 Web 服务器配置

#### Nginx 配置

```nginx
# /etc/nginx/sites-available/mahjong

upstream backend {
    server 127.0.0.1:8080;
}

server {
    listen 80;
    server_name api.mahjong.example.com;
    
    # 重定向到 HTTPS
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name api.mahjong.example.com;
    
    # SSL 证书
    ssl_certificate /etc/letsencrypt/live/api.mahjong.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/api.mahjong.example.com/privkey.pem;
    
    # 安全头
    add_header X-Frame-Options "DENY" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    
    # 反向代理
    location / {
        proxy_pass http://backend;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
    
    # WebSocket
    location /ws {
        proxy_pass http://backend/ws;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "Upgrade";
        proxy_set_header Host $host;
        proxy_read_timeout 3600;
    }
}
```

#### 启用配置

```bash
# 创建符号链接
sudo ln -s /etc/nginx/sites-available/mahjong /etc/nginx/sites-enabled/

# 测试配置
sudo nginx -t

# 重启 Nginx
sudo systemctl restart nginx
```

### 3.4 SSL 证书

#### Let's Encrypt

```bash
# 安装 Certbot
sudo apt install -y certbot python3-certbot-nginx

# 生成证书
sudo certbot certonly --standalone -d api.mahjong.example.com

# 自动续期
sudo certbot renew --dry-run
```

### 3.5 后端服务配置

#### Systemd 服务 (mahjong-backend.service)

```ini
[Unit]
Description=Mahjong Game Backend
After=network.target

[Service]
Type=simple
User=mahjong
WorkingDirectory=/opt/mahjong-backend
ExecStart=/opt/mahjong-backend/main
Restart=always
RestartSec=10

Environment="DB_HOST=localhost"
Environment="DB_USER=mahjong"
Environment="DB_PASSWORD=<strong-password>"
Environment="DB_NAME=mahjong"
Environment="ENV=production"
Environment="LOG_LEVEL=info"

[Install]
WantedBy=multi-user.target
```

#### 启动服务

```bash
# 复制可执行文件
sudo mkdir -p /opt/mahjong-backend
sudo cp ./main /opt/mahjong-backend/

# 启用服务
sudo systemctl enable mahjong-backend
sudo systemctl start mahjong-backend

# 查看状态
sudo systemctl status mahjong-backend

# 查看日志
journalctl -u mahjong-backend -f
```

---

## 4️⃣ 监控和日志

### 4.1 日志管理

#### 日志文件配置

```go
import "log"
import "os"

func setupLogging() {
    logFile, err := os.OpenFile(
        "/var/log/mahjong/backend.log",
        os.O_CREATE|os.O_WRONLY|os.O_APPEND,
        0666,
    )
    if err != nil {
        log.Fatal(err)
    }
    
    log.SetOutput(logFile)
    log.SetFlags(log.LstdFlags | log.Lshortfile)
}
```

#### 日志轮转

```bash
# logrotate 配置 (/etc/logrotate.d/mahjong)
/var/log/mahjong/*.log {
    daily
    rotate 14
    compress
    delaycompress
    notifempty
    create 0640 mahjong mahjong
    sharedscripts
    postrotate
        systemctl reload mahjong-backend > /dev/null 2>&1 || true
    endscript
}
```

### 4.2 监控工具

#### Prometheus 指标

```go
import "github.com/prometheus/client_golang/prometheus"

var (
    requestDuration = prometheus.NewHistogramVec(
        prometheus.HistogramOpts{
            Name: "http_request_duration_seconds",
            Help: "HTTP request latencies",
        },
        []string{"method", "endpoint"},
    )
    
    activeConnections = prometheus.NewGauge(
        prometheus.GaugeOpts{
            Name: "websocket_active_connections",
            Help: "Number of active WebSocket connections",
        },
    )
)

func init() {
    prometheus.MustRegister(requestDuration, activeConnections)
}
```

#### 健康检查端点

```go
router.GET("/health", func(c *gin.Context) {
    c.JSON(200, gin.H{
        "status": "healthy",
        "timestamp": time.Now(),
        "version": "1.0.0",
    })
})

router.GET("/metrics", gin.WrapH(promhttp.Handler()))
```

---

## 5️⃣ 发布流程

### 5.1 代码冻结

```bash
# 标记版本
git tag -a v1.0.0 -m "Release version 1.0.0"
git push origin v1.0.0

# 检查变更
git log v0.9.0..v1.0.0
```

### 5.2 构建发布

```bash
# 构建后端
cd backend
go build -o mahjong-backend

# 构建客户端（Godot）
godot -s --export-release Linux mahjong-linux.x86_64

# 创建发布包
tar -czf mahjong-v1.0.0.tar.gz mahjong-backend

# 计算校验和
sha256sum mahjong-v1.0.0.tar.gz > SHA256SUMS
```

### 5.3 部署到生产

```bash
#!/bin/bash
# deploy.sh

set -e

VERSION=$1
SERVER="deploy@production.server"

# 上传文件
scp mahjong-v${VERSION}.tar.gz ${SERVER}:/tmp/

# 远程执行
ssh ${SERVER} << EOF
    cd /opt/mahjong-backend
    systemctl stop mahjong-backend
    tar -xzf /tmp/mahjong-v${VERSION}.tar.gz
    systemctl start mahjong-backend
    systemctl status mahjong-backend
EOF

echo "Deployment completed successfully"
```

---

## 📋 部署检查清单

### 部署前检查

- [ ] 所有测试通过
- [ ] 代码审查完成
- [ ] 依赖已更新
- [ ] 文档已更新
- [ ] 性能基准测试通过
- [ ] 安全审计通过
- [ ] 备份已准备
- [ ] 回滚计划已制定

### 部署中检查

- [ ] 代码冻结
- [ ] 构建成功
- [ ] 镜像验证
- [ ] 数据库迁移
- [ ] DNS 更新
- [ ] SSL 证书更新

### 部署后检查

- [ ] 健康检查通过
- [ ] 日志监控正常
- [ ] 性能指标正常
- [ ] 用户测试通过
- [ ] 事件日志记录
- [ ] 监控告警配置

---

## 🚀 快速开始

### 一键部署（Docker）

```bash
# 克隆项目
git clone https://github.com/yourusername/mahjong-game.git
cd mahjong-game

# 启动所有服务
docker-compose up -d

# 查看状态
docker-compose ps

# 访问应用
curl http://localhost:8080/api/health
```

---

**部署指南**: ✅ 完成  
**环境支持**: 开发、测试、生产  
**推荐方式**: Docker Compose + Nginx + Let's Encrypt  
**支持团队**: 可联系技术支持

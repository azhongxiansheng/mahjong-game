#!/bin/bash

# 🚀 麻将游戏 v1.0.0 - 云服务器自动部署脚本
# 无需本地虚拱拟化支持
# 适用于: Oracle Cloud, 阿里云, 腾讯云等

set -e  # 任何命令出错都停止

echo "════════════════════════════════════════════════════════════"
echo "🚀 麻将游戏 v1.0.0 - 云服务器自动部署"
echo "════════════════════════════════════════════════════════════"
echo ""

# 第 1 步: 更新系统
echo "📦 Step 1/7: 更新系统包..."
sudo apt-get update
sudo apt-get upgrade -y
echo "✅ 系统包已更新"
echo ""

# 第 2 步: 安装必要工具
echo "📦 Step 2/7: 安装必要工具..."
sudo apt-get install -y \
    curl \
    wget \
    git \
    vim \
    net-tools \
    htop
echo "✅ 必要工具已安装"
echo ""

# 第 3 步: 安装 Docker
echo "🐳 Step 3/7: 安装 Docker..."
sudo apt-get install -y docker.io
sudo systemctl start docker
sudo systemctl enable docker

# 将当前用户添加到 docker 组 (可选，方便后续操作)
sudo usermod -aG docker $USER
echo "✅ Docker 已安装并启动"
echo ""

# 第 4 步: 安装 Docker Compose
echo "🐳 Step 4/7: 安装 Docker Compose..."
sudo apt-get install -y docker-compose
echo "✅ Docker Compose 已安装"
echo ""

# 第 5 步: 克隆麻将游戏项目
echo "📥 Step 5/7: 克隆麻将游戏项目..."
if [ -d "mahjong-game" ]; then
    echo "项目目录已存在，跳过克隆"
else
    git clone https://github.com/yourusername/mahjong-game.git
fi

cd mahjong-game
git checkout v1.0.0
echo "✅ 项目已克隆"
echo ""

# 第 6 步: 创建 .env 配置文件
echo "⚙️ Step 6/7: 创建环境配置文件..."
cat > .env << 'EOF'
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
JWT_SECRET=cloud-deployment-$(date +%s)

# 环境设置
ENVIRONMENT=production
LOG_LEVEL=info

# 时区
TZ=Asia/Shanghai
EOF

echo "✅ 环境配置文件已创建"
echo ""

# 第 7 步: 启动麻将游戏
echo "🚀 Step 7/7: 启动麻将游戏服务..."
sudo docker-compose up -d
echo "✅ 麻将游戏已启动"
echo ""

# 等待服务启动
echo "⏳ 等待服务完全启动 (30 秒)..."
sleep 30
echo ""

# 验证部署
echo "✅ 部署完成！验证结果:"
echo ""
echo "════════════════════════════════════════════════════════════"
echo "📊 容器状态:"
sudo docker-compose ps
echo ""
echo "════════════════════════════════════════════════════════════"
echo "🔍 系统健康检查:"
sudo docker-compose exec -T backend curl -s http://localhost:8080/api/health || echo "等待后端启动..."
echo ""
echo "════════════════════════════════════════════════════════════"
echo ""

# 获取公网 IP
PUBLIC_IP=$(curl -s https://api.ipify.org)
echo "🌍 您的麻将游戏已部署！"
echo ""
echo "访问地址: http://$PUBLIC_IP:8080/api/health"
echo ""
echo "════════════════════════════════════════════════════════════"
echo ""
echo "📋 常用命令:"
echo "  查看日志:     sudo docker-compose logs -f backend"
echo "  查看容器:     sudo docker-compose ps"
echo "  重启服务:     sudo docker-compose restart"
echo "  停止服务:     sudo docker-compose stop"
echo "  启动服务:     sudo docker-compose up -d"
echo ""
echo "════════════════════════════════════════════════════════════"
echo "✨ 部署成功！麻将游戏现在在线！🎲"
echo "════════════════════════════════════════════════════════════"

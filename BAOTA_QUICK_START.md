# 🚀 宝塔面板快速启动 - 5分钟上手

## 📱 一句话总结
**在国内服务器上安装宝塔 → 上传代码 → 启动应用 → 配置反向代理 → 完成！**

---

## ⚡ 最快流程（5 步）

### 步骤 1️⃣：购买服务器（如果还没有）

```
腾讯云/阿里云/华为云 → 买一个 2核2GB Ubuntu 服务器
记下 IP 地址和密码！
```

### 步骤 2️⃣：安装宝塔（一键）

**打开 PuTTY 或 PowerShell，连接服务器后运行：**

```bash
wget -O install.sh http://download.bt.cn/install/install_lts.sh && sudo bash install.sh ed8484bec
```

⏱️ 等待 3-5 分钟...

最后会显示：
```
外网面板地址: http://your-ip:8888
初始用户名: admin
初始密码: xxxxxx
```

✅ **记下这些！**

---

### 步骤 3️⃣：进入宝塔面板

在浏览器中访问：`http://你的IP:8888`

登录 → 初始化 → 选择 LNMP 套件

---

### 步骤 4️⃣：上传代码并启动

**在宝塔的"终端"中执行：**

```bash
# 创建项目目录
mkdir -p /home/mahjong-game

# 上传代码后，进入目录
cd /home/mahjong-game

# 编译
go build -o app main.go

# 后台运行（重要！）
nohup ./app > app.log 2>&1 &

# 验证
ps aux | grep app
```

你会看到类似输出：
```
root  12345  ... ./app
```

✅ **应用已启动！**

---

### 步骤 5️⃣：配置反向代理（可选但推荐）

**在宝塔面板中：**

1. **网站** → **添加站点**
   - 域名: `api.yourdomain.com` (或服务器 IP)
   - 创建

2. **设置** → **反向代理** → **添加反向代理**
   ```
   反向代理目标 URL: http://127.0.0.1:8080
   子目录: /
   提交
   ```

3. **终端**运行：
   ```bash
   systemctl restart nginx
   ```

✅ **完成！现在可以访问了**

---

## 🧪 测试

### 直接访问（推荐用这个测试）

```bash
# 在服务器上运行
curl http://localhost:8080/api/health

# 返回类似：
# {"status":"ok","ready":true,"time":"..."}
```

### 通过 IP 访问（如果配置了反向代理）

```
http://你的服务器IP:8080/api/health
```

### 通过域名访问（如果绑定了域名）

```
https://api.yourdomain.com/api/health
```

---

## 💾 项目文件结构

上传到服务器时，确保包含：

```
mahjong-game/
├── main.go              ✅ 必须有
├── go.mod               ✅ 必须有
├── go.sum               (可选)
└── Dockerfile           (可选)
```

---

## 📊 常见命令速查表

| 操作 | 命令 |
|------|------|
| **查看运行状态** | `ps aux \| grep app` |
| **查看实时日志** | `tail -f app.log` |
| **停止应用** | `pkill -f "./app"` |
| **重新启动** | `pkill -f "./app" && nohup ./app > app.log 2>&1 &` |
| **查看完整日志** | `cat app.log` |
| **重启 Nginx** | `systemctl restart nginx` |

---

## 🔧 如果应用没启动

### 问题排查步骤

```bash
# 1. 进入项目目录
cd /home/mahjong-game

# 2. 查看日志
tail -20 app.log

# 3. 尝试手动运行看有没有错误
go run main.go

# 4. 检查端口是否被占用
lsof -i :8080

# 5. 查看 Go 是否安装
go version
```

### 常见错误

| 错误 | 解决方案 |
|------|---------|
| `command not found: go` | 需要安装 Go（在宝塔软件商店安装） |
| `port already in use` | 有其他应用占用 8080，改端口或停止它 |
| `permission denied` | `chmod +x app` 添加执行权限 |

---

## 🎯 最小化部署脚本

如果想更快，可以把这个保存为 `deploy.sh` 上传到服务器：

```bash
#!/bin/bash

cd /home/mahjong-game

# 停止旧应用
pkill -f "./app" 2>/dev/null || true

# 编译新版本
echo "Building..."
go build -o app main.go

# 启动
echo "Starting..."
nohup ./app > app.log 2>&1 &

# 验证
sleep 2
if ps aux | grep -q "[.]./app"; then
    echo "✅ Success! Application is running"
    ps aux | grep "./app" | grep -v grep
else
    echo "❌ Failed! Check app.log"
    tail -20 app.log
fi
```

使用：
```bash
bash deploy.sh
```

---

## 📞 需要帮助？

| 问题 | 查看 |
|------|------|
| 详细教程 | `BAOTA_DEPLOYMENT_GUIDE.md` |
| 常见问题 | 本文件下方 |
| 命令不懂 | 告诉我命令，我解释 |

---

## ❓ 最常问的问题

### Q: 如何重新启动应用？

```bash
cd /home/mahjong-game
pkill -f "./app"
nohup ./app > app.log 2>&1 &
```

### Q: 如何查看实时日志？

```bash
tail -f /home/mahjong-game/app.log

# 按 Ctrl+C 退出
```

### Q: 怎样确保服务器重启后应用自动启动？

见详细教程第10步"配置开机自启"

### Q: 支持 HTTPS 吗？

支持！在宝塔面板 → 网站 → SSL，申请免费证书

### Q: 如何更新代码？

```bash
# 1. 上传新的 main.go
# 2. 重新编译
cd /home/mahjong-game
go build -o app main.go

# 3. 重启
pkill -f "./app"
nohup ./app > app.log 2>&1 &
```

---

## ✅ 完成清单

- [ ] 服务器已购买
- [ ] 宝塔已安装并可访问
- [ ] Go 已安装（`go version` 能运行）
- [ ] 代码已上传到 `/home/mahjong-game/`
- [ ] 应用成功启动（`ps aux | grep app` 能看到）
- [ ] 测试 API 成功（`curl http://localhost:8080/api/health`）
- [ ] Nginx 反向代理已配置（可选）

✨ **完成所有步骤后，你的后端就上线了！**

---

**需要什么帮助吗？直接问我！** 💬

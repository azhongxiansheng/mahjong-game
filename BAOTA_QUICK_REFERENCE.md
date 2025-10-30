# 🎯 宝塔面板部署 - 快速参考卡片

## 📱 最常用链接

| 链接 | 用途 |
|------|------|
| https://cloud.tencent.com/ | 腾讯云（买服务器）|
| https://www.putty.org/ | PuTTY（SSH 连接工具）|
| https://www.bt.cn/ | 宝塔面板官网 |
| http://你的IP:8888 | 宝塔面板登录 |

---

## 🔧 关键命令速查

### 安装宝塔（购买服务器后运行一次）

```bash
wget -O install.sh http://download.bt.cn/install/install_lts.sh && sudo bash install.sh ed8484bec
```

### 启动应用（上传代码后运行）

```bash
cd /home/mahjong-game
go build -o app main.go
nohup ./app > app.log 2>&1 &
```

### 验证应用已启动

```bash
ps aux | grep app
```

应该看到：
```
root  12345  ... ./app
```

### 查看实时日志

```bash
tail -f /home/mahjong-game/app.log
```

按 **Ctrl+C** 退出

### 查看完整日志

```bash
cat /home/mahjong-game/app.log
```

### 重启应用

```bash
pkill -f "./app"
cd /home/mahjong-game && nohup ./app > app.log 2>&1 &
```

### 停止应用

```bash
pkill -f "./app"
```

### 测试 API

```bash
curl http://localhost:8080/api/health
```

应该返回：
```json
{"status":"ok","ready":true,"time":"2025-10-29T..."}
```

### 重启 Nginx

```bash
systemctl restart nginx
```

---

## 📋 三步启动流程

### 第 1 步：编译

```bash
cd /home/mahjong-game
go build -o app main.go
```

### 第 2 步：后台运行

```bash
nohup ./app > app.log 2>&1 &
```

### 第 3 步：验证

```bash
ps aux | grep app
```

✅ 完成！应用已在后台运行

---

## 🐛 常见错误速查

| 错误 | 原因 | 解决方案 |
|------|------|---------|
| `command not found: go` | Go 未安装 | 在宝塔软件商店安装 Go |
| `port already in use` | 端口被占用 | 改用其他端口或停止占用的应用 |
| `permission denied` | 权限不足 | `chmod +x app` 添加执行权限 |
| `connection refused` | 应用未启动 | `ps aux \| grep app` 检查进程 |
| 应用启动后立即停止 | 代码错误 | `tail -f app.log` 查看日志 |

---

## 📍 文件路径一览

| 路径 | 用途 |
|------|------|
| `/home/mahjong-game/` | 项目根目录 |
| `/home/mahjong-game/main.go` | Go 源代码 |
| `/home/mahjong-game/go.mod` | Go 依赖文件 |
| `/home/mahjong-game/app` | 编译后的可执行文件 |
| `/home/mahjong-game/app.log` | 应用日志文件 |

---

## 🔐 安全设置

### 修改宝塔面板密码

在宝塔面板中：
1. 右上角 → 设置
2. 找到"修改密码"
3. 输入新密码
4. 保存

### 修改 SSH 密码（服务器密码）

在宝塔终端中：
```bash
passwd root
```

按提示输入新密码（输入时看不见，正常现象）

---

## 🌐 域名和 HTTPS 配置

### 在宝塔中添加网站

1. 点击 **网站**
2. 点击 **添加站点**
3. 填入域名（如 api.yourdomain.com）
4. 点击 **创建**

### 配置反向代理

1. 在网站列表找到你的站点
2. 点击 **设置**
3. 点击 **反向代理**
4. 点击 **添加反向代理**
5. 填入：
   - 反向代理目标 URL: `http://127.0.0.1:8080`
   - 子目录: `/`
6. 点击 **提交**

### 申请 SSL 证书

1. 在网站设置中找到 **SSL**
2. 选择 **Let's Encrypt** 免费证书
3. 输入邮箱
4. 点击 **申请**
5. 等待完成（通常几秒钟）

---

## 📊 性能监控

### 查看系统资源使用情况

```bash
# CPU 和内存
free -h
df -h

# 实时监控（按 q 退出）
top
```

### 查看网络连接

```bash
netstat -tuln | grep 8080
```

### 查看进程详情

```bash
ps aux | grep app
```

---

## 🚀 部署完整流程（快速版）

```bash
# 1. 连接到服务器（用 PuTTY）
# IP: 你的服务器IP
# 用户名: root
# 密码: 你的密码

# 2. 安装宝塔（运行一次）
wget -O install.sh http://download.bt.cn/install/install_lts.sh && sudo bash install.sh ed8484bec

# 3. 等待 3-5 分钟

# 4. 上传 main.go 和 go.mod 到 /home/mahjong-game/（用宝塔文件管理器）

# 5. 在宝塔终端运行
cd /home/mahjong-game
go build -o app main.go
nohup ./app > app.log 2>&1 &

# 6. 验证
ps aux | grep app

# 7. 测试
curl http://localhost:8080/api/health

# ✅ 完成！
```

---

## 💾 备份和恢复

### 备份项目代码

```bash
# 压缩项目
cd /home
tar -czf mahjong-game-backup.tar.gz mahjong-game/

# 下载备份（用 WinSCP 或宝塔文件管理器）
```

### 从备份恢复

```bash
# 上传 mahjong-game-backup.tar.gz 到 /home/

# 解压
cd /home
tar -xzf mahjong-game-backup.tar.gz

# 重新启动
cd /home/mahjong-game
nohup ./app > app.log 2>&1 &
```

---

## 🎓 帮助和资源

### 获取帮助的方法

1. **查看日志**
   ```bash
   tail -f /home/mahjong-game/app.log
   ```

2. **查看详细文档**
   - `BAOTA_DEPLOYMENT_GUIDE.md`
   - `BAOTA_QUICK_START.md`

3. **宝塔论坛**
   - https://www.bt.cn/

4. **Go 官方文档**
   - https://go.dev/

---

## 📞 紧急联系方式

如果应用完全无法启动，请按以下顺序检查：

```
1. 查看日志文件
   tail -20 /home/mahjong-game/app.log

2. 确认 Go 已安装
   go version

3. 确认项目文件存在
   ls -la /home/mahjong-game/

4. 尝试手动运行
   cd /home/mahjong-game && go run main.go

5. 检查端口是否被占用
   lsof -i :8080
```

---

## ✅ 每日检查清单

每天花 2 分钟检查应用状态：

```bash
# 1. 检查应用是否运行
ps aux | grep app

# 2. 检查最新日志
tail -20 /home/mahjong-game/app.log

# 3. 测试 API 是否可用
curl http://localhost:8080/api/health

# 4. 检查磁盘空间
df -h

# 5. 检查内存使用
free -h
```

---

## 🎯 完成标志

当你能够执行以下命令并得到正确结果时，说明部署成功：

```bash
$ curl http://localhost:8080/api/health
{"status":"ok","ready":true,"time":"2025-10-29T12:34:56Z"}
```

**恭喜！** 🎉 你的后端已经成功部署了！

---

**需要什么帮助？直接告诉我命令！** 💬

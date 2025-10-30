# 🎯 宝塔面板部署麻将游戏后端 - 完整教程

## 📌 总体流程

```
1. 购买国内服务器
   ↓
2. 安装宝塔面板
   ↓
3. 配置 Go 运行环境
   ↓
4. 上传项目代码
   ↓
5. 启动 Go 应用
   ↓
6. 配置反向代理 (Nginx)
   ↓
7. 绑定域名
   ↓
8. 完成！✅
```

---

## 第一步：购买国内服务器

### 推荐配置

| 选项 | 推荐 |
|------|------|
| **地区** | 北京或上海（最接近用户） |
| **系统** | Ubuntu 20.04 LTS |
| **CPU** | 2核 |
| **内存** | 2GB |
| **硬盘** | 50GB |
| **带宽** | 1-5Mbps |
| **价格** | ~¥99-200/月 |

### 购买地址

**腾讯云（最推荐）**
- https://cloud.tencent.com/
- 新用户有优惠券
- 选择：CVM 云服务器 → 标准型 → Ubuntu 20.04

**阿里云**
- https://www.aliyun.com/
- ECS 云服务器 → 选择相同配置

**华为云**
- https://www.huaweicloud.com/
- 竞争力强，速度也不错

---

## 第二步：安装宝塔面板

### 2.1 连接到服务器

**使用 Windows 的方法：**

1. **下载 PuTTY**
   - 网址：https://www.putty.org/
   - 下载 putty.exe

2. **打开 PuTTY，输入**
   - Host Name: `你的服务器 IP`
   - Port: `22`
   - 点击 Open

3. **登录**
   - Username: `root`
   - Password: `你的服务器密码`（购买时设置）

### 2.2 安装宝塔（一键命令）

复制粘贴以下命令到 PuTTY 中：

```bash
wget -O install.sh http://download.bt.cn/install/install_lts.sh && sudo bash install.sh ed8484bec
```

**按 Enter 运行**

### 2.3 等待安装完成

安装过程需要 3-5 分钟，最后会显示：

```
=============================================================
恭喜！宝塔面板安装完成

外网面板地址: http://your-ip:8888
初始用户名: admin
初始密码: xxxxxx
=============================================================
```

**✅ 记下这些信息！**

---

## 第三步：进入宝塔面板

### 3.1 打开宝塔

1. 打开浏览器
2. 访问：`http://你的服务器IP:8888`
3. 用户名：`admin`
4. 密码：`上面复制的密码`
5. 点击 **登录**

### 3.2 初始设置

首次登录会要求：
- ✅ 绑定手机（可跳过）
- ✅ 设置新密码（推荐设置强密码）
- ✅ 选择 LNMP（Linux + Nginx + MySQL + PHP）

**注意：我们只需要 Nginx，其他可以不装，但装也无所谓**

---

## 第四步：配置 Go 运行环境

### 4.1 安装 Go

**在宝塔面板中操作：**

1. 点击左侧 **软件商店**（或 App Store）
2. 搜索 **Go**
3. 找到 **Go Runtime** 或 **Golang**
4. 点击 **安装**
5. 等待安装完成（3-5 分钟）

**或者手动安装（如果商店没有）：**

1. 点击左侧 **终端**
2. 复制粘贴以下命令：

```bash
# 下载 Go 1.20
cd /opt
wget https://go.dev/dl/go1.20.linux-amd64.tar.gz

# 解压
tar -C /usr/local -xzf go1.20.linux-amd64.tar.gz

# 设置环境变量
echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
source ~/.bashrc

# 验证安装
go version
```

---

## 第五步：上传项目代码

### 5.1 准备项目文件

在本地创建一个文件夹，包含：

```
mahjong-game/
  ├── main.go
  ├── go.mod
  ├── Dockerfile (可选)
  └── Procfile (可选)
```

### 5.2 上传到服务器

**方法 A：用宝塔面板上传（最简单）**

1. 点击左侧 **文件**
2. 进入 `/home` 目录
3. 点击 **上传**
4. 选择你的项目文件夹
5. 等待上传完成

**方法 B：用 WinSCP（专业方式）**

1. 下载 WinSCP：https://winscp.net/
2. 新建会话：
   - 主机名：你的服务器 IP
   - 用户名：root
   - 密码：服务器密码
3. 连接后拖拽上传项目

---

## 第六步：启动 Go 应用

### 6.1 进入项目目录

在宝塔面板的 **终端** 中：

```bash
cd /home/mahjong-game
```

### 6.2 验证项目

```bash
ls -la
# 应该看到 main.go, go.mod

go version
# 验证 Go 已安装
```

### 6.3 运行应用

**第一种：直接运行**

```bash
go run main.go
```

**第二种：编译后运行（推荐）**

```bash
# 编译
go build -o app main.go

# 运行
./app
```

### 6.4 后台运行（重要！）

使用 **nohup** 让应用在后台持续运行：

```bash
nohup go run main.go > app.log 2>&1 &
```

或编译后：

```bash
nohup ./app > app.log 2>&1 &
```

**验证运行状态：**

```bash
ps aux | grep app
```

应该看到应用进程正在运行。

---

## 第七步：配置 Nginx 反向代理

### 7.1 创建 Nginx 配置

在宝塔面板中：

1. 点击左侧 **网站**
2. 点击 **添加站点**
3. 域名：输入你的域名（如 api.yourdomain.com）
4. 根目录：选择任意路径（如 /home/www）
5. 点击 **创建**

### 7.2 配置反向代理

1. 在网站列表中找到你刚创建的站点
2. 点击 **设置** 或 **编辑**
3. 点击 **反向代理** 标签
4. 点击 **添加反向代理**

填入以下信息：
- **反向代理目标 URL**: `http://127.0.0.1:8080`
- **子目录**: `/` （或 `/api`）
- 点击 **提交**

### 7.3 验证配置

```bash
# 测试 Nginx 配置
nginx -t

# 重启 Nginx
systemctl restart nginx
```

---

## 第八步：绑定域名（可选）

### 8.1 解析域名到服务器

1. 登录你的域名注册商（如阿里云、腾讯云）
2. 进入 DNS 解析
3. 添加 A 记录：
   - **主机记录**: `api` （或 `@` 如果是根域名）
   - **记录类型**: `A`
   - **记录值**: 你的服务器 IP
   - 等待 10-30 分钟生效

### 8.2 在宝塔中配置 SSL（HTTPS）

1. 在网站设置中找到 **SSL**
2. 选择 **Let's Encrypt** 免费证书
3. 输入你的邮箱
4. 点击 **申请**
5. 等待申请完成

---

## 第九步：测试应用

### 9.1 测试 API

```bash
# 测试健康检查
curl http://你的服务器IP:8080/api/health

# 或通过域名（如果已绑定）
curl https://api.yourdomain.com/api/health
```

**应该返回：**
```json
{"status":"ok","ready":true,"time":"2025-10-29T..."}
```

### 9.2 查看日志

```bash
# 查看运行日志
tail -f app.log

# 或查看完整历史
cat app.log
```

---

## 第十步：配置开机自启（可选但推荐）

### 10.1 创建 systemd 服务

编辑文件 `/etc/systemd/system/mahjong.service`：

```bash
sudo nano /etc/systemd/system/mahjong.service
```

粘贴以下内容：

```ini
[Unit]
Description=Mahjong Game Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/home/mahjong-game
ExecStart=/home/mahjong-game/app
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

按 **Ctrl + X** 然后 **Y** 保存。

### 10.2 启用服务

```bash
# 重新加载 systemd
sudo systemctl daemon-reload

# 启用开机自启
sudo systemctl enable mahjong

# 启动服务
sudo systemctl start mahjong

# 查看状态
sudo systemctl status mahjong
```

---

## 🆘 常见问题

### Q1: 应用启动后立即停止

```bash
# 查看日志
cat app.log

# 常见原因：
# 1. 端口被占用
# 2. 权限问题
# 3. 代码错误
```

### Q2: 无法访问应用

```bash
# 检查防火墙
sudo ufw status

# 开放端口
sudo ufw allow 8080

# 检查 Nginx 是否运行
nginx -t
systemctl status nginx
```

### Q3: 反向代理不工作

1. 确保应用在 localhost:8080 运行
2. 重启 Nginx：`systemctl restart nginx`
3. 检查配置：`nginx -T`

### Q4: 域名无法访问

```bash
# 检查 DNS 生效
nslookup api.yourdomain.com

# 检查应用状态
ps aux | grep app

# 查看 Nginx 日志
tail -f /var/log/nginx/error.log
```

---

## 📋 快速参考命令

```bash
# 启动应用
nohup go run main.go > app.log 2>&1 &

# 停止应用
pkill -f "go run main.go"

# 查看运行日志
tail -f app.log

# 重启 Nginx
systemctl restart nginx

# 查看所有运行的进程
ps aux | grep -E "go|app"

# 测试 API
curl http://localhost:8080/api/health
```

---

## ✅ 部署完成检查清单

- [ ] 服务器已购买
- [ ] 宝塔面板已安装
- [ ] Go 环境已配置
- [ ] 项目代码已上传
- [ ] 应用成功启动（在后台运行）
- [ ] Nginx 反向代理已配置
- [ ] 能通过 http://IP:8080 或 https://domain.com 访问
- [ ] 健康检查端点返回正确响应
- [ ] 开机自启已配置（可选）

---

## 🎯 总结

通过宝塔面板，你现在拥有：

✅ 一个稳定的国内服务器  
✅ 图形化管理面板  
✅ 自动化的部署流程  
✅ SSL HTTPS 支持  
✅ 日志和监控功能  

**从现在开始，你的麻将游戏后端已经完全上线！** 🎉

---

## 需要帮助吗？

如果遇到问题，提供以下信息：
1. 服务器操作系统
2. 错误日志内容
3. 宝塔面板版本
4. 应用输出信息

我会帮你快速解决！

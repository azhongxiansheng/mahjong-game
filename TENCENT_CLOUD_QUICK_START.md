# 🚀 腾讯云快速部署 - 22 分钟完成！

**选择**: 腾讯云 CVM  
**时间**: 22 分钟  
**成本**: ¥0 (完全免费)  
**配置**: 2 核 CPU + 2GB 内存 + 50GB SSD  

---

## 📋 目录

1. [注册账户](#注册账户)
2. [领取免费服务器](#领取免费服务器)
3. [创建实例](#创建实例)
4. [连接服务器](#连接服务器)
5. [部署麻将游戏](#部署麻将游戏)
6. [验证部署](#验证部署)
7. [常见问题](#常见问题)

---

## ✅ 第 1 步: 注册腾讯云账户 (5 分钟)

### 访问官网

打开浏览器，访问：
```
https://cloud.tencent.com/
```

### 点击注册

1. 在页面右上角点击 **"注册"** 按钮
2. 选择认证方式（推荐用微信或 QQ）
3. 使用微信或 QQ 快速登录

### 完成身份验证

1. 使用微信/QQ 扫码
2. 输入手机号
3. 验证身份（如需要）

✅ 完成！您已注册腾讯云账户


---

## ✅ 第 2 步: 领取免费服务器 (2 分钟)

### 进入控制台

登录后，您应该看到腾讯云控制台。

### 查找免费试用

1. 在页面左上角搜索框输入：`CVM`
2. 或点击 **"产品"** → **"云计算基础"** → **"云服务器 CVM"**

### 点击免费试用

1. 在 CVM 页面找到 **"免费试用"** 按钮
2. 点击 **"立即体验"** 或 **"新建实例"**

✅ 完成！您已进入实例创建页面


---

## ✅ 第 3 步: 创建实例 (3 分钟)

### 选择配置

在创建实例页面，进行以下配置：

#### 计费模式
```
选择: 按量计费 或 包年包月 (选免费试用)
```

#### 地区和可用区
```
地区: 北京、上海、广州（任选一个）
可用区: 默认即可
```

#### 实例类型
```
实例族: 标准型 (S5 或 S6)
规格: 2 核 2GB 内存
```

#### 镜像
```
操作系统: Linux
发行版: Ubuntu
版本: 20.04 LTS
```

#### 存储
```
系统盘: 50GB SSD (默认即可)
```

#### 网络
```
VPC: 默认 VPC
子网: 默认子网
公网 IP: 分配公网 IP (必须勾选！)
带宽: 1Mbps (免费版)
```

### 点击创建

1. 确认配置无误
2. 点击 **"立即购买"** 或 **"创建"**
3. 选择 **"免费试用 12 个月"**
4. 支付 (应该是 ¥0)

### 等待启动

实例会在 2-3 分钟内启动。您可以在控制台看到进度。

✅ 完成！您的实例已启动


---

## ✅ 第 4 步: 获取连接信息 (2 分钟)

### 获取公网 IP

1. 进入 **"云服务器"** → **"实例"**
2. 找到您刚创建的实例
3. 记下 **"主 IP"** 或 **"公网 IP"**（这就是服务器地址）

### 设置密钥或密码

#### 方式 1: 使用密钥对 (推荐)

1. 在实例详情页面，点击 **"密钥"** 标签
2. 点击 **"绑定/创建密钥"**
3. 选择 **"创建新的密钥对"**
4. 输入密钥名称（例如 `mahjong-key`）
5. 点击 **"创建并下载"**
6. 保存下载的 `.pem` 文件（例如 `mahjong-key.pem`）

#### 方式 2: 使用密码

1. 在实例列表，右键点击实例
2. 选择 **"设置密码"** 或 **"重置密码"**
3. 输入新密码（建议 12+ 位，包含大小写字母、数字、特殊符号）
4. 点击 **"确定"**

### 记录信息

记下以下信息（稍后会用到）：
```
公网 IP: xxx.xxx.xxx.xxx
用户名: ubuntu (如果是 Ubuntu 系统)
密钥文件: mahjong-key.pem (如果使用密钥)
或
密码: your-password (如果使用密码)
```

✅ 完成！您已准备好连接


---

## ✅ 第 5 步: 连接到服务器 (1 分钟)

### 在 Windows 上连接

#### 选项 1: 使用 PowerShell

打开 PowerShell，执行以下命令：

**如果使用密钥对：**
```powershell
# 1. 进入密钥文件所在目录
cd D:\Downloads  # 替换为您下载密钥的目录

# 2. 更改密钥权限 (必须)
chmod 600 mahjong-key.pem

# 3. SSH 连接
ssh -i mahjong-key.pem ubuntu@xxx.xxx.xxx.xxx
# 替换 xxx.xxx.xxx.xxx 为您的公网 IP
```

**如果使用密码：**
```powershell
ssh ubuntu@xxx.xxx.xxx.xxx
# 替换 xxx.xxx.xxx.xxx 为您的公网 IP
# 然后输入密码
```

#### 选项 2: 使用腾讯云网页终端

1. 在实例列表，点击 **"登录"** 按钮
2. 选择 **"标准登录 (WebShell)"**
3. 在网页中输入密码
4. 点击 **"登录"**

### 在 Mac/Linux 上连接

打开终端，执行以下命令：

**如果使用密钥对：**
```bash
chmod 600 /path/to/mahjong-key.pem
ssh -i /path/to/mahjong-key.pem ubuntu@xxx.xxx.xxx.xxx
```

**如果使用密码：**
```bash
ssh ubuntu@xxx.xxx.xxx.xxx
```

### 验证连接

连接成功后，您应该看到：
```
ubuntu@VM-0-0-ubuntu:~$ 
```

这表示您已成功连接到服务器！

✅ 完成！您已连接到腾讯云服务器


---

## ✅ 第 6 步: 部署麻将游戏 (10 分钟)

### 下载部署脚本

在服务器上，运行以下命令之一：

**使用 wget:**
```bash
wget https://raw.githubusercontent.com/yourusername/mahjong-game/v1.0.0/CLOUD_DEPLOYMENT_AUTO.sh
```

**或使用 curl:**
```bash
curl -O https://raw.githubusercontent.com/yourusername/mahjong-game/v1.0.0/CLOUD_DEPLOYMENT_AUTO.sh
```

### 给予执行权限

```bash
chmod +x CLOUD_DEPLOYMENT_AUTO.sh
```

### 运行脚本

```bash
./CLOUD_DEPLOYMENT_AUTO.sh
```

脚本会自动做以下事情：
```
✅ 更新系统包
✅ 安装 Docker
✅ 安装 Docker Compose
✅ 克隆麻将游戏项目
✅ 创建配置文件
✅ 启动所有服务
✅ 验证部署
✅ 显示访问地址
```

### 等待完成

脚本运行需要约 10 分钟。您可以看到实时输出，显示进度。

完成后，您会看到：
```
🌍 您的麻将游戏已部署！
访问地址: http://xxx.xxx.xxx.xxx:8080/api/health
```

✅ 完成！麻将游戏已部署


---

## ✅ 第 7 步: 验证部署 (1 分钟)

### 在浏览器中验证

打开浏览器，访问：
```
http://xxx.xxx.xxx.xxx:8080/api/health
# 替换 xxx.xxx.xxx.xxx 为您的公网 IP
```

您应该看到：
```json
{"status":"ok","timestamp":"2025-11-16T10:00:00Z"}
```

这表示服务器已成功运行！

### 查看其他关键端点

```
数据库健康检查:
http://xxx.xxx.xxx.xxx:8080/api/db/health

WebSocket 状态:
http://xxx.xxx.xxx.xxx:8080/api/ws/health

排行榜:
http://xxx.xxx.xxx.xxx:8080/api/leaderboard/daily
```

✅ 完成！您的麻将游戏已在线


---

## 🎮 第 8 步: 配置微信小程序 (可选)

如果您要开发微信小程序，需要配置后端地址。

### 在小程序代码中配置

```javascript
// 在您的小程序项目中，找到 config.js 或类似的配置文件

// 配置后端 API 地址
const API_BASE_URL = 'https://xxx.xxx.xxx.xxx:8080';
// 或者如果您已购买域名和配置 HTTPS:
// const API_BASE_URL = 'https://api.yourdomain.com:8080';

// 使用 API
wx.request({
  url: API_BASE_URL + '/api/auth/login',
  method: 'POST',
  data: {
    username: 'player1',
    password: 'password123'
  },
  success(res) {
    console.log('登录成功', res.data);
  }
});
```

### 常见 API 端点

```javascript
// 注册
POST /api/auth/register

// 登录
POST /api/auth/login

// 获取排行榜
GET /api/leaderboard/daily

// 获取用户信息
GET /api/user/profile

// 创建游戏房间
POST /api/game/rooms

// 更多详见项目文档
```

---

## ❓ 常见问题

### Q1: 脚本运行失败了怎么办？

**答:**

1. 检查网络连接
2. 查看错误信息
3. 重新运行脚本：
   ```bash
   ./CLOUD_DEPLOYMENT_AUTO.sh
   ```
4. 如果还是不行，查看日志：
   ```bash
   docker-compose logs
   ```

### Q2: 部署后如何查看日志？

**答:**

```bash
# 实时查看日志
docker-compose logs -f backend

# 查看最后 100 行
docker-compose logs --tail 100

# 查看特定服务
docker-compose logs db
```

### Q3: 需要配置域名吗？

**答:**

```
不配置:
  • 直接用 IP 访问 (http://xxx.xxx.xxx.xxx:8080)
  • 适合测试和学习
  • 不需要额外成本

配置域名:
  • 购买域名 (¥30-60/年)
  • 配置 HTTPS (SSL 证书)
  • 提交微信小程序审核
  • 生产环境推荐
```

### Q4: 如何停止或重启服务？

**答:**

```bash
# 停止所有服务
docker-compose stop

# 启动所有服务
docker-compose start

# 重启所有服务
docker-compose restart

# 查看运行状态
docker-compose ps
```

### Q5: 12 个月免费后怎么办？

**答:**

选项 1: 继续付费 (大约 ¥60/月)
选项 2: 转到七牛云 (永久免费但配置低)
选项 3: 停止并使用本地开发

### Q6: 能否增加配置？

**答:**

可以！但会产生费用。推荐：
```
如果用户多: 升级到 4 核 8GB (~¥200/月)
如果需要更多存储: 增加额外磁盘 (~¥50/月/100GB)
```

---

## 📊 总结

```
✅ 第 1 步: 注册腾讯云 (5 分钟)
✅ 第 2 步: 领取免费 (2 分钟)
✅ 第 3 步: 创建实例 (3 分钟)
✅ 第 4 步: 获取凭证 (2 分钟)
✅ 第 5 步: SSH 连接 (1 分钟)
✅ 第 6 步: 运行脚本 (10 分钟)
✅ 第 7 步: 验证部署 (1 分钟)
════════════════════════
   总耗时: 24 分钟

成本: ¥0 (完全免费)

下一步: 
  1. 访问 https://cloud.tencent.com/
  2. 按照上面的步骤操作
  3. 22 分钟后您的麻将游戏就在线了！
```

---

## 🎯 快速命令参考

```bash
# 连接服务器 (已有密钥)
ssh -i mahjong-key.pem ubuntu@YOUR_IP

# 下载脚本
wget https://raw.githubusercontent.com/yourusername/mahjong-game/v1.0.0/CLOUD_DEPLOYMENT_AUTO.sh

# 执行脚本
chmod +x CLOUD_DEPLOYMENT_AUTO.sh
./CLOUD_DEPLOYMENT_AUTO.sh

# 查看服务状态
docker-compose ps

# 查看日志
docker-compose logs -f backend

# 停止服务
docker-compose stop

# 启动服务
docker-compose start
```

---

## 📞 获取帮助

如果遇到问题：

1. 查看本指南的常见问题
2. 查看脚本输出的错误信息
3. 查看 Docker 日志：`docker-compose logs`
4. 查看 GitHub Issues

---

**祝您部署成功！🚀 麻将游戏即将上线！🎲**

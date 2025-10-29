# 🚂 Railway 快速部署指南 - 15 分钟完成

**您的选择**: Railway.app  
**成本**: ¥0 (完全免费)  
**无需**: 信用卡、充值、身份验证  
**预计时间**: 15 分钟  
**配置**: 512MB - 2GB (足够!)  

---

## 📋 目录

1. [Railway 简介](#railway简介)
2. [快速部署 (15 分钟)](#快速部署15分钟)
3. [详细步骤](#详细步骤)
4. [常见问题](#常见问题)
5. [部署后的操作](#部署后的操作)

---

## 🎯 Railway 简介

### 什么是 Railway?

```
Railway 是一个现代的云部署平台
类似于 Heroku，但更新更好

特点:
✅ 完全免费
✅ 无需信用卡
✅ 支持 Docker
✅ 自动 HTTPS
✅ 简单易用
✅ 配置足够 (512MB-2GB)
```

### 为什么选 Railway?

```
✅ 不需要信用卡或身份验证
✅ 直接用 GitHub 账户登录
✅ 自动部署 (连接 GitHub 后自动更新)
✅ 一个命令就能查看日志
✅ 支持多种语言和框架
✅ 免费额度很大
✅ 部署速度快 (5-10 分钟)
```

---

## 🚀 快速部署 (15 分钟)

### 概览

```
Step 1: 访问 railway.app (1分钟)
Step 2: 用 GitHub 注册 (2分钟)
Step 3: 创建新项目 (1分钟)
Step 4: 连接代码仓库 (2分钟)
Step 5: 配置环境 (3分钟)
Step 6: 部署 (2分钟)
Step 7: 获取 URL (1分钟)
Step 8: 验证 (3分钟)

总计: 15 分钟
```

---

## 📝 详细步骤

### Step 1: 访问 Railway.app

打开浏览器，访问：

```
https://railway.app
```

您应该看到 Railway 的主页，有一个大的 "Start Building" 按钮。

---

### Step 2: 用 GitHub 注册

#### 2.1 点击 "Start Building"

```
在页面右上角或中间位置
找到 "Start Building" 或 "Get Started" 按钮
点击
```

#### 2.2 选择 GitHub 登录

```
会看到几个登录选项:
- GitHub ← 选这个
- Google
- Email

点击 GitHub
```

#### 2.3 GitHub 授权

```
会跳转到 GitHub 登录页面
输入 GitHub 用户名和密码
完成登录

然后 GitHub 会问你是否授权 Railway
点击 "Authorize railway-app"
```

#### 2.4 完成注册

```
授权完成后
Railway 会自动创建您的账户
您会看到 Railway 的仪表板
```

---

### Step 3: 创建新项目

#### 3.1 进入项目创建

```
在 Railway 仪表板上
点击 "New Project"
或 "Create Project"
```

#### 3.2 选择部署方式

```
会看到几个选项:

▶️ Deploy from GitHub (选这个!)
   从 GitHub 仓库直接部署
   
▶️ Deploy from Docker
   从 Docker 镜像部署
   
▶️ Deploy a Template
   使用模板

选择 "Deploy from GitHub"
```

---

### Step 4: 连接代码仓库

#### 4.1 连接 GitHub

```
点击 "Deploy from GitHub" 后
Railway 会要求连接 GitHub 仓库

选择:
- 您已经 fork 的麻将游戏仓库
- 或输入仓库名: yourusername/mahjong-game
```

#### 4.2 选择分支

```
选择分支:
- main (推荐)
- master (如果用的是 master)
- v1.0.0 (如果标记了版本)
```

#### 4.3 导入项目

```
Railway 会自动分析您的项目

可能会检测到:
✅ Go (后端)
✅ Node.js (如果有 frontend)
✅ Docker (如果有 Dockerfile)

等待导入完成 (1-2 分钟)
```

---

### Step 5: 配置环境

#### 5.1 选择服务

```
导入完成后，会显示检测到的服务

对于麻将游戏:
- Backend service (Go)
- Database service (可选)

点击 Backend service 进行配置
```

#### 5.2 配置环境变量

```
进入 Backend service 后，找到 "Variables" 选项

需要设置的环境变量:

DB_HOST=localhost (或数据库地址)
DB_PORT=5432 (数据库端口)
DB_USER=postgres (数据库用户)
DB_PASSWORD=yourpassword (数据库密码)
DB_NAME=mahjong (数据库名)

API_PORT=8080
JWT_SECRET=your-secret-key
ENVIRONMENT=production

根据您的配置调整
```

#### 5.3 添加数据库 (可选)

```
如果您想要持久化数据库:

1. 点击 "+ Add"
2. 选择 "Database"
3. 选择 PostgreSQL 或 MySQL
4. Railway 会自动配置连接字符串

但对于测试，可以跳过这步
```

#### 5.4 设置启动命令

```
找到 "Start Command" 或 "Run" 选项

对于 Go 后端，设置:

go run main.go

或如果编译过:

./mahjong

根据您的项目设置
```

---

### Step 6: 部署

#### 6.1 点击部署

```
所有配置完成后
找到 "Deploy" 或 "Create" 按钮
点击

Railway 会开始构建和部署
```

#### 6.2 观察部署进度

```
页面会显示部署日志
您可以实时看到:

✓ Cloning repository
✓ Installing dependencies
✓ Building application
✓ Starting service
✓ Service running

等待直到看到 "Service running"
通常需要 5-10 分钟
```

---

### Step 7: 获取公网 URL

#### 7.1 获取服务 URL

```
部署完成后，进入您的 Backend 服务

找到 "Networking" 或 "URL" 部分

会显示:
https://mahjong-game.railway.app

或类似的 URL (每个人不同)

复制这个 URL!
这就是您的麻将游戏服务器地址！
```

#### 7.2 获取环境信息

```
记下以下信息:

Public URL: https://mahjong-game.railway.app
Service Name: backend
Status: Running
Memory: 512MB (或您分配的大小)
```

---

### Step 8: 验证部署

#### 8.1 在浏览器中测试

```
复制您的 URL
在浏览器中访问:

https://mahjong-game.railway.app/api/health

如果看到:
{"status":"ok","timestamp":"..."}

恭喜! 部署成功! ✅
```

#### 8.2 测试其他端点

```
尝试访问其他 API:

排行榜:
https://mahjong-game.railway.app/api/leaderboard/daily

用户信息:
https://mahjong-game.railway.app/api/user/profile

如果都能访问，部署完全成功!
```

---

## ❓ 常见问题

### Q1: 为什么部署失败?

**答:**

```
常见原因:

1. 启动命令错误
   解决: 检查 "Start Command"
   
2. 依赖未安装
   解决: 确保有 go.mod 或 package.json
   
3. 环境变量缺失
   解决: 检查 "Variables" 部分
   
4. 端口被占用
   解决: 确保用了 8080 或配置的端口

查看日志:
点击 "Logs" 标签查看详细错误
```

### Q2: 如何查看日志?

**答:**

```
在 Railway 项目中:

1. 进入 Backend service
2. 点击 "Logs" 标签
3. 实时查看应用日志
4. 搜索错误关键词

或在终端:
railway logs
```

### Q3: 如何连接到数据库?

**答:**

```
方式 1: 使用 Railway 提供的连接字符串
1. 进入 Database service
2. 复制 DATABASE_URL 环境变量
3. 在应用中使用

方式 2: 手动配置
1. 获取数据库主机、端口、用户、密码
2. 设置环境变量
3. 在应用中使用
```

### Q4: 如何更新应用?

**答:**

```
非常简单!

只需在 GitHub 上 push 代码
Railway 会自动检测
自动重新部署!

无需手动操作!

步骤:
git add .
git commit -m "update"
git push origin main

Railway 会在 1-2 分钟内自动部署
```

### Q5: 性能怎么样?

**答:**

```
对于麻将游戏:

免费配置:
- CPU: 共享
- 内存: 512MB
- 足够! ✅

足以支持:
✓ 单个游戏房间
✓ 小规模多人游戏 (10-20 人)
✓ 开发测试

如果需要更多:
可以升级到付费计划
或配置自动扩展
```

### Q6: 免费期限是多久?

**答:**

```
Railway 的免费政策:

✅ 永久免费
✅ 每月 $5 免费额度 (2024 年政策)
✅ 超过额度可付费
✅ 不会自动扣费

对于小型应用 (麻将游戏测试)
通常不会超过免费额度!
```

### Q7: 如何绑定自己的域名?

**答:**

```
进入您的项目:

1. 点击 "Settings"
2. 找到 "Networking"
3. 点击 "Add custom domain"
4. 输入您的域名
   例: api.yourdomain.com
5. 更新 DNS 设置 (Railway 会提示)
6. 等待 5-10 分钟生效

然后您可以用自己的域名访问!
```

---

## 🎉 部署后的操作

### 1. 记录公网 URL

```
您的麻将游戏已上线!

重要信息:
✓ 公网 URL: https://mahjong-game.railway.app
✓ API 基础地址: https://mahjong-game.railway.app/api
✓ 健康检查: https://mahjong-game.railway.app/api/health

妥善保管这个 URL!
用于:
- 微信小程序配置
- 测试
- 分享
```

### 2. 配置微信小程序

```
在您的微信小程序代码中:

const API_BASE_URL = 'https://mahjong-game.railway.app';

wx.request({
  url: API_BASE_URL + '/api/auth/login',
  method: 'POST',
  // ... 更多配置
});
```

### 3. 监控和维护

```
定期检查:

1. 查看日志
   railway logs
   
2. 检查健康状态
   访问 /api/health
   
3. 监控内存使用
   Railway 仪表板 → Metrics
   
4. 定期测试 API
   确保一切正常
```

### 4. 后续升级

```
如果需要升级:

选项 1: 付费计划
- 更多内存 (1GB、2GB、4GB)
- 更好性能
- 专业支持

选项 2: 转移到 Google Cloud
- 更高配置
- 更多功能
- 需要信用卡

对于现在，Railway 已经足够!
```

---

## ✅ 完整检查清单

部署前检查:

- [ ] GitHub 账户已创建
- [ ] 代码已 push 到 GitHub
- [ ] Railway 账户已注册
- [ ] Backend 启动命令正确
- [ ] 环境变量已设置
- [ ] 数据库连接字符串正确 (如需要)

部署后检查:

- [ ] 部署日志显示 "Running"
- [ ] 公网 URL 可访问
- [ ] /api/health 返回正常
- [ ] 其他 API 端点可访问
- [ ] 日志中没有错误

---

## 📞 如果遇到问题

### 查看日志

```
最好的调试方法:

1. 进入 Railway 项目
2. 点击您的 service
3. 点击 "Logs" 标签
4. 搜索 "error" 或 "ERROR"
5. 查看错误信息

大多数问题都能从日志中看出
```

### 常见错误和解决方案

```
❌ "command not found"
→ 启动命令错误，检查 Start Command

❌ "port already in use"
→ 改变端口号，或检查是否有多个进程

❌ "out of memory"
→ 升级到付费计划获得更多内存

❌ "connection refused"
→ 数据库连接失败，检查凭证
```

---

## 🎯 最后的步骤

### 现在就开始!

```
1. 打开: https://railway.app
2. 点击: "Start Building"
3. 选择: GitHub 登录
4. 授权: Railway 访问您的 GitHub
5. 创建: 新项目
6. 选择: "Deploy from GitHub"
7. 选择: 您的麻将游戏仓库
8. 配置: 环境变量
9. 点击: Deploy
10. 等待: 5-10 分钟
11. 获取: 公网 URL
12. 完成: 麻将游戏上线!

总耗时: 15 分钟!
```

### 成功标志

```
✅ 看到 "Service running"
✅ 能访问 /api/health
✅ 获得公网 URL
✅ 麻将游戏已在线

恭喜! 您已成功部署了麻将游戏! 🎉
```

---

## 📖 快速参考

### 重要链接

```
Railway 官网: https://railway.app
Railway 文档: https://railway.app/docs
Railway 社区: https://community.railway.app
```

### 重要命令

```
连接到 Railway CLI:
railway login

查看日志:
railway logs

部署:
railway up

环境变量:
railway variables

服务状态:
railway status
```

---

**现在就去 railway.app 部署您的麻将游戏吧!** 🚀

15 分钟内，您的游戏将在全球在线！🎲

完成后告诉我您的公网 URL，
我会帮您配置微信小程序和进行最后的测试！

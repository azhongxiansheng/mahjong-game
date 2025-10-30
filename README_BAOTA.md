# 🎉 欢迎使用宝塔面板部署方案

## 📌 你已经成功转换到国内服务器部署！

从 Railway 的困扰中解脱，拥抱稳定可靠的国内服务器 + 宝塔面板方案。

✅ **不再有缓存问题**  
✅ **完整的控制权**  
✅ **国内访问速度快**  
✅ **价格更便宜**  
✅ **中文支持和宝塔面板**  

---

## 🚀 立即开始（只需 1 小时）

### 第 1 步：选择并购买服务器（30 分钟）

📖 **查看:** `CHINESE_SERVER_GUIDE.md`

**快速决策：**
- 服务商：腾讯云（最推荐）
- 配置：2核2GB/50GB
- 系统：Ubuntu 20.04 LTS
- 地域：北京 或 上海
- 价格：¥99-150/月

**购买链接：**
- 腾讯云: https://cloud.tencent.com/
- 阿里云: https://www.aliyun.com/
- 华为云: https://www.huaweicloud.com/

### 第 2 步：安装宝塔并启动应用（30 分钟）

📖 **查看:** `BAOTA_QUICK_START.md`

**核心命令：**
```bash
# 安装宝塔
wget -O install.sh http://download.bt.cn/install/install_lts.sh && sudo bash install.sh ed8484bec

# 启动应用
cd /home/mahjong-game && go build -o app main.go && nohup ./app > app.log 2>&1 &

# 验证
curl http://localhost:8080/api/health
```

---

## 📚 文档速查表

### 🎯 按需求查找

| 我需要... | 查看文件 |
|----------|--------|
| **快速上手** | `BAOTA_QUICK_START.md` ⭐ |
| **选择服务器** | `CHINESE_SERVER_GUIDE.md` ⭐ |
| **详细教程** | `BAOTA_DEPLOYMENT_GUIDE.md` |
| **快速参考** | `BAOTA_QUICK_REFERENCE.md` ⭐ |
| **完整流程** | `START_BAOTA_DEPLOYMENT.md` |
| **排查问题** | `BAOTA_DEPLOYMENT_GUIDE.md` → 常见问题 |

### 📖 按学习阶段

```
初学者路径：
  1️⃣ START_BAOTA_DEPLOYMENT.md
  2️⃣ CHINESE_SERVER_GUIDE.md
  3️⃣ BAOTA_QUICK_START.md
  
开发者路径：
  1️⃣ BAOTA_DEPLOYMENT_GUIDE.md
  2️⃣ BAOTA_QUICK_REFERENCE.md
  
问题排查：
  1️⃣ BAOTA_QUICK_REFERENCE.md（常见错误速查）
  2️⃣ BAOTA_DEPLOYMENT_GUIDE.md（详细故障排查）
```

---

## 🎯 完整流程简览

### 4 个阶段 → 1 小时 → 后端上线

```
┌─────────────────────────────────────────┐
│ 阶段 1: 购买服务器 (30 分钟)            │
│ • 选择腾讯云/阿里云/华为云              │
│ • 购买 2核2GB 服务器                    │
│ • 记下 IP 和密码                        │
└─────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────┐
│ 阶段 2: 安装宝塔 (10 分钟)              │
│ • 用 PuTTY 连接服务器                   │
│ • 运行一键安装脚本                      │
│ • 记下宝塔面板地址和密码                │
└─────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────┐
│ 阶段 3: 上传代码并启动 (10 分钟)        │
│ • 上传 main.go 和 go.mod                │
│ • 编译应用                              │
│ • 后台运行应用                          │
└─────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────┐
│ 阶段 4: 配置反向代理 (5 分钟)(可选)     │
│ • 在宝塔配置 Nginx 反向代理             │
│ • 绑定域名 (可选)                       │
│ • 申请 SSL 证书 (可选)                  │
└─────────────────────────────────────────┘
                    ↓
                ✨ 完成！✨
          你的后端已成功上线！
```

---

## 🔑 三个最重要的命令

### 1. 编译应用

```bash
cd /home/mahjong-game
go build -o app main.go
```

### 2. 启动应用（后台运行）

```bash
nohup ./app > app.log 2>&1 &
```

### 3. 验证应用

```bash
curl http://localhost:8080/api/health
```

**成功标志：**
```json
{"status":"ok","ready":true,"time":"2025-10-29T..."}
```

---

## 💾 你的项目代码已准备好

✅ `main.go` - 已包含健康检查端点  
✅ `go.mod` - Go 依赖配置  
✅ 心跳日志 - 防止容器自动停止  

**无需修改任何代码！** 直接上传部署即可。

---

## 🤔 常见问题快速解答

### Q: 这比 Railway 好在哪里？

| 对比项 | Railway | 国内服务器 + 宝塔 |
|--------|---------|--------|
| 缓存问题 | ❌ 严重 | ✅ 无 |
| 配置冲突 | ❌ 频繁 | ✅ 不会 |
| 国内速度 | ❌ 慢 | ✅ 极快 |
| 价格 | ¥99-150/月 | ✅ ¥99-150/月 |
| 完全控制 | ❌ 有限 | ✅ 完全 |
| 中文支持 | ❌ 无 | ✅ 宝塔完全中文 |

### Q: 需要多少钱？

- **第一个月：** ¥99-150（测试）
- **第一年：** ¥999-1200（含优惠）
- **长期：** 按需付费（可随时升级/降级）

### Q: 需要备案吗？

- ✅ **有 IP 直接用，不需要备案**
- ⚠️ 绑定域名才需要备案（3-7 天）

### Q: 能支持多少用户？

- 当前配置（2核2GB）支持 **100+ 并发连接**
- 用户增多可随时升级

### Q: 应用崩溃了怎么办？

所有故障都很容易解决，查看：
- `BAOTA_QUICK_REFERENCE.md` → 常见错误速查
- `BAOTA_DEPLOYMENT_GUIDE.md` → 详细故障排查

---

## 📋 部署前检查清单

在购买服务器前，确保你已有：

- [ ] 本地代码已提交到 Git
- [ ] `main.go` 能正常编译：`go build -o app main.go`
- [ ] `go.mod` 文件存在
- [ ] 已选定服务商（推荐腾讯云）
- [ ] 已准备支付方式（支付宝/微信/银行卡）

---

## 🎓 学习资源

### 官方文档

| 资源 | 链接 |
|------|------|
| 宝塔面板 | https://www.bt.cn/ |
| Go 编程 | https://go.dev/ |
| 腾讯云 | https://cloud.tencent.com/document |
| Ubuntu | https://ubuntu.com/server |

### 你已有的文档

- ✅ 完整部署教程
- ✅ 快速启动指南
- ✅ 服务器选购指南
- ✅ 故障排查指南
- ✅ 快速参考卡片

---

## 🎯 下一步行动

### 👉 现在就做这三件事：

1. **阅读** `CHINESE_SERVER_GUIDE.md`（10 分钟）
   - 了解各云服务商的优劣
   - 决定选哪一个

2. **购买** 服务器（30 分钟）
   - 在选定的平台购买
   - 记下 IP 和密码

3. **打开** `BAOTA_QUICK_START.md`（准备部署）
   - 按步骤安装宝塔
   - 上传代码并启动

---

## 📞 获取帮助

### 问题排查顺序

```
1. 查看对应文档
   ↓
2. 检查日志文件
   tail -f /home/mahjong-game/app.log
   ↓
3. 对比常见错误
   BAOTA_QUICK_REFERENCE.md → 常见错误速查
   ↓
4. 直接告诉我错误信息
```

---

## ✨ 成功的感受

当你看到这个输出时：

```bash
$ curl http://localhost:8080/api/health
{"status":"ok","ready":true,"time":"2025-10-29T12:34:56Z"}
```

**你会感受到：**
- ✨ 稳定性 - 不再有 Railway 的缓存问题
- ✨ 可靠性 - 国内服务器，快速可靠
- ✨ 控制性 - 完全掌握在自己手中
- ✨ 成就感 - 从 0 到 1 的完整体验

---

## 🎊 恭喜你！

你已经准备好离开 Railway 的困扰，开始享受稳定可靠的国内服务器体验了！

### 现在就开始吧！

**第一步：打开 `START_BAOTA_DEPLOYMENT.md` 或 `CHINESE_SERVER_GUIDE.md`**

---

## 📚 完整文档列表

```
🎯 START_BAOTA_DEPLOYMENT.md
   ↳ 总体指南，告诉你该做什么

🌐 CHINESE_SERVER_GUIDE.md
   ↳ 服务器选购，一步步教你怎么买

⚡ BAOTA_QUICK_START.md
   ↳ 5分钟快速启动，最快的方式

📖 BAOTA_DEPLOYMENT_GUIDE.md
   ↳ 完整详细教程，学习所有细节

🔧 BAOTA_QUICK_REFERENCE.md
   ↳ 快速参考卡片，关键命令一览

📱 README_BAOTA.md (当前文档)
   ↳ 欢迎指南，快速上手
```

---

**准备好了吗？** 🚀

**让我们告别 Railway，开始国内服务器的新征程吧！**

💪 相信你会成功的！

---

*最后更新: 2025-10-29*  
*祝部署顺利！* ✨

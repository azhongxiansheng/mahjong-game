# 🎯 告别 Railway，拥抱国内服务器 - 完整指南

## 📌 你的现状

✅ Railway 部署失败（缓存、配置冲突等问题）  
✅ Go 后端代码已就绪（在 `D:\MahjongGame\main.go`）  
✅ 决定使用国内服务器 + 宝塔面板  

❓ 接下来怎么做？

---

## 🚀 完整流程（4 个阶段）

### 🎯 第一阶段：选择和购买服务器（今天 - 1 小时）

**详见：`CHINESE_SERVER_GUIDE.md`**

#### 快速决策

```
预算: 每月 ¥99-150
首选: 腾讯云 ✅
配置: 2核2GB/50GB Ubuntu 20.04
地域: 北京 或 上海
周期: 先买 1 个月测试
```

#### 立即行动

1. 打开: https://cloud.tencent.com/ (或阿里云/华为云)
2. 点击: CVM 云服务器 / ECS
3. 选择推荐配置
4. 支付购买（新用户可能更便宜）
5. 记下：**IP 地址、密码、地域**

**预计时间：30 分钟** ⏱️

---

### 🛠️ 第二阶段：安装宝塔面板（购买后 - 10 分钟）

**详见：`BAOTA_DEPLOYMENT_GUIDE.md` 第 2-3 步**

#### 快速步骤

1. **下载 PuTTY**（Windows SSH 工具）
   - https://www.putty.org/

2. **连接到服务器**
   ```
   Host: 你的服务器 IP
   Port: 22
   Username: root
   Password: 你的密码
   ```

3. **安装宝塔（一键）**
   ```bash
   wget -O install.sh http://download.bt.cn/install/install_lts.sh && sudo bash install.sh ed8484bec
   ```

4. **等待完成**（3-5 分钟）

5. **记下宝塔信息**
   ```
   外网面板地址: http://你的IP:8888
   用户名: admin
   密码: xxxxx
   ```

**预计时间：10 分钟** ⏱️

---

### 📤 第三阶段：上传代码并启动（10 分钟）

**详见：`BAOTA_QUICK_START.md` 步骤 4-5**

#### 快速步骤

1. **打开宝塔面板**
   ```
   地址: http://你的IP:8888
   用户名: admin
   密码: 上面记下的密码
   ```

2. **在宝塔"文件"中创建项目目录**
   ```
   路径: /home/mahjong-game/
   ```

3. **上传项目文件**
   - 需要上传的文件：
     - ✅ main.go
     - ✅ go.mod
     - ✅ go.sum (可选)

4. **在宝塔"终端"中运行**
   ```bash
   cd /home/mahjong-game
   go build -o app main.go
   nohup ./app > app.log 2>&1 &
   ```

5. **验证应用已启动**
   ```bash
   ps aux | grep app
   ```
   应该看到类似：
   ```
   root  12345  0.0  ... ./app
   ```

**预计时间：10 分钟** ⏱️

---

### 🌐 第四阶段：配置反向代理和域名（5 分钟）

**详见：`BAOTA_DEPLOYMENT_GUIDE.md` 第 7-8 步**

#### 可选项 A：直接通过 IP 访问

```
http://你的服务器IP:8080/api/health

应该返回：
{"status":"ok","ready":true,"time":"2025-..."}
```

#### 可选项 B：配置 Nginx 反向代理（推荐）

1. **在宝塔"网站"中添加站点**
   - 域名: api.yourdomain.com（或用 IP）
   - 创建

2. **配置反向代理**
   - 设置 → 反向代理 → 添加反向代理
   - 目标 URL: http://127.0.0.1:8080
   - 子目录: /

3. **重启 Nginx**
   ```bash
   systemctl restart nginx
   ```

**预计时间：5 分钟** ⏱️

---

## 📊 总时间预估

| 阶段 | 时间 | 备注 |
|------|------|------|
| 选择和购买服务器 | 30 分钟 | 包括支付 |
| 安装宝塔面板 | 10 分钟 | 自动安装 |
| 上传代码并启动 | 10 分钟 | 手动操作 |
| 配置反向代理 | 5 分钟 | 可选 |
| **总计** | **~1 小时** | ✅ |

---

## 📋 详细文档索引

### 新手必读

| 文档 | 适合 | 内容 |
|------|------|------|
| **`CHINESE_SERVER_GUIDE.md`** | 🆕 选购阶段 | 服务商对比、购买步骤 |
| **`BAOTA_QUICK_START.md`** | 🆕 快速入门 | 5 步快速部署 |
| **`BAOTA_DEPLOYMENT_GUIDE.md`** | 📖 完整教程 | 详细步骤 + 常见问题 |

### 参考资料

| 文档 | 用途 |
|------|------|
| `GO_DEPLOYMENT_CHECKLIST.md` | 部署前检查清单 |
| `TROUBLESHOOTING.md` | 常见问题排查 |

---

## 🔑 关键信息一览表

### 我需要记住什么？

```
服务器信息:
  IP: ________________
  密码: ________________
  地域: ________________
  
宝塔面板信息:
  地址: http://IP:8888
  用户名: admin
  密码: ________________
  
项目信息:
  路径: /home/mahjong-game/
  启动命令: nohup ./app > app.log 2>&1 &
  验证: curl http://localhost:8080/api/health
```

---

## 🎯 具体行动步骤

### ✅ 今天就做这些

```
□ 1. 决定选哪个服务商
    推荐: 腾讯云
    链接: https://cloud.tencent.com/
    
□ 2. 购买 1 个月服务器
    配置: 2核2GB/50GB Ubuntu 20.04
    地域: 北京 或 上海
    价格: ¥99-150/月
    
□ 3. 记下服务器 IP 和密码
    IP: ________________
    密码: ________________
    
□ 4. 下载 PuTTY 连接工具
    链接: https://www.putty.org/
    
□ 5. 按照 `BAOTA_DEPLOYMENT_GUIDE.md` 
    第 2-3 步安装宝塔
    
□ 6. 记下宝塔面板地址和密码
    地址: ________________
    密码: ________________
```

### ✅ 明天做这些

```
□ 7. 进入宝塔面板
    地址: http://IP:8888
    
□ 8. 按照 `BAOTA_QUICK_START.md` 步骤 4
    上传 main.go 和 go.mod
    
□ 9. 启动应用
    命令: nohup ./app > app.log 2>&1 &
    
□ 10. 验证应用运行
     命令: ps aux | grep app
     
□ 11. 测试 API
     命令: curl http://localhost:8080/api/health
```

### ✅ 后续（可选）

```
□ 12. 配置 Nginx 反向代理（可选）
□ 13. 购买域名并绑定（可选）
□ 14. 申请 SSL 证书（可选）
□ 15. 配置开机自启（推荐）
```

---

## 🤔 常见问题

### Q: 比 Railway 有什么优势？

**A:**
- ✅ 没有缓存问题
- ✅ 完全控制权
- ✅ 国内速度更快
- ✅ 便宜（同样价格配置更好）
- ✅ 中文支持 + 宝塔面板简单易用

### Q: 如果出问题了怎么办？

**A:** 按顺序查看：
1. `BAOTA_QUICK_START.md` 常见问题
2. `BAOTA_DEPLOYMENT_GUIDE.md` 故障排查
3. 查看日志：`cat /home/mahjong-game/app.log`
4. 直接问我

### Q: 需要备案吗？

**A:** 
- ✅ 有 IP 就能用（不需要备案）
- ⚠️ 如果绑定域名，需要备案
- 💡 备案大约 3-7 天完成

### Q: 一个月后还要继续付钱吗？

**A:** 
- 是的，这是正常的云服务费用
- 建议：测试 1 个月，稳定后年付更便宜

### Q: 能同时连接多个客户端吗？

**A:** 
- 当前配置（2核2GB）可以支持 100+ 并发连接
- 如果需要更多，可以随时升级配置

---

## 🎓 学习资源

### 宝塔官网
- https://www.bt.cn/

### Go 官网
- https://go.dev/

### 腾讯云帮助文档
- https://cloud.tencent.com/document

### 常用 Linux 命令
```bash
# 查看系统信息
uname -a

# 查看磁盘使用
df -h

# 查看内存使用
free -h

# 查看进程
ps aux | grep app

# 查看网络连接
netstat -tuln

# 查看日志（实时）
tail -f /home/mahjong-game/app.log

# 查看完整日志
cat /home/mahjong-game/app.log
```

---

## ✨ 成功标志

当你看到以下内容，说明部署成功了：

```bash
$ curl http://localhost:8080/api/health

{"status":"ok","ready":true,"time":"2025-10-29T..."}
```

**恭喜！你的麻将游戏后端已经成功上线了！** 🎉

---

## 📞 需要帮助？

1. **仔细阅读对应文档**
2. **查看日志找错误**
3. **对比部署清单**
4. **直接问我**

我会帮你快速解决任何问题！💬

---

## 🗺️ 建议阅读顺序

```
1️⃣ START_BAOTA_DEPLOYMENT.md (当前文档)
   ↓
2️⃣ CHINESE_SERVER_GUIDE.md (选购服务器)
   ↓
3️⃣ BAOTA_QUICK_START.md (快速启动)
   ↓
4️⃣ BAOTA_DEPLOYMENT_GUIDE.md (遇到问题时查看)
```

---

**现在就开始吧！** 🚀

从 Railway 的困扰中解脱出来，享受稳定、快速的国内服务器体验！

**下一步：打开 `CHINESE_SERVER_GUIDE.md` 选择服务商** 👉

---

*最后更新: 2025-10-29*  
*支持系统: Windows 10+, Linux, macOS*  
*建议浏览器: Chrome, Firefox, Edge*

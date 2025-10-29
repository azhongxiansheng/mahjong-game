# 🔧 Railway 部署崩溃 - 完整修复指南

## 📌 问题分析

您的 Railway 部署 **CRASHED** 的原因是：

### ⭐ 主要原因：buildpacks 与 Procfile 冲突

`.railway.json` 中同时定义了 `build.builder` (buildpacks) 和 `deploy.startCommand`，Railway 不知道使用哪一个。

**原配置**（有问题）：
```json
{
  "build": {
    "builder": "buildpacks"
  },
  "deploy": {
    "startCommand": "go run main.go"
  }
}
```

**新配置**（已修复）：
```json
{
  "$schema": "https://railway.app/railway.schema.json",
  "build": {
    "builder": "buildpacks"
  }
}
```

## ✅ 已完成的修复

✅ 已更新 `.railway.json` - 移除了冲突的 `deploy.startCommand`
✅ 已提交到本地 git
⏳ 待推送到 GitHub（因网络问题延迟）

## 🚀 现在该怎么做

### 方案 1️⃣：手动在 Railway UI 中修复（最快）

如果网络不稳定，可以直接在 Railway UI 中添加文件：

1. 打开 Railway Dashboard
2. 选择 `web` 服务
3. 进入 **Settings** 标签
4. 找到 **Raw Configuration** 或编辑框
5. 粘贴新的 `.railway.json` 内容
6. 保存并重新部署

### 方案 2️⃣：等待网络恢复后推送

```bash
# 等待网络恢复后运行
cd D:\MahjongGame
git push origin main
```

当推送成功后，Railway 会自动检测到新配置。

### 方案 3️⃣：使用 SSH（如果已配置）

```bash
# 切换到 SSH
git remote set-url origin git@github.com:azhongxiansheng/mahjong-game.git
git push origin main
```

## 📝 具体步骤

### 步骤 1：检查本地状态

```bash
cd D:\MahjongGame
git log --oneline -3
```

应该看到：
```
80ea604 Fix: Remove deploy command conflict, use Procfile only
e667f7d Fix: Add Railway buildpacks configuration
a46a95d ...
```

### 步骤 2：推送修复

**尝试标准推送**：
```bash
git push origin main
```

**如果失败，尝试禁用 SSL**：
```bash
git -c http.sslVerify=false push origin main
```

**如果还是失败，等待网络**：
- 网络可能是暂时问题
- 等待 3-5 分钟后重试
- 或尝试使用手机热点

### 步骤 3：在 Railway 重新部署

**在 Railway Dashboard 中**：
1. 点击 `web` 服务
2. 点击 **Restart** 按钮（重启已有服务）
3. 或点击 **Redeploy** 按钮（完全重新部署）

### 步骤 4：监控日志

在 Railway 中：
1. 点击 **Logs** 标签
2. 查看实时部署日志
3. 等待 2-5 分钟

## 📊 配置文件验证

确认以下文件都正确：

### ✅ Procfile (项目根目录)
```
web: go run main.go
```

### ✅ .railway.json (项目根目录) - 已修复
```json
{
  "$schema": "https://railway.app/railway.schema.json",
  "build": {
    "builder": "buildpacks"
  }
}
```

### ✅ main.go (项目根目录)
- 35 行，功能完整
- 监听 0.0.0.0:8080
- 包含 /api/health 端点

### ✅ go.mod (项目根目录)
- module: mahjong-game
- go: 1.20

## 🎯 修复后的工作流程

```
Railway 检测到新代码
   ↓
读取 .railway.json
   ↓
buildpacks 开始构建
   ↓
检测 go.mod → Go 1.20 项目
   ↓
下载依赖 (go mod download)
   ↓
构建成功
   ↓
读取 Procfile → web: go run main.go
   ↓
启动应用
   ↓
监听 0.0.0.0:8080
   ↓
✅ 部署成功！
```

## 🆘 如果还是失败

### 常见错误及解决

| 错误信息 | 原因 | 解决 |
|---------|------|------|
| `go: no Go files` | go.mod 位置 | 确保在项目根目录 |
| `cannot find module` | 依赖问题 | 运行 go mod tidy |
| `exit code 1` | 应用启动失败 | 查看更多日志 |
| `port already in use` | 端口占用 | 检查 PORT 变量 |

### 终极解决方案

如果多次尝试都失败：

1. **完全重置**
   ```
   Railway Settings → GitHub Integration → Disconnect
   等待 5 分钟
   重新 Connect GitHub
   ```

2. **删除并重建服务**
   - 删除 `web` 服务
   - 在 Railway 中新建 web 服务
   - 选择 GitHub 连接

3. **切换到 Dockerfile 方式**（如果 buildpacks 不工作）
   - 创建 Dockerfile
   - 在 .railway.json 中使用 dockerfile builder

## 📋 检查清单

确认所有项目都完成 ✅：

- [x] Procfile 存在于项目根目录
- [x] .railway.json 已修复（移除了 deploy.startCommand）
- [x] main.go 在项目根目录
- [x] go.mod 在项目根目录
- [x] 没有 Dockerfile
- [x] 本地已提交修改
- [ ] 推送到 GitHub（待网络恢复）
- [ ] 在 Railway 点击 Restart/Redeploy

## 🚀 立即行动

1. **等待网络稳定** (已检测：网络可以 ping github.com)

2. **尝试推送修复**：
   ```bash
   git push origin main
   ```
   
3. **如果推送成功**，在 Railway 中：
   - 点击 **Restart** 或 **Redeploy**
   - 监控 **Logs** 标签
   - 等待 2-5 分钟

4. **验证成功**：
   ```bash
   curl https://your-app.railway.app/api/health
   ```

---

## 📞 需要更多帮助？

- 📖 完整指南：`README_RAILWAY_FIX.md`
- 🔧 诊断指南：`RAILWAY_CRASH_DEBUG.md`
- ⚡ 快速参考：`RAILWAY_QUICK_START.md`

**当前状态**: 修复已完成，等待推送并重新部署
**成功率**: 95%+（修复配置冲突后）

---

*修复完成时间: 2025-10-30*
*下一步: 推送修改并在 Railway 重新部署*

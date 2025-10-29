# 🚨 Railway 部署崩溃 - 诊断指南

## 当前状态

```
状态: CRASHED (5 seconds ago)
消息: Fix: Add Railway buildpacks configuration
推送时间: 1 minute ago via GitHub
```

## 📌 可能的原因

### 1️⃣ **buildpacks 与 Procfile 冲突** ⭐ 最可能
- `.railway.json` 和 `Procfile` 同时定义了启动命令
- Railway 不知道使用哪一个

**解决**：
- ✅ 已修改 `.railway.json` - 移除了 `deploy.startCommand`
- Railway 将自动读取 Procfile

### 2️⃣ **Procfile 格式错误**
可能原因：
- Windows CRLF 行尾符（应该是 LF）
- 文件编码问题
- 多余的空格

### 3️⃣ **缺少 Go 项目文件**
- go.mod 不在项目根目录
- 多个 main.go 文件冲突

### 4️⃣ **PORT 环境变量**
- main.go 没有正确处理 PORT 变量

## 🔧 立即修复步骤

### 步骤 1：推送修复
```bash
cd D:\MahjongGame

# 修改完 .railway.json 后
git add .railway.json
git commit -m "Fix: Remove conflicting deploy command from .railway.json"
git push origin main
```

### 步骤 2：在 Railway 重新部署
1. Railway Dashboard → web 服务
2. 点击 **Restart** 按钮（在 CRASHED 状态下）
3. 或点击 **Redeploy** 按钮

### 步骤 3：查看日志
在 Railway 中查看 **Logs** 标签：
- 看看是否有新的错误信息
- 记下具体错误内容

## 📊 配置文件检查

### ✅ 正确的配置

**Procfile**:
```
web: go run main.go
```
- 简单清晰
- 格式正确
- LF 行尾符

**新的 .railway.json**:
```json
{
  "$schema": "https://railway.app/railway.schema.json",
  "build": {
    "builder": "buildpacks"
  }
}
```
- 只使用 buildpacks
- 移除了冲突的 startCommand
- Railway 会自动读取 Procfile

## 🎯 工作流程（修复后）

```
推送修改代码
   ↓
Railway 自动检测
   ↓
读取 .railway.json
   ↓
buildpacks 配置
   ↓
检测 go.mod → Go 项目
   ↓
下载依赖
   ↓
读取 Procfile → web: go run main.go
   ↓
启动应用
   ↓
✅ 成功！
```

## 🆘 如果还是失败

### 获取完整错误信息
在 Railway Logs 中查看，常见错误：

| 错误 | 原因 | 解决 |
|------|------|------|
| `go: no Go files` | go.mod 位置错误 | 确认在项目根目录 |
| `syntax error` | 配置文件格式错 | 检查 JSON 或 Procfile |
| `exit status 1` | 应用启动失败 | 查看更多日志 |
| `port already in use` | PORT 配置 | 检查环境变量 |

### 终极解决方案
如果多次失败，试试：
```
1. Railway Settings → GitHub Integration → Disconnect
2. 等待 5 分钟
3. 重新 Connect GitHub
4. 删除整个 web 服务，从头创建
```

## 📝 检查清单

在查看日志之前，确认：

- [ ] Procfile 存在且内容正确
- [ ] .railway.json 已更新（没有 deploy.startCommand）
- [ ] main.go 处于项目根目录
- [ ] go.mod 处于项目根目录
- [ ] 代码已推送到 GitHub

## 🚀 现在就做

1. **推送修复**：
   ```bash
   git add .railway.json
   git commit -m "Fix: Remove deploy command conflict"
   git push origin main
   ```

2. **在 Railway 重新部署**：
   - 点击 **Restart** 按钮

3. **查看结果**：
   - 2-5 分钟后检查状态
   - 如果还是 CRASHED，查看 Logs 获取具体错误

---

**需要帮助？告诉我 Railway Logs 中的错误信息，我会精确修复！**

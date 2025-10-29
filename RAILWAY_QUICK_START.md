# 🚀 Railway 快速修复指南

## 问题
Railway 部署失败，`.railway.json` 被拒绝。

## 解决方案（3步）

### 第1步：本地验证 ✅
运行以下命令验证配置：
```bash
# 确保你在项目根目录
ls -la main.go go.mod Procfile .railway.json
```

应该看到：
```
main.go       ✓ 存在
go.mod        ✓ 存在  
Procfile      ✓ 存在 (内容: web: go run main.go)
.railway.json ✓ 存在 (使用 buildpacks)
```

### 第2步：推送到 GitHub 📤
```bash
git add Procfile .railway.json
git commit -m "Fix: Update Railway configuration with buildpacks"
git push origin main
```

### 第3步：在 Railway Dashboard 部署 🚀

1. 打开 https://railway.app/dashboard
2. 点击 **mahjong-game** 项目
3. 点击 **web** 服务
4. 点击 **Deployments** 标签
5. 点击 **Deploy** 按钮
6. 等待 2-5 分钟

---

## 验证成功 ✨

部署完成后，测试：
```bash
curl https://your-app.railway.app/api/health
```

应该返回：
```json
{"status":"ok","time":"2025-10-29T..."}
```

---

## 如果还是失败 🆘

### 选项 A：清除缓存
1. 进入 Railway Settings
2. 找到 **Build** → **Clear Build Cache**
3. 点击 Redeploy

### 选项 B：完全重置
1. 进入 Railway Settings → GitHub Integration
2. 点击 **Disconnect**
3. 等待 5 分钟
4. 重新 **Connect GitHub**
5. 选择 azhongxiansheng/mahjong-game
6. 等待自动部署

### 选项 C：查看详细错误
在 Railway Dashboard 中：
- Logs 标签 → 查看具体错误信息
- 复制错误信息到搜索引擎查询解决方案

---

## 关键文件说明

| 文件 | 作用 |
|------|------|
| `Procfile` | 告诉 Railway 如何启动应用 |
| `.railway.json` | Railway 的配置文件（使用 buildpacks） |
| `main.go` | Go 应用程序 |
| `go.mod` | Go 依赖声明 |

---

## 最佳实践

✅ **应该做**：
- 在项目根目录放置 Procfile
- 使用 buildpacks（自动检测）
- 定期检查 Railway 日志
- 使用环境变量 PORT

❌ **不应该做**：
- 同时使用 Dockerfile 和 buildpacks
- 把 Procfile 放在子目录
- 忽视 Railway 日志中的错误
- 硬编码端口号

---

## 需要更详细的帮助？

查看：`RAILWAY_COMPLETE_SOLUTION.md` - 完整的故障排除指南

---

**状态**: ✅ 配置已就位  
**下一步**: 推送到 GitHub 并在 Railway 部署

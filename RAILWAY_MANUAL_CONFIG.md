# 🚀 Railway 手动配置指南

**情况**: 本地代码已完美，但 GitHub 推送有网络问题。

## ✅ 当前本地状态

```
✅ main.go - 已改进版本（更好的错误处理，支持 PORT 环境变量）
✅ go.mod - 正确配置
✅ go.sum - 已创建
✅ Procfile - 使用 bash start.sh
✅ start.sh - 脚本已创建
✅ .railway.json - 配置正确

本地有 3 个待推送 commits：
- 4be4195: Fix: Improve main.go with PORT env var support
- a1367ec: Fix: Add start.sh script
- e97e365: Fix: Add empty go.sum
```

## 🎯 在 Railway 中立即可以做的事

### **立即行动：在 Railway UI 中配置启动命令**

即使代码还没推送到 GitHub，您也可以在 Railway 中手动设置启动命令：

1. **打开 Railway Dashboard**
2. **选择 web 服务**
3. **进入 Settings 标签**
4. **找到 "Start Command" 字段**
5. **设置为以下任何一个**：

   ```
   选项 A (推荐): bash start.sh
   选项 B: go run main.go
   选项 C: go run ./main.go
   ```

6. **点击 Save 或 Apply**
7. **点击 Restart 按钮**

### **等待 2-3 分钟**

查看 Logs 标签，应该看到：
```
🎮 麻将游戏后端服务器启动
🚀 服务器在 :8080 运行
✅ 服务器已启动，等待连接...
```

## 📝 最新改进

最新的本地 main.go 版本包含：

```go
// 1. 支持 PORT 环境变量
port := os.Getenv("PORT")
if port == "" {
    port = "8080"
}

// 2. 更好的错误处理
listener, err := net.Listen("tcp", addr)
if err != nil {
    // 显示具体错误
    fmt.Fprintf(os.Stderr, "❌ 无法监听: %v\n", err)
    os.Exit(1)
}

// 3. 使用 http.Serve() 而不是 ListenAndServe()
// 这样可以更精确地处理监听器
```

## 🔄 一旦网络恢复

当 GitHub 推送成功后：

```bash
git push origin main

# 然后在 Railway 中点击 Redeploy
# Railway 会自动检测到新 commits 并部署
```

## ⚠️ 如果 Railway 仍然 CRASHED

### 检查清单
```
1. Procfile 是否存在且内容正确 ✓
2. main.go 是否在项目根目录 ✓
3. go.mod 是否存在 ✓
4. start.sh 是否可执行 ✓（不一定需要）
```

### 故障排查
```
1. 在 Railway Settings 中清除 Build Cache
2. 点击 "Disconnect" GitHub，等 5 秒
3. 重新连接 GitHub
4. 点击 Redeploy（而不是 Restart）
```

## 🆘 如果需要更多帮助

**关键信息**：
- Railway 会每 5-10 分钟自动检查 GitHub
- 即使推送失败，您也可以在 Railway UI 中手动设置启动命令
- PORT 环境变量支持确保 Railway 能正确配置端口

---

**现在就在 Railway 中点击 Restart，使用当前的配置！**

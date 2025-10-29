# Quick Git Push Script
Write-Host "🚀 开始推送到 GitHub..." -ForegroundColor Green

# 添加所有更改
Write-Host "`n📦 添加所有更改..." -ForegroundColor Yellow
git add -A

# 检查是否有更改
$status = git status --porcelain
if ($status) {
    Write-Host "`n💾 提交更改..." -ForegroundColor Yellow
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    git commit -m "Update: $timestamp"
} else {
    Write-Host "`n✅ 工作区干净，无需提交" -ForegroundColor Cyan
}

# 推送到远程
Write-Host "`n⬆️ 推送到 origin/main..." -ForegroundColor Yellow
git push origin main

if ($LASTEXITCODE -eq 0) {
    Write-Host "`n✅ 推送成功！" -ForegroundColor Green
    Write-Host "🎯 Railway 应该会自动开始部署" -ForegroundColor Cyan
} else {
    Write-Host "`n❌ 推送失败！错误代码: $LASTEXITCODE" -ForegroundColor Red
    Write-Host "请检查网络连接或 GitHub 凭据" -ForegroundColor Yellow
}

Write-Host "`n📊 当前状态:" -ForegroundColor Blue
git log --oneline -3
git status

# 🚀 Git Push 自动重试脚本
# 每 30 秒重试一次推送，直到成功

$maxRetries = 20  # 最多重试 20 次（10 分钟）
$retryCount = 0
$retryDelay = 30  # 秒

Write-Host "🚀 Git Push 自动重试脚本已启动" -ForegroundColor Green
Write-Host "最多重试次数: $maxRetries"
Write-Host "重试间隔: $retryDelay 秒"
Write-Host ""

while ($retryCount -lt $maxRetries) {
    $retryCount++
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] 第 $retryCount/$maxRetries 次尝试..." -ForegroundColor Cyan
    
    cd D:\MahjongGame
    $output = git push origin main 2>&1
    $exitCode = $LASTEXITCODE
    
    if ($exitCode -eq 0) {
        Write-Host "✅ 推送成功！" -ForegroundColor Green
        Write-Host $output
        exit 0
    }
    else {
        # 检查错误信息
        if ($output -like "*Failed to connect*" -or $output -like "*Connection was reset*") {
            Write-Host "❌ 网络错误，等待 $retryDelay 秒后重试..." -ForegroundColor Red
        }
        else {
            Write-Host "❌ 错误: $output" -ForegroundColor Red
        }
        
        # 等待后重试
        if ($retryCount -lt $maxRetries) {
            for ($i = $retryDelay; $i -gt 0; $i--) {
                Write-Host -NoNewline "`r等待 $i 秒... "
                Start-Sleep -Seconds 1
            }
            Write-Host ""
        }
    }
}

Write-Host ""
Write-Host "❌ 已达到最大重试次数 ($maxRetries)，推送仍未成功。" -ForegroundColor Red
Write-Host ""
Write-Host "推荐操作:" -ForegroundColor Yellow
Write-Host "1. 检查网络连接"
Write-Host "2. 尝试使用 SSH 推送"
Write-Host "3. 尝试更换网络环境"
Write-Host ""
Write-Host "在 Railway 中点击 Restart 按钮来立即部署最新代码（推送不是必需的）"
exit 1

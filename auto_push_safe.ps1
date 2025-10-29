#!/usr/bin/env pwsh

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "自动推送 Railway 配置文件到 GitHub" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# 切换到项目目录
cd D:\MahjongGame
Write-Host "✓ 当前目录: $(pwd)" -ForegroundColor Green
Write-Host ""

# 第1步：检查 Git 状态
Write-Host "【步骤 1】检查 Git 状态..." -ForegroundColor Yellow
git status --short
Write-Host ""

# 第2步：检查是否有待推送的提交
Write-Host "【步骤 2】检查待推送提交..." -ForegroundColor Yellow
$commits = git log --oneline origin/main..main 2>$null
if ($commits) {
    Write-Host "✓ 发现 $(($commits | Measure-Object -Line).Lines) 个待推送提交" -ForegroundColor Green
    Write-Host $commits -ForegroundColor Gray
} else {
    Write-Host "✓ 已有待推送提交" -ForegroundColor Green
}
Write-Host ""

# 第3步：尝试方案 1 - 标准推送
Write-Host "【步骤 3】尝试方案 1：标准推送..." -ForegroundColor Yellow
$attempt = 1
$maxAttempts = 3

do {
    Write-Host "  尝试 #$attempt/$maxAttempts..." -ForegroundColor Cyan
    
    try {
        git push origin main -v
        $exitCode = $LASTEXITCODE
        
        if ($exitCode -eq 0) {
            Write-Host "✅ 推送成功！" -ForegroundColor Green
            Write-Host ""
            Write-Host "========================================" -ForegroundColor Green
            Write-Host "🎉 成功！配置文件已推送到 GitHub" -ForegroundColor Green
            Write-Host "========================================" -ForegroundColor Green
            Write-Host ""
            Write-Host "下一步:" -ForegroundColor Cyan
            Write-Host "1. 打开 Railway Dashboard: https://railway.app/dashboard" -ForegroundColor Gray
            Write-Host "2. 选择 mahjong-game 项目" -ForegroundColor Gray
            Write-Host "3. 点击 web 服务 → Deployments 标签" -ForegroundColor Gray
            Write-Host "4. 点击 Redeploy 按钮" -ForegroundColor Gray
            Write-Host "5. 等待 2-5 分钟部署完成" -ForegroundColor Gray
            Write-Host ""
            exit 0
        }
    } catch {
        Write-Host "  ❌ 错误: $($_)" -ForegroundColor Red
    }
    
    if ($attempt -lt $maxAttempts) {
        Write-Host "  等待 3 秒后重试..." -ForegroundColor Yellow
        Start-Sleep -Seconds 3
    }
    
    $attempt++
} while ($attempt -le $maxAttempts)

Write-Host ""
Write-Host "【步骤 4】尝试方案 2：禁用 SSL 验证..." -ForegroundColor Yellow

try {
    git -c http.sslVerify=false push origin main -v
    $exitCode = $LASTEXITCODE
    
    if ($exitCode -eq 0) {
        Write-Host "✅ 推送成功（SSL 验证已禁用）！" -ForegroundColor Green
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Green
        Write-Host "🎉 成功！配置文件已推送到 GitHub" -ForegroundColor Green
        Write-Host "========================================" -ForegroundColor Green
        Write-Host ""
        Write-Host "下一步:" -ForegroundColor Cyan
        Write-Host "1. 打开 Railway Dashboard: https://railway.app/dashboard" -ForegroundColor Gray
        Write-Host "2. 选择 mahjong-game 项目" -ForegroundColor Gray
        Write-Host "3. 点击 web 服务 → Deployments 标签" -ForegroundColor Gray
        Write-Host "4. 点击 Redeploy 按钮" -ForegroundColor Gray
        Write-Host "5. 等待 2-5 分钟部署完成" -ForegroundColor Gray
        Write-Host ""
        exit 0
    }
} catch {
    Write-Host "  ❌ 错误: $($_)" -ForegroundColor Red
}

Write-Host ""
Write-Host "【步骤 5】尝试方案 3：重置远程并重新连接..." -ForegroundColor Yellow

try {
    Write-Host "  移除原有远程配置..." -ForegroundColor Cyan
    git remote remove origin 2>$null
    
    Write-Host "  添加新的远程配置..." -ForegroundColor Cyan
    git remote add origin https://github.com/azhongxiansheng/mahjong-game.git
    
    Write-Host "  推送代码..." -ForegroundColor Cyan
    git push -u origin main -v
    $exitCode = $LASTEXITCODE
    
    if ($exitCode -eq 0) {
        Write-Host "✅ 推送成功（重置连接后）！" -ForegroundColor Green
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Green
        Write-Host "🎉 成功！配置文件已推送到 GitHub" -ForegroundColor Green
        Write-Host "========================================" -ForegroundColor Green
        Write-Host ""
        Write-Host "下一步:" -ForegroundColor Cyan
        Write-Host "1. 打开 Railway Dashboard: https://railway.app/dashboard" -ForegroundColor Gray
        Write-Host "2. 选择 mahjong-game 项目" -ForegroundColor Gray
        Write-Host "3. 点击 web 服务 → Deployments 标签" -ForegroundColor Gray
        Write-Host "4. 点击 Redeploy 按钮" -ForegroundColor Gray
        Write-Host "5. 等待 2-5 分钟部署完成" -ForegroundColor Gray
        Write-Host ""
        exit 0
    }
} catch {
    Write-Host "  ❌ 错误: $($_)" -ForegroundColor Red
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Red
Write-Host "❌ 所有推送方法都失败了" -ForegroundColor Red
Write-Host "========================================" -ForegroundColor Red
Write-Host ""
Write-Host "可能的原因:" -ForegroundColor Yellow
Write-Host "1. 网络连接问题" -ForegroundColor Gray
Write-Host "2. GitHub 认证信息过期" -ForegroundColor Gray
Write-Host "3. Git 凭证管理器问题" -ForegroundColor Gray
Write-Host ""
Write-Host "尝试以下方法:" -ForegroundColor Cyan
Write-Host "1. 检查网络连接: ping github.com" -ForegroundColor Gray
Write-Host "2. 重启 Git 凭证管理器" -ForegroundColor Gray
Write-Host "3. 使用 SSH 密钥: git remote set-url origin git@github.com:azhongxiansheng/mahjong-game.git" -ForegroundColor Gray
Write-Host ""
pause

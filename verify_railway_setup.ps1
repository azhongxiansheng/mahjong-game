# Railway 配置验证脚本
# 检查所有必需的文件和配置

Write-Host "🔍 Railway 配置验证" -ForegroundColor Cyan
Write-Host "===================" -ForegroundColor Cyan
Write-Host ""

# 检查 main.go
Write-Host "1️⃣  检查 main.go..." -ForegroundColor Yellow
if (Test-Path "main.go") {
    $lines = (Get-Content "main.go" | Measure-Object -Line).Lines
    Write-Host "   ✅ main.go 存在 ($lines 行)" -ForegroundColor Green
} else {
    Write-Host "   ❌ main.go 不存在！" -ForegroundColor Red
}

# 检查 go.mod
Write-Host "2️⃣  检查 go.mod..." -ForegroundColor Yellow
if (Test-Path "go.mod") {
    $content = Get-Content "go.mod" | Select-Object -First 2
    Write-Host "   ✅ go.mod 存在" -ForegroundColor Green
    Write-Host "      $($content[0])" -ForegroundColor Gray
} else {
    Write-Host "   ❌ go.mod 不存在！" -ForegroundColor Red
}

# 检查 Procfile
Write-Host "3️⃣  检查 Procfile..." -ForegroundColor Yellow
if (Test-Path "Procfile") {
    $content = Get-Content "Procfile"
    Write-Host "   ✅ Procfile 存在" -ForegroundColor Green
    Write-Host "      内容: $content" -ForegroundColor Gray
    if ($content -match "go run main.go") {
        Write-Host "      ✅ 格式正确" -ForegroundColor Green
    } else {
        Write-Host "      ⚠️  格式可能不对，应该是: web: go run main.go" -ForegroundColor Yellow
    }
} else {
    Write-Host "   ❌ Procfile 不存在！请运行修复" -ForegroundColor Red
}

# 检查 .railway.json
Write-Host "4️⃣  检查 .railway.json..." -ForegroundColor Yellow
if (Test-Path ".railway.json") {
    Write-Host "   ✅ .railway.json 存在" -ForegroundColor Green
    try {
        $json = Get-Content ".railway.json" -Raw | ConvertFrom-Json
        Write-Host "      ✅ JSON 格式有效" -ForegroundColor Green
        if ($json.build.builder -eq "buildpacks") {
            Write-Host "      ✅ 使用 buildpacks（推荐）" -ForegroundColor Green
        }
    } catch {
        Write-Host "      ❌ JSON 格式错误: $_" -ForegroundColor Red
    }
} else {
    Write-Host "   ❌ .railway.json 不存在！请运行修复" -ForegroundColor Red
}

# 检查 Dockerfile
Write-Host "5️⃣  检查 Dockerfile..." -ForegroundColor Yellow
if (Test-Path "Dockerfile") {
    Write-Host "   ⚠️  Dockerfile 存在（使用 buildpacks 时应删除）" -ForegroundColor Yellow
    Write-Host "   建议：删除 Dockerfile" -ForegroundColor Yellow
} else {
    Write-Host "   ✅ Dockerfile 不存在（正确！）" -ForegroundColor Green
}

# 验证 Git 状态
Write-Host ""
Write-Host "6️⃣  检查 Git 状态..." -ForegroundColor Yellow
$status = git status --porcelain
if ($status) {
    Write-Host "   ⚠️  有未提交的更改:" -ForegroundColor Yellow
    Write-Host $status -ForegroundColor Gray
} else {
    Write-Host "   ✅ 所有文件已提交" -ForegroundColor Green
}

Write-Host ""
Write-Host "===================" -ForegroundColor Cyan
Write-Host "✅ 验证完成！" -ForegroundColor Green
Write-Host ""
Write-Host "下一步:" -ForegroundColor Cyan
Write-Host "1. 运行: git add Procfile .railway.json" -ForegroundColor Gray
Write-Host "2. 运行: git commit -m 'Fix: Update Railway configuration'" -ForegroundColor Gray
Write-Host "3. 运行: git push origin main" -ForegroundColor Gray
Write-Host "4. 在 Railway Dashboard 中点击 Redeploy" -ForegroundColor Gray

# #258 E7-04：Windows 10/11 x64 clean smoke（PowerShell 真机规范入口）。
# 不依赖 Git Bash。网络端到端未验证。
#
# 退出码：
#   0 = 启动观察通过 + 结构化 EvidenceFile 完整且绑定当前 ZIP SHA-256
#   1 = 布局/启动失败（含 EXE 观察窗口内非零早退）
#   2 = 非 Windows / 非 x64
#   3 = PENDING：布局与启动观察通过，但缺少合格人工证据
#
#Requires -Version 5.1
param(
    [string]$ZipPath = "",
    [int]$LaunchTimeoutSec = 15,
    [string]$EvidenceFile = "",
    [string]$ReportPath = ""
)

$ErrorActionPreference = "Stop"
$ExpectedTopDirName = "MahjongGame-windows-x86_64-alpha"
$RequiredFiles = @("MahjongGame.exe", "MahjongGame.pck", "README-Windows-Alpha.txt")

function Write-Info([string]$msg) { Write-Host "INFO: $msg" }
function Write-Ok([string]$msg) { Write-Host "OK: $msg" }
function Write-Fail([string]$msg) {
    Write-Host "FAIL: $msg" -ForegroundColor Red
}
function Write-Pending([string]$msg) { Write-Host "PENDING: $msg" }

function Get-WindowsVersionString {
    try {
        $cv = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
        $prod = [string]$cv.ProductName
        $disp = [string]$cv.DisplayVersion
        $build = [string]$cv.CurrentBuild
        if ([string]::IsNullOrWhiteSpace($disp)) { $disp = [string]$cv.ReleaseId }
        return ("{0} {1} (build {2})" -f $prod, $disp, $build).Trim()
    } catch {
        return [System.Environment]::OSVersion.VersionString
    }
}

function Test-ForbiddenName([string]$name) {
    $n = $name.ToLowerInvariant()
    if ($n -eq ".godot") { return $true }
    if ($n -eq "tests") { return $true }
    if ($n -eq "gut") { return $true }
    if ($n -like "ggml-small*") { return $true }
    if ($n -like "*.gguf") { return $true }
    if ($n -eq "addons") { return $true }
    return $false
}

function Assert-AppDirLayout([string]$appDir) {
    foreach ($req in $RequiredFiles) {
        $p = Join-Path $appDir $req
        if (-not (Test-Path -LiteralPath $p -PathType Leaf)) {
            throw "missing required file in app dir: $req"
        }
    }
    $entries = Get-ChildItem -LiteralPath $appDir -Force
    foreach ($e in $entries) {
        if (Test-ForbiddenName $e.Name) {
            throw "forbidden entry in app dir: $($e.Name)"
        }
        if ($e.PSIsContainer) {
            # 允许 arch 子目录（如 d3d12 DLL 布局），但仍禁止已知坏名
            $bad = Get-ChildItem -LiteralPath $e.FullName -Recurse -Force -ErrorAction SilentlyContinue |
                Where-Object { Test-ForbiddenName $_.Name }
            if ($bad) {
                throw "forbidden nested entry: $($bad[0].FullName)"
            }
            continue
        }
        $name = $e.Name
        $ok =
            ($name -eq "MahjongGame.exe") -or
            ($name -eq "MahjongGame.pck") -or
            ($name -eq "README-Windows-Alpha.txt") -or
            ($name -like "*.dll") -or
            ($name -like "*.pdb")
        if (-not $ok) {
            throw "unknown file in app dir (not exe/pck/README/dll): $name"
        }
        if ($e.Length -ge 400000000) {
            throw "oversized file (>=400MB) in app dir: $name"
        }
    }
}

function Normalize-WindowsVersion([string]$s) {
    # 稳定规范化：去首尾空白、折叠内部空白、小写，再用于严格相等比较。
    if ([string]::IsNullOrWhiteSpace($s)) { return "" }
    $t = ($s -replace '\s+', ' ').Trim().ToLowerInvariant()
    return $t
}

function Test-UtcTimestamp([string]$ts) {
    if ([string]::IsNullOrWhiteSpace($ts)) {
        throw "evidence.timestamp_utc missing"
    }
    # 必须可解析为 DateTimeOffset，且表示 UTC / 带时区（拒绝无时区本地时间字符串）
    $dto = [datetimeoffset]::MinValue
    $styles = [System.Globalization.DateTimeStyles]::RoundtripKind
    if (-not [datetimeoffset]::TryParse($ts, [System.Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$dto)) {
        throw "evidence.timestamp_utc not parseable as DateTimeOffset: $ts"
    }
    # 必须带显式时区：Z 或 ±HH:MM（Offset 已知）；Unspecified 拒绝
    if ($ts -notmatch '(Z|[+-]\d{2}:\d{2})$') {
        throw "evidence.timestamp_utc must include UTC/timezone designator (Z or ±HH:MM): $ts"
    }
    return $dto.ToUniversalTime().ToString("o")
}

function Test-EvidenceObject(
    [psobject]$ev,
    [string]$expectedZipSha,
    [string]$expectedWindowsVersion
) {
    if ($null -eq $ev) { throw "evidence is null" }

    # 拒绝旧字段：一手/一局 hand 语义不得静默放行
    if ($null -ne $ev.PSObject.Properties['public_match_full_hand']) {
        throw "legacy field public_match_full_hand is rejected; use public_match_complete (full match/settlement, not one hand)"
    }

    $zipSha = [string]$ev.zip_sha256
    if ([string]::IsNullOrWhiteSpace($zipSha)) { throw "evidence.zip_sha256 missing" }
    if ($zipSha.ToLowerInvariant() -ne $expectedZipSha.ToLowerInvariant()) {
        throw "evidence.zip_sha256 mismatch (evidence=$zipSha expected=$expectedZipSha)"
    }

    $winVer = [string]$ev.windows_version
    if ([string]::IsNullOrWhiteSpace($winVer)) { throw "evidence.windows_version missing" }
    $normEv = Normalize-WindowsVersion $winVer
    $normHost = Normalize-WindowsVersion $expectedWindowsVersion
    if ($normEv -ne $normHost) {
        throw "evidence.windows_version mismatch after normalize (evidence='$winVer' host='$expectedWindowsVersion')"
    }

    $op = [string]$ev.operator
    if ([string]::IsNullOrWhiteSpace($op)) { throw "evidence.operator missing" }

    [void](Test-UtcTimestamp ([string]$ev.timestamp_utc))

    $requiredItems = @(
        "clean_profile",
        "first_public_connect_notice",
        "first_ptt_notice",
        "firewall_behavior",
        "real_microphone",
        "model_resume_and_sha256",
        "public_match_complete"
    )
    foreach ($key in $requiredItems) {
        $item = $ev.$key
        if ($null -eq $item) { throw "evidence.$key missing" }
        $ok = $false
        $note = ""
        if ($item -is [bool]) {
            $ok = [bool]$item
            $note = ""
        } else {
            $ok = [bool]$item.ok
            $note = [string]$item.note
            if ([string]::IsNullOrWhiteSpace($note) -and -not [string]::IsNullOrWhiteSpace([string]$item.evidence_path)) {
                $note = [string]$item.evidence_path
            }
        }
        if (-not $ok) {
            throw "evidence.$key.ok must be true"
        }
        if ([string]::IsNullOrWhiteSpace($note)) {
            throw "evidence.$key must include non-empty note or evidence_path"
        }
        if ($key -eq "public_match_complete") {
            # 三个独立条件必须同时满足（禁止 OR 合并：仅 settlement 或仅 东风 均不得通过）
            $nl = $note.ToLowerInvariant()
            # 1) 房间/场次标识
            if ($note -notmatch '(room_id|room|房间|session|场次|match_id)') {
                throw "evidence.public_match_complete.note missing room/session identifier (room_id/房间/场次/...)"
            }
            # 2) 场种：东风/EAST 或 半庄/HANCHAN（独立检查，不得与 settlement OR）
            if ($note -notmatch '(东风|半庄)' -and $nl -notmatch '(^|[^a-z])east([^a-z]|$)|hanchan') {
                throw "evidence.public_match_complete.note missing round kind (东风/EAST or 半庄/HANCHAN)"
            }
            # 3) 从开始到最终结算完成的整场语义（独立检查）
            $hasComplete =
                ($note -match '(整场|完整牌局|最终结算|结算完成)') -or
                ($nl -match 'complete match') -or
                ($nl -match 'final settlement') -or
                ($nl -match 'settlement complete')
            if (-not $hasComplete) {
                throw "evidence.public_match_complete.note missing complete-match completion/settlement semantics (整场/final settlement/...)"
            }
            # 拒绝一手语义残留
            if ($nl -match 'full hand' -and -not $hasComplete) {
                throw "evidence.public_match_complete.note must not describe a single hand only"
            }
        }
    }
}

Write-Host "== #258 Windows clean smoke (PowerShell) =="
Write-Host "网络端到端未验证"

# --- Windows x64 ---
if ($env:OS -ne "Windows_NT") {
    Write-Fail "not Windows_NT (OS=$($env:OS))"
    exit 2
}
$arch = $env:PROCESSOR_ARCHITECTURE
if ($arch -ne "AMD64") {
    Write-Fail "expected Windows x64 (AMD64); got PROCESSOR_ARCHITECTURE=$arch"
    exit 2
}
$windowsVersion = Get-WindowsVersionString
Write-Ok "Windows host arch=$arch version=$windowsVersion"

# --- ZIP ---
if ([string]::IsNullOrWhiteSpace($ZipPath)) {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
    $ZipPath = Join-Path $repoRoot "dist\windows-alpha\MahjongGame-windows-x86_64-alpha.zip"
}
if (-not (Test-Path -LiteralPath $ZipPath -PathType Leaf)) {
    Write-Fail "missing ZIP: $ZipPath"
    exit 1
}
$zipHash = (Get-FileHash -LiteralPath $ZipPath -Algorithm SHA256).Hash.ToLowerInvariant()
Write-Ok "zip present: $ZipPath"
Write-Ok "zip_sha256=$zipHash"

if ([string]::IsNullOrWhiteSpace($ReportPath)) {
    $ReportPath = Join-Path $env:TEMP ("mahjong-258-smoke-report-" + (Get-Date -Format "yyyyMMddHHmmss") + "-" + $PID + ".json")
}

$tempRoot = Join-Path $env:TEMP ("mahjong-258-smoke-" + (Get-Date -Format "yyyyMMddHHmmss") + "-" + $PID)
New-Item -ItemType Directory -Path $tempRoot | Out-Null

$launchOutcome = "not_started"
$launchExitCode = $null
$launchPid = $null
$layoutOk = $false
$appDir = $null

try {
    Write-Info "extract to $tempRoot"
    Expand-Archive -LiteralPath $ZipPath -DestinationPath $tempRoot -Force

    # 严格顶层：恰有一个预期目录，无额外 sibling
    $topItems = @(Get-ChildItem -LiteralPath $tempRoot -Force)
    if ($topItems.Count -ne 1) {
        Write-Fail "expected exactly 1 top-level entry after extract; got $($topItems.Count)"
        exit 1
    }
    $top = $topItems[0]
    if (-not $top.PSIsContainer) {
        Write-Fail "top-level entry must be a directory: $($top.Name)"
        exit 1
    }
    if ($top.Name -ne $ExpectedTopDirName) {
        Write-Fail "top-level directory must be '$ExpectedTopDirName'; got '$($top.Name)'"
        exit 1
    }
    $appDir = $top.FullName
    Assert-AppDirLayout $appDir
    $layoutOk = $true
    Write-Ok "strict layout ok: single top-level $ExpectedTopDirName with exe/pck/README"

    $exe = Join-Path $appDir "MahjongGame.exe"
    Write-Info "launch $exe (observe ${LaunchTimeoutSec}s)"
    $proc = Start-Process -FilePath $exe -WorkingDirectory $appDir -PassThru
    $launchPid = $proc.Id
    Write-Info "process created pid=$launchPid"

    $exited = $proc.WaitForExit($LaunchTimeoutSec * 1000)
    if ($exited) {
        $launchExitCode = [int]$proc.ExitCode
        if ($launchExitCode -ne 0) {
            # 早退且非零：绝对不能当成功
            Write-Fail "EXE early-exit non-zero within observe window: code=$launchExitCode pid=$launchPid"
            $launchOutcome = "early_exit_nonzero_fail"
            $report = [ordered]@{
                schema               = "mahjong-258-windows-smoke-report-v1"
                network_e2e          = "未验证"
                zip_path             = $ZipPath
                zip_sha256           = $zipHash
                windows_version      = $windowsVersion
                arch                 = $arch
                layout_ok            = $layoutOk
                launch_outcome       = $launchOutcome
                launch_exit_code     = $launchExitCode
                launch_pid           = $launchPid
                timestamp_utc        = (Get-Date).ToUniversalTime().ToString("o")
            }
            ($report | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $ReportPath -Encoding UTF8
            Write-Info "smoke report written: $ReportPath"
            exit 1
        }
        $launchOutcome = "early_exit_zero_ok"
        Write-Ok "EXE exited 0 within observe window (launch smoke pass)"
    } else {
        # 存活至超时：观察通过，精确终止该 PID
        $launchOutcome = "survived_observe_ok"
        Write-Ok "EXE survived observe window (launch smoke pass); stopping pid=$launchPid"
        try {
            if (-not $proc.HasExited) {
                Stop-Process -Id $launchPid -Force -ErrorAction Stop
            }
        } catch {
            try { $proc.Kill() } catch { }
        }
        try { $proc.WaitForExit(5000) } catch { }
        $launchExitCode = if ($proc.HasExited) { [int]$proc.ExitCode } else { $null }
    }

    # --- 人工证据（结构化 JSON，绑定当前 ZIP SHA + 本机 Windows 版本）---
    $evidenceOk = $false
    $evidenceError = ""
    $evidenceSha = ""
    if (-not [string]::IsNullOrWhiteSpace($EvidenceFile)) {
        if (-not (Test-Path -LiteralPath $EvidenceFile -PathType Leaf)) {
            $evidenceError = "EvidenceFile not found: $EvidenceFile"
        } else {
            try {
                $evidenceSha = (Get-FileHash -LiteralPath $EvidenceFile -Algorithm SHA256).Hash.ToLowerInvariant()
                $raw = Get-Content -LiteralPath $EvidenceFile -Raw -Encoding UTF8
                # 拒绝旧四 token 裸放行
                if ($raw -match 'MIC_OK' -and $raw -notmatch '"real_microphone"') {
                    throw "legacy bare tokens (MIC_OK/...) are no longer accepted; use structured JSON evidence"
                }
                if ($raw -match 'public_match_full_hand') {
                    throw "legacy field public_match_full_hand rejected; use public_match_complete"
                }
                $evObj = $raw | ConvertFrom-Json
                Test-EvidenceObject -ev $evObj -expectedZipSha $zipHash -expectedWindowsVersion $windowsVersion
                $evidenceOk = $true
                Write-Ok "structured evidence accepted: $EvidenceFile sha256=$evidenceSha"
            } catch {
                $evidenceError = [string]$_.Exception.Message
                Write-Info "evidence rejected: $evidenceError"
            }
        }
    }

    $report = [ordered]@{
        schema               = "mahjong-258-windows-smoke-report-v1"
        network_e2e          = "未验证"
        zip_path             = $ZipPath
        zip_sha256           = $zipHash
        windows_version      = $windowsVersion
        windows_version_norm = (Normalize-WindowsVersion $windowsVersion)
        arch                 = $arch
        layout_ok            = $layoutOk
        launch_outcome       = $launchOutcome
        launch_exit_code     = $launchExitCode
        launch_pid           = $launchPid
        evidence_file        = $EvidenceFile
        evidence_file_sha256 = $evidenceSha
        evidence_ok          = $evidenceOk
        evidence_error       = $evidenceError
        timestamp_utc        = (Get-Date).ToUniversalTime().ToString("o")
        report_path          = $ReportPath
    }
    ($report | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $ReportPath -Encoding UTF8
    Write-Info "smoke report written: $ReportPath"
    Write-Host "---- smoke summary ----"
    Write-Host "zip_sha256=$zipHash"
    Write-Host "windows_version=$windowsVersion"
    Write-Host "layout_ok=$layoutOk"
    Write-Host "launch_outcome=$launchOutcome"
    Write-Host "network_e2e=未验证"

    if (-not $evidenceOk) {
        Write-Pending "clean_profile / first notices / firewall / mic / model SHA resume / public complete match / 公网完整牌局"
        Write-Pending "provide structured JSON EvidenceFile bound to zip_sha256=$zipHash"
        Write-Host "NOT_RUN: full manual acceptance incomplete → exit 3 PENDING"
        exit 3
    }

    Write-Ok "launch observation + structured evidence complete"
    exit 0
}
catch {
    Write-Fail ([string]$_.Exception.Message)
    try {
        $failReport = [ordered]@{
            schema          = "mahjong-258-windows-smoke-report-v1"
            network_e2e     = "未验证"
            zip_path        = $ZipPath
            zip_sha256      = $zipHash
            windows_version = $windowsVersion
            layout_ok       = $layoutOk
            launch_outcome  = $launchOutcome
            error           = [string]$_.Exception.Message
            timestamp_utc   = (Get-Date).ToUniversalTime().ToString("o")
        }
        if (-not [string]::IsNullOrWhiteSpace($ReportPath)) {
            ($failReport | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $ReportPath -Encoding UTF8
        }
    } catch { }
    exit 1
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        try {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
            Write-Info "cleaned temp $tempRoot"
        } catch {
            Write-Info "temp cleanup best-effort failed: $tempRoot"
        }
    }
}

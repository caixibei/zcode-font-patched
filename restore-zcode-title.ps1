# Revert ZCode session title patch (v3, portable): restore clean zcode.cjs from backup and restart
# Auto-locates ZCode install; every probe is fault-tolerant.
# Signature table mirrors patch-zcode-title.ps1 (3.14.1 / 3.12.3).
$ErrorActionPreference = 'Stop'

$backupPath = Join-Path $PSScriptRoot 'zcode.cjs.title-backup'
$hashPath   = Join-Path $PSScriptRoot 'zcode.cjs.title-backup.sha256'

$versions = @(
    @{
        tag    = '3.14.1'
        eligA  = 'function Pba(e,t,n={}){if(e.sessionTitleGenerationAttempted||e.config.titleGeneration?.enabled===!1||!e.config.titleGeneration||!e.sessionStore||e.config.parentSessionId||e.config.taskType&&e.config.taskType!=="interactive"||e.turnNumber!==0)return!1;'
        eligB  = 'function Tba(e,t,n){return e.config.titleGeneration?.enabled===!1||!e.config.titleGeneration||!e.sessionStore||e.config.parentSessionId||e.config.taskType&&e.config.taskType!=="interactive"||n.trim().length===0?!1:Zye(t).length>0}'
    },
    @{
        tag    = '3.12.3'
        eligA  = 'function FYi(e,t,r={}){if(e.sessionTitleGenerationAttempted||e.config.titleGeneration?.enabled===!1||!e.config.titleGeneration||!e.sessionStore||e.config.parentSessionId||e.config.taskType&&e.config.taskType!=="interactive"||e.turnNumber!==0)return!1;'
        eligB  = 'function NYi(e,t,r){return e.config.titleGeneration?.enabled===!1||!e.config.titleGeneration||!e.sessionStore||e.config.parentSessionId||e.config.taskType&&e.config.taskType!=="interactive"||r.trim().length===0?!1:_J(t).length>0}'
    }
)
$oldLang = "- Use the user's primary language."

function Find-ZCodeDir {
    try {
        $p = Get-Process -Name 'ZCode' -ErrorAction SilentlyContinue | Where-Object Path | Select-Object -First 1
        if ($p) { return Split-Path (Split-Path $p.Path -Parent) -Parent }
    } catch {}
    $keys = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
              'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
              'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*')
    foreach ($k in $keys) {
        try {
            $hit = Get-ItemProperty $k -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like '*ZCode*' -and $_.InstallLocation } | Select-Object -First 1
            if ($hit) {
                $cand = Join-Path $hit.InstallLocation 'resources\glm\zcode.cjs'
                if (Test-Path $cand) { return (Split-Path $cand -Parent) }
            }
        } catch {}
    }
    $candidates = @('D:\installer\zcode', "$env:LOCALAPPDATA\Programs\zcode", "$env:ProgramFiles\zcode", "${env:ProgramFiles(x86)}\zcode")
    foreach ($d in $candidates) {
        try {
            if (-not (Test-Path $d)) { continue }
            $cand = Join-Path $d 'resources\glm\zcode.cjs'
            if (Test-Path $cand) { return (Split-Path $cand -Parent) }
        } catch { continue }
    }
    return $null
}

$glmDir = Find-ZCodeDir
if (-not $glmDir) {
    Write-Host '[?] Could not auto-locate ZCode. Example: D:\installer\zcode\resources\glm' -ForegroundColor Yellow
    $manual = Read-Host 'Enter the folder that contains zcode.cjs (resources\glm dir)'
    if (-not $manual -or -not (Test-Path (Join-Path $manual 'zcode.cjs'))) {
        Write-Host "[X] zcode.cjs not found under: $manual" -ForegroundColor Red
        Read-Host 'Press Enter to exit'
        exit 1
    }
    $glmDir = $manual
}
$cjsPath  = Join-Path $glmDir 'zcode.cjs'
$zcodeExe = Join-Path (Split-Path (Split-Path $cjsPath -Parent) -Parent) 'ZCode.exe'
if (-not (Test-Path $zcodeExe)) { $zcodeExe = $null }
Write-Host "target: $cjsPath"

$procs = Get-Process -Name 'ZCode' -ErrorAction SilentlyContinue
if ($procs) {
    Write-Host '[X] ZCode is running. Quit it from the tray icon first, then run this script again.' -ForegroundColor Red
    Read-Host 'Press Enter to exit'
    exit 1
}
if (-not (Test-Path $backupPath)) {
    Write-Host '[X] backup not found: ' $backupPath -ForegroundColor Red
    Write-Host '    (was the title patch ever applied on this machine? The backup is created by the patch script.)' -ForegroundColor Yellow
    Read-Host 'Press Enter to exit'
    exit 1
}

# sidecar hash must match the backup file itself
if (Test-Path $hashPath) {
    $expect = (Get-Content $hashPath -ErrorAction SilentlyContinue)
    $actual = (Get-FileHash $backupPath -Algorithm SHA256).Hash
    if (-not $expect -or ($actual -ne $expect.Trim())) {
        Write-Host '[X] backup hash mismatch with sidecar, refusing to overwrite.' -ForegroundColor Red
        Read-Host 'Press Enter to exit'
        exit 1
    }
}

# the backup must match a clean original of a KNOWN version (all fragments exactly once)
$latin1 = [System.Text.Encoding]::GetEncoding(28591)
$bt = $latin1.GetString([System.IO.File]::ReadAllBytes($backupPath))
$matched = $false
foreach ($v in $versions) {
    $ca = ([regex]::Matches($bt, [regex]::Escape($v.eligA))).Count
    $cb = ([regex]::Matches($bt, [regex]::Escape($v.eligB))).Count
    $cl = ([regex]::Matches($bt, [regex]::Escape($oldLang))).Count
    if ($ca -eq 1 -and $cb -eq 1 -and $cl -eq 1) {
        Write-Host "[OK] backup matches clean original of ZCode $($v.tag)."
        $matched = $true
        break
    }
}
if (-not $matched) {
    Write-Host '[X] backup does not match any known clean original zcode.cjs (looks patched or from an unsupported ZCode version), refusing to overwrite.' -ForegroundColor Red
    Read-Host 'Press Enter to exit'
    exit 1
}

Copy-Item $backupPath $cjsPath -Force
Write-Host '[OK] zcode.cjs restored.'
if ($zcodeExe) {
    Start-Process $zcodeExe
    Write-Host '[OK] ZCode restarted.'
} else {
    Write-Host '[OK] Start ZCode manually.'
}

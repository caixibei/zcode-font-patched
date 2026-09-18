# Revert ZCode session title patch (v2, portable): restore clean zcode.cjs from backup and restart
# Auto-locates ZCode install; every probe is fault-tolerant.
# Exits automatically on success; pauses only on errors.
$ErrorActionPreference = 'Stop'

$backupPath = Join-Path $PSScriptRoot 'zcode.cjs.title-backup'
$hashPath   = Join-Path $PSScriptRoot 'zcode.cjs.title-backup.sha256'

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

# the backup must be a clean unpatched zcode.cjs, never a patched one
$latin1 = [System.Text.Encoding]::GetEncoding(28591)
$oldFy = 'function FYi(e,t,r={}){if(e.sessionTitleGenerationAttempted||e.config.titleGeneration?.enabled===!1||!e.config.titleGeneration||!e.sessionStore||e.config.parentSessionId||e.config.taskType&&e.config.taskType!=="interactive"||e.turnNumber!==0)return!1;'
$oldNy = 'function NYi(e,t,r){return e.config.titleGeneration?.enabled===!1||!e.config.titleGeneration||!e.sessionStore||e.config.parentSessionId||e.config.taskType&&e.config.taskType!=="interactive"||r.trim().length===0?!1:_J(t).length>0}'
$oldLang = "- Use the user's primary language."
$bt = $latin1.GetString([System.IO.File]::ReadAllBytes($backupPath))
if (([regex]::Matches($bt, [regex]::Escape($oldFy))).Count -ne 1 -or ([regex]::Matches($bt, [regex]::Escape($oldNy))).Count -ne 1 -or ([regex]::Matches($bt, [regex]::Escape($oldLang))).Count -ne 1) {
    Write-Host '[X] backup is not a clean original zcode.cjs (looks patched or from a different ZCode version), refusing to overwrite.' -ForegroundColor Red
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

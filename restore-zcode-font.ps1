# Revert ZCode desktop UI font (v3, portable): restore app.asar from backup and restart
# Auto-locates ZCode install; every probe is fault-tolerant.
# Exits automatically on success; pauses only on errors.
$ErrorActionPreference = 'Stop'

$backupPath = Join-Path $PSScriptRoot 'app.asar.font-backup'
$hashPath   = Join-Path $PSScriptRoot 'app.asar.font-backup.sha256'

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
                $cand = Join-Path $hit.InstallLocation 'resources\app.asar'
                if (Test-Path $cand) { return (Split-Path $cand -Parent) }
            }
        } catch {}
    }
    $candidates = @('D:\installer\zcode', "$env:LOCALAPPDATA\Programs\zcode", "$env:ProgramFiles\zcode", "${env:ProgramFiles(x86)}\zcode")
    foreach ($d in $candidates) {
        try {
            if (-not (Test-Path $d)) { continue }
            $cand = Join-Path $d 'resources\app.asar'
            if (Test-Path $cand) { return (Split-Path $cand -Parent) }
        } catch { continue }
    }
    return $null
}

$resourcesDir = Find-ZCodeDir
if (-not $resourcesDir) {
    Write-Host '[?] Could not auto-locate ZCode. Example: D:\installer\zcode\resources' -ForegroundColor Yellow
    $manual = Read-Host 'Enter the folder that contains app.asar (resources dir)'
    if (-not $manual -or -not (Test-Path (Join-Path $manual 'app.asar'))) {
        Write-Host "[X] app.asar not found under: $manual" -ForegroundColor Red
        Read-Host 'Press Enter to exit'
        exit 1
    }
    $resourcesDir = $manual
}
$asarPath  = Join-Path $resourcesDir 'app.asar'
$zcodeExe  = Join-Path (Split-Path $resourcesDir -Parent) 'ZCode.exe'
if (-not (Test-Path $zcodeExe)) { $zcodeExe = $null }
Write-Host "target: $asarPath"

$procs = Get-Process -Name 'ZCode' -ErrorAction SilentlyContinue
if ($procs) {
    Write-Host '[X] ZCode is running. Quit it from the tray icon first, then run this script again.' -ForegroundColor Red
    Read-Host 'Press Enter to exit'
    exit 1
}
if (-not (Test-Path $backupPath)) {
    Write-Host '[X] backup not found: ' $backupPath -ForegroundColor Red
    Write-Host '    (was the patch ever applied on this machine? The backup is created by the patch script.)' -ForegroundColor Yellow
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

Copy-Item $backupPath $asarPath -Force
Write-Host '[OK] app.asar restored.'
if ($zcodeExe) {
    Start-Process $zcodeExe
    Write-Host '[OK] ZCode restarted.'
} else {
    Write-Host '[OK] Start ZCode manually.'
}

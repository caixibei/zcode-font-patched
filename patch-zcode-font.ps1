# ZCode desktop UI font patch (v3, portable)
# - Auto-locates ZCode install (running process / registry / common dirs / manual input);
#   every probe is fault-tolerant, a missing drive or path never aborts the search
# - Patches Tailwind root vars --font-sans / --font-mono inside app.asar:
#   English -> "Anthropic Mono Variable", CJK fallback -> "Noto Sans SC"
# - Equal-length byte replacement: asar header offsets/sizes stay intact
# - Backup = exact pre-patch state of THIS machine's app.asar; if the existing
#   backup does not match (kit copied from another machine, or ZCode updated),
#   it is silently re-created before patching
# - Exits automatically on success; pauses only on errors
# Revert with restore-zcode-font.bat
$ErrorActionPreference = 'Stop'
$latin1 = [System.Text.Encoding]::GetEncoding(28591)  # lossless byte<->char round-trip

$backupPath = Join-Path $PSScriptRoot 'app.asar.font-backup'
$hashPath   = Join-Path $PSScriptRoot 'app.asar.font-backup.sha256'

# ---- exact strings present in current ZCode builds (each must occur exactly once) ----
$oldSans = '--font-sans:ui-sans-serif, system-ui, sans-serif, "Apple Color Emoji", "Segoe UI Emoji", "Segoe UI Symbol", "Noto Color Emoji";'
$oldMono = '--font-mono:ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", "Microsoft YaHei UI", "Microsoft YaHei", "PingFang SC", "Noto Sans CJK SC", monospace;'

# ---- patched strings: Anthropic Mono first, Noto Sans SC as CJK fallback ----
$newSans = '--font-sans:"Anthropic Mono Variable", "Noto Sans SC", "Segoe UI Emoji", "Noto Color Emoji";'
$newMono = '--font-mono:"Anthropic Mono Variable", "Noto Sans SC", "Segoe UI Emoji", "Noto Color Emoji";'

function Pad-To([string]$old, [string]$new) {
    if ($new.Length -gt $old.Length) { throw "new string longer than old, cannot pad: $($new.Length) > $($old.Length)" }
    $pad = $old.Length - $new.Length
    if ($pad -eq 0) { return $new }
    return $new.Substring(0, $new.Length - 1) + (' ' * $pad) + ';'
}
$newSans = Pad-To $oldSans $newSans
$newMono = Pad-To $oldMono $newMono

# ---- v1 patch strings (previous kit version, English-only change) ----
# v1 wrote these padded to equal length the same way, so reproduce that exactly
$v1Sans = Pad-To $oldSans '--font-sans:"Anthropic Mono Variable", system-ui, "Apple Color Emoji", "Segoe UI Emoji", "Segoe UI Symbol", "Noto Color Emoji";'
$v1Mono = Pad-To $oldMono '--font-mono:"Anthropic Mono Variable", Consolas, "Liberation Mono", "Courier New", "Microsoft YaHei UI", "Microsoft YaHei", "PingFang SC", "Noto Sans CJK SC", monospace;'

function Find-ZCodeDir {
    # 1) running process path
    try {
        $p = Get-Process -Name 'ZCode' -ErrorAction SilentlyContinue | Where-Object Path | Select-Object -First 1
        if ($p) { return Split-Path (Split-Path $p.Path -Parent) -Parent }
    } catch {}
    # 2) registry uninstall entries (32/64-bit + per-user)
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
    # 3) common dirs; Join-Path with an absent drive throws, so test the drive first
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

# 0) ZCode must not be running
$procs = Get-Process -Name 'ZCode' -ErrorAction SilentlyContinue
if ($procs) {
    Write-Host '[X] ZCode is running, app.asar is locked.' -ForegroundColor Red
    Write-Host '    Quit ZCode first (right-click tray icon -> Quit; clicking X may only minimize to tray).' -ForegroundColor Yellow
    Read-Host 'Press Enter to exit'
    exit 1
}

# 1) read asar first (need it both for backup and assertions)
$bytes = [System.IO.File]::ReadAllBytes($asarPath)
$text  = $latin1.GetString($bytes)
$asarHash = (Get-FileHash $asarPath -Algorithm SHA256).Hash

# 2) backup policy: backup must always equal the CURRENT pre-patch asar of this machine
$needNewBackup = $true
if ((Test-Path $backupPath) -and (Test-Path $hashPath)) {
    $expect = (Get-Content $hashPath -ErrorAction SilentlyContinue)
    $actual = (Get-FileHash $backupPath -Algorithm SHA256).Hash
    if ($expect -and ($actual -eq $expect.Trim()) -and ($actual -eq $asarHash)) {
        $needNewBackup = $false
        Write-Host '[1/4] backup matches current app.asar'
    } elseif ($actual -eq $asarHash) {
        $needNewBackup = $false
        [System.IO.File]::WriteAllText($hashPath, $actual)
        Write-Host '[1/4] backup matches current app.asar (sidecar refreshed)'
    }
}
if ($needNewBackup) {
    Copy-Item $asarPath $backupPath -Force
    [System.IO.File]::WriteAllText($hashPath, $asarHash)
    Write-Host '[1/4] backup (re)created from current app.asar'
}

# 3) state detection: unpatched / v1-patched (upgrade to v2) / v2-patched (idempotent)
$cOldSans = ([regex]::Matches($text, [regex]::Escape($oldSans))).Count
$cOldMono = ([regex]::Matches($text, [regex]::Escape($oldMono))).Count
$cV1Sans  = ([regex]::Matches($text, [regex]::Escape($v1Sans))).Count
$cV1Mono  = ([regex]::Matches($text, [regex]::Escape($v1Mono))).Count
$cNewSans = ([regex]::Matches($text, [regex]::Escape($newSans.TrimEnd().TrimEnd(';')))).Count
if ($cOldSans -eq 1 -and $cOldMono -eq 1) {
    Write-Host '[2/4] state: unpatched, applying patch'
} elseif ($cV1Sans -eq 1 -and $cV1Mono -eq 1) {
    Write-Host '[2/4] state: v1 patch detected, upgrading to v2 (restore backup first)'
    $bytes = [System.IO.File]::ReadAllBytes($backupPath)
    $text  = $latin1.GetString($bytes)
    if (([regex]::Matches($text, [regex]::Escape($oldSans))).Count -ne 1 -or ([regex]::Matches($text, [regex]::Escape($oldMono))).Count -ne 1) {
        throw 'v1 detected but backup is not a clean original, refusing.'
    }
} elseif ($cNewSans -ge 1 -and $cOldSans -eq 0 -and $cV1Sans -eq 0) {
    Write-Host '[2/4] state: already v2 patched, nothing to do'
    if ($zcodeExe) { Start-Process $zcodeExe }
    exit 0
} else {
    throw "unknown asar state (oldSans=$cOldSans oldMono=$cOldMono v1Sans=$cV1Sans v1Mono=$cV1Mono). Version changed? Refusing."
}

# 4) equal-length replace + verify
$patched  = $text.Replace($oldSans, $newSans).Replace($oldMono, $newMono)
$newBytes = $latin1.GetBytes($patched)
if ($newBytes.Length -ne $bytes.Length) { throw "length changed: $($bytes.Length) -> $($newBytes.Length), refusing to write." }
if (([regex]::Matches($patched, [regex]::Escape($oldSans))).Count -ne 0) { throw 'old sans still present after replace.' }
[System.IO.File]::WriteAllBytes($asarPath, $newBytes)
Write-Host '[3/4] patch written (equal-length, size unchanged)'

if ($zcodeExe) {
    Start-Process $zcodeExe
    Write-Host '[4/4] ZCode restarted. English: Anthropic Mono Variable, CJK: Noto Sans SC.'
} else {
    Write-Host '[4/4] done. Start ZCode manually. English: Anthropic Mono Variable, CJK: Noto Sans SC.'
}

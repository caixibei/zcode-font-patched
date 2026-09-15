# ZCode desktop UI font patch (v3, portable)
# - Auto-locates ZCode install (running process / registry / common dirs / manual input);
#   every probe is fault-tolerant, a missing drive or path never aborts the search
# - Patches Tailwind root vars --font-sans / --font-mono inside app.asar with the
#   user-specified priority stack (first installed family wins, CJK falls through):
#   "Anthropic Mono Variable" -> "MiSans" -> "HarmonyOS Sans SC"
#   -> "Source Han Sans SC" -> "Noto Sans SC" -> "HarmonyOS Sans"
#   (emoji fonts omitted: Chromium still renders emoji via its own system fallback)
# - Equal-length byte replacement: asar header offsets/sizes stay intact
# - Backup = clean original asar of THIS machine; state is detected BEFORE any
#   backup decision, so an existing clean backup is never overwritten by a
#   patched asar; a missing/invalid backup is self-healed by reverse replacement
# - Upgrades v1/v2 patch layouts in place; idempotent when already v3
# - Exits automatically on success; pauses only on errors
# Revert with restore-zcode-font.bat
$ErrorActionPreference = 'Stop'
$latin1 = [System.Text.Encoding]::GetEncoding(28591)  # lossless byte<->char round-trip

$backupPath = Join-Path $PSScriptRoot 'app.asar.font-backup'
$hashPath   = Join-Path $PSScriptRoot 'app.asar.font-backup.sha256'

# ---- exact strings present in current ZCode builds (each must occur exactly once) ----
$oldSans = '--font-sans:ui-sans-serif, system-ui, sans-serif, "Apple Color Emoji", "Segoe UI Emoji", "Segoe UI Symbol", "Noto Color Emoji";'
$oldMono = '--font-mono:ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", "Microsoft YaHei UI", "Microsoft YaHei", "PingFang SC", "Noto Sans CJK SC", monospace;'

# ---- patched strings (v4): separate stacks per variable, user-specified priority ----
# sans: LXGW WenKai (handwriting-flavored CJK) -> HarmonyOS Sans SC -> Source Han Sans SC
#       -> Noto Sans SC -> HarmonyOS Sans -> MiSans
# mono: Anthropic Mono Variable (latin) -> LXGW WenKai (CJK) -> JetBrains Mono
$newSans = '--font-sans:"LXGW WenKai", "HarmonyOS Sans SC", "Source Han Sans SC", "Noto Sans SC", "HarmonyOS Sans", "MiSans";'
$newMono = '--font-mono:"Anthropic Mono Variable", "LXGW WenKai", "JetBrains Mono";'

# ---- v3 patch strings (previous kit version, single stack for both variables) ----
$v3Sans = '--font-sans:"Anthropic Mono Variable", "MiSans", "HarmonyOS Sans SC", "Source Han Sans SC", "Noto Sans SC", "HarmonyOS Sans";'
$v3Mono = '--font-mono:"Anthropic Mono Variable", "MiSans", "HarmonyOS Sans SC", "Source Han Sans SC", "Noto Sans SC", "HarmonyOS Sans";'

function Pad-To([string]$old, [string]$new) {
    if ($new.Length -gt $old.Length) { throw "new string longer than old, cannot pad: $($new.Length) > $($old.Length)" }
    $pad = $old.Length - $new.Length
    if ($pad -eq 0) { return $new }
    return $new.Substring(0, $new.Length - 1) + (' ' * $pad) + ';'
}
$newSans = Pad-To $oldSans $newSans
$newMono = Pad-To $oldMono $newMono

# ---- legacy patch strings (v1 / v2 kit versions), padded exactly as they were written ----
$v1Sans = Pad-To $oldSans '--font-sans:"Anthropic Mono Variable", system-ui, "Apple Color Emoji", "Segoe UI Emoji", "Segoe UI Symbol", "Noto Color Emoji";'
$v1Mono = Pad-To $oldMono '--font-mono:"Anthropic Mono Variable", Consolas, "Liberation Mono", "Courier New", "Microsoft YaHei UI", "Microsoft YaHei", "PingFang SC", "Noto Sans CJK SC", monospace;'
$v2Sans = Pad-To $oldSans '--font-sans:"Anthropic Mono Variable", "Noto Sans SC", "Segoe UI Emoji", "Noto Color Emoji";'
$v2Mono = Pad-To $oldMono '--font-mono:"Anthropic Mono Variable", "Noto Sans SC", "Segoe UI Emoji", "Noto Color Emoji";'
$v3Sans = Pad-To $oldSans $v3Sans
$v3Mono = Pad-To $oldMono $v3Mono

function Count-Str([string]$hay, [string]$s) {
    return ([regex]::Matches($hay, [regex]::Escape($s))).Count
}
function Hash-Bytes([byte[]]$b) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return (($sha.ComputeHash($b) | ForEach-Object { $_.ToString('X2') }) -join '') } finally { $sha.Dispose() }
}

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
    # 3) common dirs; Join-Path with an absent drive throws, so test the path first
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

# 1) read current asar and detect its state BEFORE touching any backup
$bytes    = [System.IO.File]::ReadAllBytes($asarPath)
$text     = $latin1.GetString($bytes)
$asarHash = Hash-Bytes $bytes

$cOldSans = Count-Str $text $oldSans
$cOldMono = Count-Str $text $oldMono
$cV1Sans  = Count-Str $text $v1Sans
$cV1Mono  = Count-Str $text $v1Mono
$cV2Sans  = Count-Str $text $v2Sans
$cV2Mono  = Count-Str $text $v2Mono
$cV3Sans  = Count-Str $text ($v3Sans.TrimEnd(';').TrimEnd())
$cV3Mono  = Count-Str $text ($v3Mono.TrimEnd(';').TrimEnd())
$cNewSans = Count-Str $text ($newSans.TrimEnd(';').TrimEnd())
$cNewMono = Count-Str $text ($newMono.TrimEnd(';').TrimEnd())

$isUnpatched = ($cOldSans -eq 1 -and $cOldMono -eq 1)
$isV1        = ($cV1Sans -eq 1 -and $cV1Mono -eq 1)
$isV2        = ($cV2Sans -eq 1 -and $cV2Mono -eq 1)
$isV3        = ($cV3Sans -ge 1 -and $cV3Mono -ge 1 -and $cNewSans -eq 0)
$isV4        = ($cNewSans -ge 1 -and $cNewMono -ge 1)

# 2) determine the clean baseline asar (what the backup must contain)
$baseText = $null
if ($isUnpatched) {
    Write-Host '[1/4] state: unpatched'
    $baseText = $text
} elseif ($isV1 -or $isV2 -or $isV3 -or $isV4) {
    if ($isV1) { Write-Host '[1/4] state: v1 patch detected (upgrade)' }
    elseif ($isV2) { Write-Host '[1/4] state: v2 patch detected (upgrade)' }
    elseif ($isV3) { Write-Host '[1/4] state: v3 patch detected (upgrade)' }
    else { Write-Host '[1/4] state: v4 patch detected' }
    # baseline = existing backup if it verifies as a clean original...
    if (Test-Path $backupPath) {
        $sidecarOk = $false
        if (Test-Path $hashPath) {
            $expect = (Get-Content $hashPath -ErrorAction SilentlyContinue)
            $actual = (Get-FileHash $backupPath -Algorithm SHA256).Hash
            $sidecarOk = ($expect -and ($actual -eq $expect.Trim()))
        }
        if ($sidecarOk) {
            $bt = $latin1.GetString([System.IO.File]::ReadAllBytes($backupPath))
            if ((Count-Str $bt $oldSans) -eq 1 -and (Count-Str $bt $oldMono) -eq 1) {
                $baseText = $bt
                Write-Host '[2/4] clean backup verified'
            }
        }
    }
    # ...otherwise self-heal: reverse the known patch strings to rebuild the clean original
    if (-not $baseText) {
        $rt = $text
        foreach ($pair in @(($v1Sans, $oldSans), ($v1Mono, $oldMono), ($v2Sans, $oldSans), ($v2Mono, $oldMono), ($v3Sans, $oldSans), ($v3Mono, $oldMono), ($newSans, $oldSans), ($newMono, $oldMono))) {
            $rt = $rt.Replace($pair[0], $pair[1])
        }
        if ((Count-Str $rt $oldSans) -ne 1 -or (Count-Str $rt $oldMono) -ne 1) {
            throw 'clean backup missing/invalid and cannot be reconstructed from the patched asar; refusing.'
        }
        $baseText = $rt
        Write-Host '[2/4] clean backup missing/invalid, reconstructed from patched asar'
    }
} else {
    throw "unknown asar state (oldSans=$cOldSans oldMono=$cOldMono v1Sans=$cV1Sans v1Mono=$cV1Mono v2Sans=$cV2Sans v2Mono=$cV2Mono v3Sans=$cV3Sans v3Mono=$cV3Mono v4Sans=$cNewSans v4Mono=$cNewMono). Version changed? Refusing."
}
$baseBytes = $latin1.GetBytes($baseText)
$baseHash  = Hash-Bytes $baseBytes

# 3) make the backup equal the clean baseline (never the patched state)
$needBackupWrite = $true
if (Test-Path $backupPath) {
    if ((Get-FileHash $backupPath -Algorithm SHA256).Hash -eq $baseHash) {
        $needBackupWrite = $false
    }
}
if ($needBackupWrite) {
    [System.IO.File]::WriteAllBytes($backupPath, $baseBytes)
    [System.IO.File]::WriteAllText($hashPath, $baseHash)
    Write-Host '[2/4] backup (re)created from clean baseline'
} elseif (-not (Test-Path $hashPath) -or (Get-Content $hashPath -ErrorAction SilentlyContinue).Trim() -ne $baseHash) {
    [System.IO.File]::WriteAllText($hashPath, $baseHash)
    Write-Host '[2/4] backup verified (sidecar refreshed)'
}

# 4) apply v3 stack onto the baseline and write only if content changes
$patched  = $baseText.Replace($oldSans, $newSans).Replace($oldMono, $newMono)
$newBytes = $latin1.GetBytes($patched)
if ($newBytes.Length -ne $baseBytes.Length) { throw "length changed: $($baseBytes.Length) -> $($newBytes.Length), refusing to write." }
if ((Count-Str $patched $oldSans) -ne 0) { throw 'old sans still present after replace.' }
if ((Count-Str $patched ($newSans.TrimEnd(';').TrimEnd())) -lt 1) { throw 'new sans missing after replace.' }

if ((Hash-Bytes $newBytes) -eq $asarHash) {
    Write-Host '[3/4] asar already carries the v4 stacks, nothing to write'
} else {
    [System.IO.File]::WriteAllBytes($asarPath, $newBytes)
    Write-Host '[3/4] patch written (equal-length, size unchanged)'
}

if ($zcodeExe) {
    Start-Process $zcodeExe
    Write-Host '[4/4] ZCode restarted.'
} else {
    Write-Host '[4/4] done. Start ZCode manually.'
}
Write-Host '--font-sans: "LXGW WenKai" -> "HarmonyOS Sans SC" -> "Source Han Sans SC" -> "Noto Sans SC" -> "HarmonyOS Sans" -> "MiSans".'
Write-Host '--font-mono: "Anthropic Mono Variable" -> "LXGW WenKai" -> "JetBrains Mono".'

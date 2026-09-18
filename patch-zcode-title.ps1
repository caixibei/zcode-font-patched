# ZCode session title patch (v1, portable) - restore auto title generation on 3.12.3
# - Targets resources\glm\zcode.cjs (agent CLI runtime), NOT app.asar
# - 3.12.3 regression: eligibility check requires truthy config.titleGeneration, but the
#   desktop host passes {} and an upstream merge can leave it undefined -> FYi/NYi bail
#   out silently and no session_title model request is ever issued
# - Patch removes the "||!e.config.titleGeneration" clause from BOTH eligibility functions
#   (FYi / NYi) using an equal-length /*...*/ filler: byte length stays identical
# - Equal-length byte replacement: file size unchanged, no repackage needed
# - Backup = clean original zcode.cjs of THIS machine; an existing verified backup is
#   never overwritten; missing backup is self-healed by reverse replacement
# - Idempotent; refuses when the target string does not match (version drift guard)
# Revert with restore-zcode-title.bat
$ErrorActionPreference = 'Stop'
$latin1 = [System.Text.Encoding]::GetEncoding(28591)  # lossless byte<->char round-trip

$backupPath = Join-Path $PSScriptRoot 'zcode.cjs.title-backup'
$hashPath   = Join-Path $PSScriptRoot 'zcode.cjs.title-backup.sha256'

# ---- exact original fragments inside zcode.cjs 3.12.3 (each must occur exactly once) ----
# FYi = shouldAttemptSessionTitleGeneration (session title eligibility)
$oldFy = 'function FYi(e,t,r={}){if(e.sessionTitleGenerationAttempted||e.config.titleGeneration?.enabled===!1||!e.config.titleGeneration||!e.sessionStore||e.config.parentSessionId||e.config.taskType&&e.config.taskType!=="interactive"||e.turnNumber!==0)return!1;'
# NYi = shouldAttemptGoalSummaryTitleGeneration (goal summary title eligibility)
$oldNy = 'function NYi(e,t,r){return e.config.titleGeneration?.enabled===!1||!e.config.titleGeneration||!e.sessionStore||e.config.parentSessionId||e.config.taskType&&e.config.taskType!=="interactive"||r.trim().length===0?!1:_J(t).length>0}'

# ---- patched forms: drop "||!e.config.titleGeneration" (27 chars), pad with a 27-char /*...*/ comment ----
$filler = '/*' + ('x' * 23) + '*/'   # 2+23+2 = 27 chars, JS comment -> no runtime effect
$newFy = $oldFy.Replace('||!e.config.titleGeneration', '').Replace('{if(', '{' + $filler + 'if(')
$newNy = $oldNy.Replace('||!e.config.titleGeneration', '').Replace('{return ', '{' + $filler + 'return ')
if ($newFy.Length -ne $oldFy.Length) { throw 'FYi patch length mismatch, aborting.' }
if ($newNy.Length -ne $oldNy.Length) { throw 'NYi patch length mismatch, aborting.' }

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
                $cand = Join-Path $hit.InstallLocation 'resources\glm\zcode.cjs'
                if (Test-Path $cand) { return (Split-Path $cand -Parent) }
            }
        } catch {}
    }
    # 3) common dirs
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

# 0) ZCode must not be running (zcode.cjs is memory-mapped/locked by worker processes)
$procs = Get-Process -Name 'ZCode' -ErrorAction SilentlyContinue
if ($procs) {
    Write-Host '[X] ZCode is running, zcode.cjs is locked.' -ForegroundColor Red
    Write-Host '    Quit ZCode first (right-click tray icon -> Quit; clicking X may only minimize to tray).' -ForegroundColor Yellow
    Read-Host 'Press Enter to exit'
    exit 1
}

# 1) read current file and detect its state BEFORE touching any backup
$bytes    = [System.IO.File]::ReadAllBytes($cjsPath)
$text     = $latin1.GetString($bytes)
$cjsHash  = Hash-Bytes $bytes

$cOldFy  = Count-Str $text $oldFy
$cOldNy  = Count-Str $text $oldNy
$cNewFy  = Count-Str $text $newFy
$cNewNy  = Count-Str $text $newNy

$isUnpatched = ($cOldFy -eq 1 -and $cOldNy -eq 1)
$isPatched   = ($cNewFy -eq 1 -and $cNewNy -eq 1)

# 2) determine the clean baseline (what the backup must contain)
$baseText = $null
if ($isUnpatched) {
    Write-Host '[1/4] state: unpatched (3.12.3 original)'
    $baseText = $text
} elseif ($isPatched) {
    Write-Host '[1/4] state: title patch already applied'
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
            if ((Count-Str $bt $oldFy) -eq 1 -and (Count-Str $bt $oldNy) -eq 1) {
                $baseText = $bt
                Write-Host '[2/4] clean backup verified'
            }
        }
    }
    # ...otherwise self-heal: reverse the patch to rebuild the clean original
    if (-not $baseText) {
        $rt = $text.Replace($newFy, $oldFy).Replace($newNy, $oldNy)
        if ((Count-Str $rt $oldFy) -ne 1 -or (Count-Str $rt $oldNy) -ne 1) {
            throw 'clean backup missing/invalid and cannot be reconstructed from the patched file; refusing.'
        }
        $baseText = $rt
        Write-Host '[2/4] clean backup missing/invalid, reconstructed from patched file'
    }
} else {
    throw "unknown zcode.cjs state (oldFy=$cOldFy oldNy=$cOldNy newFy=$cNewFy newNy=$cNewNy). ZCode version changed? Refusing."
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

# 4) apply the patch onto the baseline and write only if content changes
$patched  = $baseText.Replace($oldFy, $newFy).Replace($oldNy, $newNy)
$newBytes = $latin1.GetBytes($patched)
if ($newBytes.Length -ne $baseBytes.Length) { throw "length changed: $($baseBytes.Length) -> $($newBytes.Length), refusing to write." }
if ((Count-Str $patched $oldFy) -ne 0 -or (Count-Str $patched $oldNy) -ne 0) { throw 'old fragment still present after replace.' }
if ((Count-Str $patched $newFy) -ne 1 -or (Count-Str $patched $newNy) -ne 1) { throw 'new fragment missing after replace.' }

if ((Hash-Bytes $newBytes) -eq $cjsHash) {
    Write-Host '[3/4] zcode.cjs already carries the title patch, nothing to write'
} else {
    [System.IO.File]::WriteAllBytes($cjsPath, $newBytes)
    Write-Host '[3/4] patch written (equal-length, size unchanged)'
}

if ($zcodeExe) {
    Start-Process $zcodeExe
    Write-Host '[4/4] ZCode restarted.'
} else {
    Write-Host '[4/4] done. Start ZCode manually.'
}
Write-Host 'Auto session title generation is restored: new interactive sessions will issue a session_title model request again.'

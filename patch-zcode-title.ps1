# ZCode session title patch (v2, portable) - restore auto title generation on 3.12.3
# - Targets resources\glm\zcode.cjs (agent CLI runtime), NOT app.asar
# - Fix 1 (3.12.3 regression): eligibility check requires truthy config.titleGeneration,
#   but the desktop host passes {} and an upstream merge can leave it undefined ->
#   FYi/NYi bail out silently and no session_title model request is ever issued.
#   Patch removes the "||!e.config.titleGeneration" clause from BOTH eligibility
#   functions (FYi / NYi) using an equal-length /*...*/ filler.
# - Fix 2 (weak language rule): the title prompt rule "- Use the user's primary
#   language." is too weak for some models (e.g. minimax-m3 answered an all-Chinese
#   input with an English title). Strengthened to "- MUST use the user's primary
#   language." (+5 bytes). zcode.cjs is a standalone file (NOT inside the asar
#   archive), so a small size change is safe: no offsets or headers depend on it.
# - Backup = clean original zcode.cjs of THIS machine; an existing verified backup is
#   never overwritten; missing backup is self-healed by reverse replacement
# - Upgrades v1 in place; idempotent when already v2
# - Exits automatically on success; pauses only on errors
# Revert with restore-zcode-title.bat
$ErrorActionPreference = 'Stop'
$latin1 = [System.Text.Encoding]::GetEncoding(28591)  # lossless byte<->char round-trip (all patch strings are pure ASCII)

$backupPath = Join-Path $PSScriptRoot 'zcode.cjs.title-backup'
$hashPath   = Join-Path $PSScriptRoot 'zcode.cjs.title-backup.sha256'

# ---- exact original fragments inside zcode.cjs 3.12.3 (each must occur exactly once) ----
# FYi = shouldAttemptSessionTitleGeneration (session title eligibility)
$oldFy = 'function FYi(e,t,r={}){if(e.sessionTitleGenerationAttempted||e.config.titleGeneration?.enabled===!1||!e.config.titleGeneration||!e.sessionStore||e.config.parentSessionId||e.config.taskType&&e.config.taskType!=="interactive"||e.turnNumber!==0)return!1;'
# NYi = shouldAttemptGoalSummaryTitleGeneration (goal summary title eligibility)
$oldNy = 'function NYi(e,t,r){return e.config.titleGeneration?.enabled===!1||!e.config.titleGeneration||!e.sessionStore||e.config.parentSessionId||e.config.taskType&&e.config.taskType!=="interactive"||r.trim().length===0?!1:_J(t).length>0}'
# title prompt language rule (too weak: some models output English titles for Chinese input)
$oldLang = "- Use the user's primary language."

# ---- patched forms ----
# FYi/NYi: drop "||!e.config.titleGeneration" (27 chars), pad with a 27-char /*...*/ comment
$filler = '/*' + ('x' * 23) + '*/'   # 2+23+2 = 27 chars, JS comment -> no runtime effect
$newFy = $oldFy.Replace('||!e.config.titleGeneration', '').Replace('{if(', '{' + $filler + 'if(')
$newNy = $oldNy.Replace('||!e.config.titleGeneration', '').Replace('{return ', '{' + $filler + 'return ')
# language rule: strengthen with MUST (+5 bytes, safe: standalone file, no offsets)
$newLang = "- MUST use the user's primary language."
if ($newFy.Length -ne $oldFy.Length) { throw 'FYi patch length mismatch, aborting.' }
if ($newNy.Length -ne $oldNy.Length) { throw 'NYi patch length mismatch, aborting.' }
$langDelta = $newLang.Length - $oldLang.Length   # expected +5

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

$cOldFy   = Count-Str $text $oldFy
$cOldNy   = Count-Str $text $oldNy
$cNewFy   = Count-Str $text $newFy
$cNewNy   = Count-Str $text $newNy
$cOldLang = Count-Str $text $oldLang
$cNewLang = Count-Str $text $newLang

$isFyNyClean   = ($cOldFy -eq 1 -and $cOldNy -eq 1)
$isFyNyPatched = ($cNewFy -eq 1 -and $cNewNy -eq 1)
$isLangClean   = ($cOldLang -eq 1)
$isLangPatched = ($cNewLang -eq 1)

$isUnpatched = ($isFyNyClean   -and $isLangClean)
$isV2        = ($isFyNyPatched -and $isLangPatched)
$isV1        = ($isFyNyPatched -and $isLangClean)   # v1: FYi/NYi done, language rule pending
$isLangOnly  = ($isFyNyClean   -and $isLangPatched)  # unexpected mixed state

function Get-CleanBaseline {
    # baseline = existing backup if it verifies as a clean original (all three fragments exactly once)...
    if (Test-Path $backupPath) {
        $sidecarOk = $false
        if (Test-Path $hashPath) {
            $expect = (Get-Content $hashPath -ErrorAction SilentlyContinue)
            $actual = (Get-FileHash $backupPath -Algorithm SHA256).Hash
            $sidecarOk = ($expect -and ($actual -eq $expect.Trim()))
        }
        if ($sidecarOk) {
            $bt = $latin1.GetString([System.IO.File]::ReadAllBytes($backupPath))
            if ((Count-Str $bt $oldFy) -eq 1 -and (Count-Str $bt $oldNy) -eq 1 -and (Count-Str $bt $oldLang) -eq 1) {
                Write-Host '[2/4] clean backup verified'
                return $bt
            }
        }
    }
    # ...otherwise self-heal: reverse the patch to rebuild the clean original
    $rt = $text.Replace($newFy, $oldFy).Replace($newNy, $oldNy).Replace($newLang, $oldLang)
    if ((Count-Str $rt $oldFy) -ne 1 -or (Count-Str $rt $oldNy) -ne 1 -or (Count-Str $rt $oldLang) -ne 1) {
        throw 'clean backup missing/invalid and cannot be reconstructed from the patched file; refusing.'
    }
    Write-Host '[2/4] clean backup missing/invalid, reconstructed from patched file'
    return $rt
}

# 2) determine the clean baseline (what the backup must contain: all three original fragments)
$baseText = $null
if ($isUnpatched) {
    Write-Host '[1/4] state: unpatched (3.12.3 original)'
    $baseText = $text
} elseif ($isV2) {
    Write-Host '[1/4] state: title patch v2 already applied'
    $baseText = Get-CleanBaseline
} elseif ($isV1) {
    Write-Host '[1/4] state: v1 title patch detected (upgrading: strengthening language rule)'
    $baseText = Get-CleanBaseline
} elseif ($isLangOnly) {
    throw 'unexpected state: language rule patched but FYi/NYi clean; run restore-zcode-title.bat first.'
} else {
    throw "unknown zcode.cjs state (oldFy=$cOldFy oldNy=$cOldNy newFy=$cNewFy newNy=$cNewNy oldLang=$cOldLang newLang=$cNewLang). ZCode version changed? Refusing."
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
$patched  = $baseText.Replace($oldFy, $newFy).Replace($oldNy, $newNy).Replace($oldLang, $newLang)
$newBytes = $latin1.GetBytes($patched)
# FYi/NYi are equal-length swaps; the language rule adds exactly $langDelta bytes
$expectedLen = $baseBytes.Length + $langDelta
if ($newBytes.Length -ne $expectedLen) { throw "unexpected length: $($baseBytes.Length) -> $($newBytes.Length) (expected $expectedLen), refusing to write." }
if ((Count-Str $patched $oldFy) -ne 0 -or (Count-Str $patched $oldNy) -ne 0 -or (Count-Str $patched $oldLang) -ne 0) { throw 'old fragment still present after replace.' }
if ((Count-Str $patched $newFy) -ne 1 -or (Count-Str $patched $newNy) -ne 1 -or (Count-Str $patched $newLang) -ne 1) { throw 'new fragment missing after replace.' }

if ((Hash-Bytes $newBytes) -eq $cjsHash) {
    Write-Host '[3/4] zcode.cjs already carries the title patch v2, nothing to write'
} else {
    [System.IO.File]::WriteAllBytes($cjsPath, $newBytes)
    Write-Host "[3/4] patch written (FYi/NYi equal-length; language rule +$langDelta bytes; standalone file, size change is safe)"
}

if ($zcodeExe) {
    Start-Process $zcodeExe
    Write-Host '[4/4] ZCode restarted.'
} else {
    Write-Host '[4/4] done. Start ZCode manually.'
}
Write-Host 'Auto session title generation is restored; titles now MUST follow the user primary language.'

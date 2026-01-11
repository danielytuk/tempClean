<#
.SYNOPSIS
  Cleans up temporary and cache files (Windows + browsers/Electron + Firefox forks).

.DESCRIPTION
  Goal: free disk space by removing old, unimportant files (temp/cache/logs/crash dumps).

  - Windows/user temp (2+ days)
  - Windows Update cache (SoftwareDistribution\Download, 7+ days)
  - Memory dumps & crash dumps (7+ days)
  - Windows Error Reporting (WER) archives/queue (7+ days)
  - Legacy Edge/IE INetCache (2+ days)
  - Generic cache dirs via wildcards under AppData (2+ days), e.g.:
      *\*\Cache*
      *\*\Code Cache*
      *\*\GPUCache*
  - Generic temp/log dirs via wildcards under AppData (2+ days), e.g.:
      *\Temp
      *\tmp
      *\Logs
  - Firefox & Firefox forks (Gecko-based) profile caches (2+ days)
      Profiles\*\cache2\entries, Profiles\*\cache2, Profiles\*\cache

  Only files are removed, never entire directories wholesale.
  All deletions are age-limited: nothing newer than 2 days is touched.

.PARAMETER del
  Run silently (no confirmation) and delete files directly.

.EXAMPLE
  .\Clean-TempAndCache.ps1
  # Dry-run first, then prompt to delete

.EXAMPLE
  .\Clean-TempAndCache.ps1 -del
  # Silent delete, no prompt
#>

[CmdletBinding()]
param(
    [switch]$del
)

Write-Host "=== Temp & Cache Cleanup Script ===" -ForegroundColor Cyan
Write-Host "Started at $(Get-Date)" -ForegroundColor Cyan

# ---------------- Utility functions ----------------

function Format-Bytes {
    param([long]$Bytes)
    if     ($Bytes -ge 1GB) { return "{0:N2} GB" -f ($Bytes / 1GB) }
    elseif ($Bytes -ge 1MB) { return "{0:N2} MB" -f ($Bytes / 1MB) }
    elseif ($Bytes -ge 1KB) { return "{0:N2} KB" -f ($Bytes / 1KB) }
    else                    { return "$Bytes B" }
}

function Collect-OldFilesFromRoots {
    param(
        [string[]]$Roots,
        [int]$Days,
        [string]$Description
    )

    $cutoff    = (Get-Date).AddDays(-$Days)
    $collected = @()

    foreach ($root in $Roots) {
        if (-not $root -or -not (Test-Path -LiteralPath $root)) { continue }

        try {
            # Single recursive scan per root; files only (better perf, safer)
            $files = Get-ChildItem -LiteralPath $root -Recurse -File -Force -ErrorAction SilentlyContinue |
                     Where-Object { $_.LastWriteTime -lt $cutoff }
        } catch {
            continue
        }

        if ($files -and $files.Count -gt 0) {
            $bytes = ($files | Measure-Object Length -Sum).Sum
            Write-Host "$Description in '$root': $($files.Count) files, $(Format-Bytes $bytes)" -ForegroundColor Green
            $collected += $files
        } else {
            Write-Host "$Description in '$root': nothing to clean." -ForegroundColor DarkGray
        }
    }

    return $collected
}

function Collect-OldFilesFromPatterns {
    param(
        [string[]]$Patterns,
        [int]$Days,
        [string]$Description
    )

    $cutoff    = (Get-Date).AddDays(-$Days)
    $collected = @()
    $dirs      = @()

    # Resolve wildcard patterns to concrete directories
    foreach ($pattern in $Patterns) {
        if (-not $pattern) { continue }
        try {
            $dirs += Get-ChildItem -Path $pattern -Directory -Force -ErrorAction SilentlyContinue
        } catch {
            # ignore invalid patterns / access issues
        }
    }

    if (-not $dirs) { return $collected }

    # Deduplicate directories by path
    $dirs = $dirs | Sort-Object FullName -Unique

    # For each resolved directory, recursively scan old files
    foreach ($dir in $dirs) {
        try {
            $files = Get-ChildItem -LiteralPath $dir.FullName -Recurse -File -Force -ErrorAction SilentlyContinue |
                     Where-Object { $_.LastWriteTime -lt $cutoff }

            if ($files -and $files.Count -gt 0) {
                $bytes = ($files | Measure-Object Length -Sum).Sum
                Write-Host "$Description in '$($dir.FullName)': $($files.Count) files, $(Format-Bytes $bytes)" -ForegroundColor Green
                $collected += $files
            }
        } catch {
            # ignore per-dir failures
        }
    }

    return $collected
}

# ---------------- Configurable ages ----------------

# Minimum: we never delete anything newer than 2 days
$TempDays    = 2    # user / app temp
$CacheDays   = 2    # caches (browser/Electron/Firefox forks/AppData caches)
$LogDays     = 2    # logs in typical log dirs
$SystemDays  = 7    # system-level stuff (update cache, minidumps, WER, etc.)

# ---------------- Collect candidate files (dry-run phase) ----------------

Write-Host ""
Write-Host "Scanning for old temp and cache files (files only, age-limited)..." -ForegroundColor Cyan

$allFiles = @()

# 1) Windows + user temp (2+ days)
$windowsTempRoots = @(
    $env:TEMP,
    $env:TMP,
    "$($env:WINDIR)\Temp"
) | Sort-Object -Unique | Where-Object { $_ -and $_.Trim() -ne "" }

$allFiles += Collect-OldFilesFromRoots -Roots $windowsTempRoots -Days $TempDays -Description "Windows/user temp files"

# 2) Extra system caches & crash dumps (7+ days)
$systemRoots = @(
    "C:\Windows\SoftwareDistribution\Download",                    # Windows Update cache
    "C:\Windows\Minidump",                                        # Memory dumps
    "$($env:SystemDrive)\CrashDumps",                             # User-mode crash dumps (if exists)
    "C:\ProgramData\Microsoft\Windows\WER\ReportArchive",         # WER archived reports
    "C:\ProgramData\Microsoft\Windows\WER\ReportQueue"            # WER queued reports
)

$allFiles += Collect-OldFilesFromRoots -Roots $systemRoots -Days $SystemDays -Description "System update/diagnostic cache & dumps"

# 3) Legacy Edge/IE INetCache (2+ days)
$inetCacheRoot = Join-Path $env:LOCALAPPDATA "Microsoft\Windows\INetCache"
$allFiles += Collect-OldFilesFromRoots -Roots @($inetCacheRoot) -Days $CacheDays -Description "Edge/IE INetCache"

# 4) Generic browser/Electron-style caches via wildcard patterns (2+ days)
#    This is intentionally app-agnostic: anything under AppData that looks like a cache folder.

$genericCachePatterns = @()
$rootsForGeneric      = @($env:LOCALAPPDATA, $env:APPDATA) | Where-Object { $_ -and $_.Trim() -ne "" }

foreach ($root in $rootsForGeneric) {
    if (-not (Test-Path -LiteralPath $root)) { continue }

    # Patterns like:
    #   <root>\*\*\Cache*
    #   <root>\*\*\Code Cache*
    #   <root>\*\*\GPUCache*
    # Catching Chromium-based profiles, Electron apps, Steam htmlcache, etc.
    $genericCachePatterns += (Join-Path $root '*\*\Cache*')
    $genericCachePatterns += (Join-Path $root '*\*\Code Cache*')
    $genericCachePatterns += (Join-Path $root '*\*\GPUCache*')
}

$allFiles += Collect-OldFilesFromPatterns -Patterns $genericCachePatterns -Days $CacheDays -Description "Generic AppData caches"

# 5) Generic temp/log directories via wildcard patterns (2+ days)
#    Safe-ish: typical places where apps drop transient temp or log files.

$genericTempPatterns = @()
foreach ($root in $rootsForGeneric) {
    if (-not (Test-Path -LiteralPath $root)) { continue }

    # Patterns like:
    #   <root>\*\Temp
    #   <root>\*\tmp
    #   <root>\*\Logs
    $genericTempPatterns += (Join-Path $root '*\Temp')
    $genericTempPatterns += (Join-Path $root '*\tmp')
    $genericTempPatterns += (Join-Path $root '*\Logs')
}

$allFiles += Collect-OldFilesFromPatterns -Patterns $genericTempPatterns -Days $LogDays -Description "Generic AppData temp/log files"

# 6) Firefox + Firefox forks (Gecko-based) caches (2+ days)
#    We look for any "Profiles" trees under Mozilla/* and other Apps, then
#    hit the typical cache structures used by Firefox-like browsers.

$geckoProfilePatterns = @(
    (Join-Path $env:LOCALAPPDATA 'Mozilla\*\Profiles\*'),
    (Join-Path $env:APPDATA      'Mozilla\*\Profiles\*'),
    (Join-Path $env:LOCALAPPDATA '*\Profiles\*'),
    (Join-Path $env:APPDATA      '*\Profiles\*')
) | Where-Object { $_ -and $_ -notmatch '^\s*$' }

$geckoProfiles = @()
foreach ($pattern in $geckoProfilePatterns) {
    try {
        $geckoProfiles += Get-ChildItem -Path $pattern -Directory -Force -ErrorAction SilentlyContinue
    } catch {
        # ignore
    }
}

if ($geckoProfiles) {
    $geckoProfiles = $geckoProfiles | Sort-Object FullName -Unique

    foreach ($profile in $geckoProfiles) {
        $cacheDirs = @(
            (Join-Path $profile.FullName 'cache2\entries'),
            (Join-Path $profile.FullName 'cache2'),
            (Join-Path $profile.FullName 'cache')
        )

        $allFiles += Collect-OldFilesFromRoots -Roots $cacheDirs -Days $CacheDays -Description "Gecko/Firefox(-fork) cache for profile '$($profile.Name)'"
    }
}

# NOTE: You could optionally add Windows log directories like:
#   "$($env:WINDIR)\Logs\CBS", "$($env:WINDIR)\Logs\DISM"
# using Collect-OldFilesFromRoots with $LogDays, but those can be left out if you prefer.

# ---------------- Summarize & confirm ----------------

Write-Host ""

if (-not $allFiles -or $allFiles.Count -eq 0) {
    Write-Host "No old temp/cache/log files found to clean." -ForegroundColor Green
    Write-Host "Finished at $(Get-Date)." -ForegroundColor Cyan
    return
}

# Deduplicate files by full path to avoid double-processing/counting
$allFiles    = $allFiles | Sort-Object FullName -Unique
$totalCount  = $allFiles.Count
$totalBytes  = ($allFiles | Measure-Object Length -Sum).Sum
$formatted   = Format-Bytes $totalBytes

Write-Host "Scan complete." -ForegroundColor Cyan
Write-Host "  Files identified: $totalCount"
Write-Host "  Potential space to free: $formatted"
Write-Host ""

if (-not $del) {
    Write-Host "Dry-run only so far: no files deleted yet." -ForegroundColor Yellow
    $answer = Read-Host "Delete these files now? (Y/N)"
    if ($answer -notmatch '^[Yy]') {
        Write-Host "Cleanup aborted by user. No files were deleted." -ForegroundColor Yellow
        Write-Host "Finished at $(Get-Date)." -ForegroundColor Cyan
        return
    }

    Write-Host ""
    Write-Host "Proceeding to delete files..." -ForegroundColor Red
} else {
    Write-Host "Silent delete mode (-del) enabled. Deleting files without confirmation..." -ForegroundColor Red
}

# ---------------- Deletion phase ----------------

$deletedBytes = 0L
$deletedCount = 0

foreach ($file in $allFiles) {
    try {
        if (Test-Path -LiteralPath $file.FullName) {
            $size = $file.Length
            Remove-Item -LiteralPath $file.FullName -Force -ErrorAction SilentlyContinue
            $deletedBytes += $size
            $deletedCount++
        }
    } catch {
        # ignore individual failures (locked files, permissions, etc.)
    }
}

Write-Host ""
Write-Host "Deleted $deletedCount files, freeing $(Format-Bytes $deletedBytes)." -ForegroundColor Green
Write-Host "Cleanup complete at $(Get-Date)." -ForegroundColor Cyan

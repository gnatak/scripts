@echo off
setlocal EnableExtensions DisableDelayedExpansion

rem ==========================================================
rem  Backup subdirectories to encrypted 7z archives
rem
rem  Usage:
rem    backup_dirs.bat
rem    backup_dirs.bat "D:\Data"
rem    backup_dirs.bat "D:\Data" -e node_modules,.git
rem
rem  Result:
rem    directory_name_YYYYMMDD.7z
rem
rem  Password is entered securely via PowerShell.
rem ==========================================================

set "BAT_SELF=%~f0"
set "BAT_ARGS=%*"

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference = 'Stop';" ^
  "try {" ^
  "  $raw = Get-Content -LiteralPath $env:BAT_SELF -Raw;" ^
  "  $marker = '#== POWERSHELL SCRIPT BELOW ==#';" ^
  "  $idx = $raw.LastIndexOf($marker);" ^
  "  if ($idx -lt 0) { throw 'Embedded PowerShell script section not found.' }" ^
  "  $script = $raw.Substring($idx + $marker.Length);" ^
  "  & ([scriptblock]::Create($script));" ^
  "  exit 0" ^
  "} catch {" ^
  "  Write-Error $_.Exception.Message;" ^
  "  exit 1" ^
  "}"

exit /b %ERRORLEVEL%

#== POWERSHELL SCRIPT BELOW ==#
$Script:Version = '0.1'
$Script:Author  = 'gnat <gnatak@gmail.com>'

$argLine = if ($env:BAT_ARGS) { $env:BAT_ARGS } else { '' }
$ParsedArgs = @([regex]::Matches($argLine, '"([^"]*)"|(\S+)') | ForEach-Object {
    if ($_.Groups[1].Success) { $_.Groups[1].Value } else { $_.Groups[2].Value }
})

$Action   = $null
$Root     = $null
$Excludes = @()

for ($i = 0; $i -lt $ParsedArgs.Count; $i++) {
    $arg = $ParsedArgs[$i]
    switch -Exact ($arg) {
        '-h'        { $Action = 'help' }
        '--help'    { $Action = 'help' }
        '-v'        { $Action = 'version' }
        '--version' { $Action = 'version' }
        '-e'        {
            $i++
            if ($i -lt $ParsedArgs.Count) {
                $Excludes += ($ParsedArgs[$i] -split ',') | ForEach-Object { $_.Trim() } | Where-Object { $_ }
            }
        }
        '--exclude' {
            $i++
            if ($i -lt $ParsedArgs.Count) {
                $Excludes += ($ParsedArgs[$i] -split ',') | ForEach-Object { $_.Trim() } | Where-Object { $_ }
            }
        }
        default     { if (-not $Root) { $Root = $arg } }
    }
}

if (-not $Root) { $Root = (Get-Location).Path }

function Show-Version {
    Write-Host "backup_dirs $Script:Version"
    Write-Host "Author: $Script:Author"
}

function Show-BackupHelp {
    Write-Host 'Usage: backup_dirs.bat [path] [-e|--exclude <names>] [-v|--version] [-h|--help]'
    Write-Host ''
    Write-Host 'Backs up each subdirectory of <path> (default: current directory) to'
    Write-Host 'an encrypted 7z archive named <dirname>_YYYYMMDD.7z.'
    Write-Host ''
    Write-Host 'Options:'
    Write-Host '  -e, --exclude  Comma-separated list of subdirectory names to skip'
    Write-Host '                 (case-insensitive, matched against the directory name)'
    Write-Host '  -v, --version  Show version and author'
    Write-Host '  -h, --help     Show this help'
}

if ($Action -eq 'version') { Show-Version;     return }
if ($Action -eq 'help')    { Show-BackupHelp;  return }

function Find-7Zip {
    $cmd = Get-Command "7z.exe" -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Source
    }

    $candidates = @(
        "$env:ProgramFiles\7-Zip\7z.exe",
        "${env:ProgramFiles(x86)}\7-Zip\7z.exe"
    )

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) {
            return $candidate
        }
    }

    Write-Host ""
    Write-Host "7-Zip was not found." -ForegroundColor Yellow
    Write-Host ""

    $response = Read-Host "Do you want to install 7-Zip from winget? [y/N]"

    if ($response -match '^[yY]$') {
        Write-Host ""
        Write-Host "Installing 7-Zip..." -ForegroundColor Cyan
        Write-Host ""

        try {
            & winget install 7zip.7zip --silent --accept-source-agreements --accept-package-agreements

            if ($LASTEXITCODE -eq 0) {
                Write-Host ""
                Write-Host "7-Zip was successfully installed." -ForegroundColor Green
                Write-Host ""

                $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

                $newCmd = Get-Command "7z.exe" -ErrorAction SilentlyContinue
                if ($newCmd) {
                    return $newCmd.Source
                }

                foreach ($candidate in $candidates) {
                    if ($candidate -and (Test-Path -LiteralPath $candidate)) {
                        return $candidate
                    }
                }
            }
        }
        catch {
            Write-Host "Installation error: $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    throw "7-Zip is not available. Install 7-Zip or add 7z.exe to PATH."
}

function Get-DirectorySizeBytes {
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.DirectoryInfo]$Directory
    )

    [int64]$size = 0

    Get-ChildItem -LiteralPath $Directory.FullName -Recurse -Force -File -ErrorAction SilentlyContinue |
        ForEach-Object {
            $size += $_.Length
        }

    return $size
}

function Format-Bytes {
    param(
        [int64]$Bytes
    )

    if ($Bytes -eq 0) {
        return "0 B"
    }

    $units = @("B", "KB", "MB", "GB", "TB", "PB")
    $index = [Math]::Floor([Math]::Log($Bytes) / [Math]::Log(1024))
    $index = [Math]::Min($index, $units.Count - 1)

    return "{0:N2} {1}" -f ($Bytes / [Math]::Pow(1024, $index)), $units[$index]
}

function Convert-SecureStringToPlainText {
    param(
        [Parameter(Mandatory = $true)]
        [System.Security.SecureString]$SecureString
    )

    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString)

    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

function Test-IsExcluded {
    param(
        [Parameter(Mandatory = $true)] [string]$Name,
        [string[]]$ExcludeList
    )
    if (-not $ExcludeList -or $ExcludeList.Count -eq 0) { return $false }
    foreach ($ex in $ExcludeList) {
        if ([string]::Equals($Name, $ex, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }
    return $false
}

try {
    $sevenZip = Find-7Zip

    $rootItem = Get-Item -LiteralPath $Root -ErrorAction Stop

    if (-not $rootItem.PSIsContainer) {
        throw "The specified path is not a directory: $Root"
    }

    $rootPath = $rootItem.FullName

    $allDirectories = @(Get-ChildItem -LiteralPath $rootPath -Directory -Force | Sort-Object Name)

    $skipped = @()
    $directories = foreach ($dir in $allDirectories) {
        if (Test-IsExcluded -Name $dir.Name -ExcludeList $Excludes) {
            $skipped += $dir.Name
        } else {
            $dir
        }
    }
    $directories = @($directories)

    if ($directories.Count -eq 0) {
        Write-Host ""
        Write-Host "No subdirectories found to backup:"
        Write-Host "  $rootPath"
        if ($skipped.Count -gt 0) {
            Write-Host ""
            Write-Host ("Excluded: {0}" -f ($skipped -join ', '))
        }
        exit 0
    }

    Write-Host ""
    Write-Host "Backup directory:"
    Write-Host "  $rootPath"
    if ($skipped.Count -gt 0) {
        Write-Host ""
        Write-Host ("Excluded ({0}): {1}" -f $skipped.Count, ($skipped -join ', '))
    }
    Write-Host ""
    Write-Host "Computing directory sizes..."
    Write-Host ""

    $backupItems = foreach ($dir in $directories) {
        $sizeBytes = Get-DirectorySizeBytes -Directory $dir

        [PSCustomObject]@{
            Name      = $dir.Name
            FullName  = $dir.FullName
            SizeBytes = $sizeBytes
            SizeText  = Format-Bytes $sizeBytes
        }
    }

    $totalBytes = ($backupItems | Measure-Object -Property SizeBytes -Sum).Sum
    if ($null -eq $totalBytes) {
        $totalBytes = 0
    }

    function Show-BackupTable {
        param([PSObject[]]$Items)
        $i = 0
        $Items |
            ForEach-Object {
                $i++
                [PSCustomObject]@{
                    '#'       = $i
                    Directory = $_.Name
                    Size      = $_.SizeText
                    Path      = $_.FullName
                }
            } |
            Format-Table -AutoSize
    }

    Write-Host "Directories to backup:"
    Write-Host ""
    Show-BackupTable -Items $backupItems

    Write-Host ""
    Write-Host ("Total: {0} directories, approximate size {1}" -f $backupItems.Count, (Format-Bytes $totalBytes))
    Write-Host ""

    $excludeInput = Read-Host "Numbers to exclude (comma-separated), or Enter to continue"
    if (-not [string]::IsNullOrWhiteSpace($excludeInput)) {
        $excludeIdx = @()
        foreach ($tok in ($excludeInput -split ',')) {
            $t = $tok.Trim()
            if ($t -match '^\d+$') {
                $n = [int]$t
                if ($n -ge 1 -and $n -le $backupItems.Count) {
                    $excludeIdx += ($n - 1)
                } else {
                    Write-Warning "Out of range, ignoring: $n"
                }
            } elseif ($t) {
                Write-Warning "Not a number, ignoring: $t"
            }
        }
        $excludeIdx = $excludeIdx | Select-Object -Unique
        if ($excludeIdx.Count -gt 0) {
            $removed = @()
            $kept    = @()
            for ($i = 0; $i -lt $backupItems.Count; $i++) {
                if ($excludeIdx -contains $i) { $removed += $backupItems[$i] }
                else                          { $kept    += $backupItems[$i] }
            }
            $backupItems = $kept
            Write-Host ""
            Write-Host ("Excluded interactively ({0}): {1}" -f $removed.Count, (($removed | ForEach-Object { $_.Name }) -join ', '))

            if ($backupItems.Count -eq 0) {
                Write-Host ""
                Write-Host "No directories left to backup."
                exit 0
            }

            $totalBytes = ($backupItems | Measure-Object -Property SizeBytes -Sum).Sum
            if ($null -eq $totalBytes) { $totalBytes = 0 }

            Write-Host ""
            Write-Host "Directories to backup:"
            Write-Host ""
            Show-BackupTable -Items $backupItems
            Write-Host ""
            Write-Host ("Total: {0} directories, approximate size {1}" -f $backupItems.Count, (Format-Bytes $totalBytes))
            Write-Host ""
        }
    }

    $securePassword1 = Read-Host -AsSecureString "Enter password for encrypted archives"
    $securePassword2 = Read-Host -AsSecureString "Enter password again to verify"

    $password1 = Convert-SecureStringToPlainText $securePassword1
    $password2 = Convert-SecureStringToPlainText $securePassword2

    if ([string]::IsNullOrEmpty($password1)) {
        throw "Password cannot be empty."
    }

    if ($password1 -ne $password2) {
        throw "Passwords do not match."
    }

    $date = Get-Date -Format "yyyyMMdd"

    Write-Host ""
    Write-Host "Starting to create encrypted archives..."
    Write-Host ""

    $failed = 0
    $warnings = 0

    Push-Location $rootPath

    try {
        foreach ($item in $backupItems) {
            $archiveName = "{0}_{1}.7z" -f $item.Name, $date
            $archivePath = Join-Path $rootPath $archiveName

            if (Test-Path -LiteralPath $archivePath) {
                Write-Warning "Archive already exists, skipping: $archivePath"
                continue
            }

            Write-Host "Backing up: $($item.Name)"
            Write-Host "Archive:    $archiveName"

            $arguments = @(
                "a",
                "-t7z",
                $archivePath,
                ".\$($item.Name)",
                "-mx=9",
                "-mhe=on",
                "-p$password1",
                "-y"
            )

            & $sevenZip @arguments

            $exitCode = $LASTEXITCODE

            if ($exitCode -eq 0) {
                Write-Host "Done."
                Write-Host ""
            }
            elseif ($exitCode -eq 1) {
                $warnings++
                Write-Warning "Archive created with warning: $archivePath"
                Write-Host ""
            }
            else {
                $failed++
                Write-Host "ERROR creating archive: $archivePath"
                Write-Host "7-Zip exit code: $exitCode"
                Write-Host ""
            }
        }
    }
    finally {
        Pop-Location
    }

    Write-Host ""
    Write-Host "Backup completed."
    Write-Host "Warnings: $warnings"
    Write-Host "Errors:   $failed"

    if ($failed -gt 0) {
        exit 2
    }

    exit 0
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
finally {
    $password1 = $null
    $password2 = $null
}

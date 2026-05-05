@echo off
setlocal EnableExtensions DisableDelayedExpansion

rem ==========================================================
rem  Synchronise winget packages across PCs
rem
rem  Usage:
rem    winget_sync.bat -c [filename]         - Export installed packages
rem    winget_sync.bat -d <filename>         - Compare against file
rem    winget_sync.bat -i <filename>         - Install packages from file
rem    winget_sync.bat -h                    - Show help
rem
rem  File format: fixed-width columns (Name, Id, Version, Source)
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
Set-StrictMode -Version Latest

$Script:Version = '0.1'
$Script:Author  = 'gnat <gnatak@gmail.com>'

$argLine = if ($env:BAT_ARGS) { $env:BAT_ARGS } else { '' }
$ParsedArgs = [regex]::Matches($argLine, '"([^"]*)"|(\S+)') | ForEach-Object {
    if ($_.Groups[1].Success) { $_.Groups[1].Value } else { $_.Groups[2].Value }
}

$Action = $null
$FileName = $null

foreach ($arg in $ParsedArgs) {
    switch -Exact ($arg) {
        '-h'        { $Action = 'help' }
        '--help'    { $Action = 'help' }
        '-v'        { $Action = 'version' }
        '--version' { $Action = 'version' }
        '-c'        { $Action = 'create' }
        '--create'  { $Action = 'create' }
        '-d'        { $Action = 'diff'   }
        '--diff'    { $Action = 'diff'   }
        '-i'        { $Action = 'install' }
        '--install' { $Action = 'install' }
        default     { if (-not $FileName) { $FileName = $arg } }
    }
}

function Get-WingetListNames {
    $raw    = & winget list 2>&1
    $lines  = $raw | ForEach-Object { "$_" }
    $lookup = @{}

    $sepIdx = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^-[\s-]+$' -and $lines[$i].Contains('-')) { $sepIdx = $i; break }
    }
    if ($sepIdx -lt 1) { return $lookup }

    $header     = $lines[$sepIdx - 1]
    $namePos    = $header.IndexOf('Name')
    $idPos      = $header.IndexOf('Id')
    $versionPos = $header.IndexOf('Version')

    for ($i = $sepIdx + 1; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ([string]::IsNullOrWhiteSpace($line) -or $line.Length -le $idPos) { continue }

        $name = ($line.Substring($namePos, [Math]::Min($idPos - $namePos, $line.Length - $namePos)).Trim() `
                 -replace '^[^\x20-\x7E]+', '').Trim()
        $id   = ($line.Substring($idPos, [Math]::Min($versionPos, $line.Length) - $idPos).Trim() `
                 -replace '^[^\x20-\x7E]+', '').Trim()

        if ($id -and $name -and $id -notmatch '^-+$') { $lookup[$id] = $name }
    }
    return $lookup
}

function Get-InstalledPackages {
    $tempFile = [System.IO.Path]::ChangeExtension([System.IO.Path]::GetTempFileName(), '.json')
    try {
        & winget export --output $tempFile --include-versions --accept-source-agreements 2>&1 | Out-Null
        if (-not (Test-Path $tempFile)) { throw 'winget export did not produce output.' }

        $nameLookup = Get-WingetListNames
        $data       = Get-Content $tempFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $packages   = [System.Collections.Generic.List[PSObject]]::new()

        foreach ($src in $data.Sources) {
            $sourceName = $src.SourceDetails.Name
            foreach ($pkg in $src.Packages) {
                $id      = $pkg.PackageIdentifier
                $version = if ($pkg.Version) { $pkg.Version -replace '^>\s*', '' } else { '' }

                $displayName = if ($nameLookup.ContainsKey($id)) {
                    $nameLookup[$id]
                } else {
                    $prefix = $nameLookup.Keys | Where-Object { $id.StartsWith($_) } | Select-Object -First 1
                    if ($prefix) { $nameLookup[$prefix] } else { $id }
                }

                $packages.Add([PSCustomObject]@{
                    Name    = $displayName
                    Id      = $id
                    Version = $version
                    Source  = $sourceName
                })
            }
        }
        return $packages
    } finally {
        if (Test-Path $tempFile) { Remove-Item $tempFile -Force }
    }
}

function Read-PackageFile {
    param([string]$Path)

    $lines    = Get-Content -Path $Path -Encoding UTF8
    $packages = [System.Collections.Generic.List[PSObject]]::new()

    $sepIdx = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^-[\s-]+$' -and $lines[$i].Contains('-')) { $sepIdx = $i; break }
    }

    if ($sepIdx -ge 1) {
        $header     = $lines[$sepIdx - 1]
        $namePos    = $header.IndexOf('Name')
        $idPos      = $header.IndexOf('Id')
        $versionPos = $header.IndexOf('Version')
        $sourcePos  = $header.IndexOf('Source')

        for ($i = $sepIdx + 1; $i -lt $lines.Count; $i++) {
            $line = $lines[$i]
            if ([string]::IsNullOrWhiteSpace($line)) { continue }

            $name = if ($namePos -ge 0 -and $line.Length -gt $namePos) {
                $end = if ($idPos -gt 0) { [Math]::Min($idPos, $line.Length) } else { $line.Length }
                $line.Substring($namePos, $end - $namePos).Trim()
            } else { '' }

            $id = if ($line.Length -gt $idPos) {
                $end = if ($versionPos -gt 0) { [Math]::Min($versionPos, $line.Length) } else { $line.Length }
                $line.Substring($idPos, $end - $idPos).Trim()
            } else { '' }

            $version = if ($versionPos -gt 0 -and $line.Length -gt $versionPos) {
                $end = if ($sourcePos -gt 0) { [Math]::Min($sourcePos, $line.Length) } else { $line.Length }
                $line.Substring($versionPos, $end - $versionPos).Trim()
            } else { '' }

            $source = if ($sourcePos -gt 0 -and $line.Length -gt $sourcePos) {
                $line.Substring($sourcePos).Trim()
            } else { '' }

            if ($id) { $packages.Add([PSCustomObject]@{ Name = $name; Id = $id; Version = $version; Source = $source }) }
        }
    } else {
        foreach ($line in $lines) {
            if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('#')) { continue }
            $parts = $line -split '\t'
            $packages.Add([PSCustomObject]@{
                Name    = ''
                Id      = $parts[0].Trim()
                Version = if ($parts.Count -ge 2) { $parts[1].Trim() } else { '' }
                Source  = if ($parts.Count -ge 3) { $parts[2].Trim() } else { '' }
            })
        }
    }

    return $packages
}

function Format-WingetTable {
    param([PSObject[]]$Packages)

    $colName    = [Math]::Max(($Packages | ForEach-Object { $_.Name.Length }    | Measure-Object -Maximum).Maximum, 4)
    $colId      = [Math]::Max(($Packages | ForEach-Object { $_.Id.Length }      | Measure-Object -Maximum).Maximum, 2)
    $colVersion = [Math]::Max(($Packages | ForEach-Object { $_.Version.Length } | Measure-Object -Maximum).Maximum, 7)
    $colSource  = [Math]::Max(($Packages | ForEach-Object { $_.Source.Length }  | Measure-Object -Maximum).Maximum, 6)

    $pad     = 2
    $header  = 'Name'.PadRight($colName + $pad) + 'Id'.PadRight($colId + $pad) +
               'Version'.PadRight($colVersion + $pad) + 'Source'
    $sepLine = '-' * ($colName + $pad + $colId + $pad + $colVersion + $pad + $colSource)

    $rows = $Packages | ForEach-Object {
        $_.Name.PadRight($colName + $pad) + $_.Id.PadRight($colId + $pad) +
        $_.Version.PadRight($colVersion + $pad) + $_.Source
    }

    return @($header, $sepLine) + $rows
}

function Invoke-Create {
    param([string]$FileName)

    if (Test-Path -LiteralPath $FileName) {
        $confirm = Read-Host "File '$FileName' already exists. Overwrite? [y/N]"
        if ($confirm -notmatch '^[yY]$') { Write-Host 'Cancelled.'; return }
    }

    Write-Host 'Reading installed packages...'
    $packages = Get-InstalledPackages
    $lines    = Format-WingetTable -Packages $packages
    Set-Content -Path $FileName -Value $lines -Encoding UTF8
    Write-Host "Exported $($packages.Count) packages to '$FileName'."
}

function Invoke-Diff {
    param([string]$FileName)

    if (-not (Test-Path $FileName)) { throw "File not found: $FileName" }

    Write-Host 'Reading installed packages...'
    $installed   = Get-InstalledPackages
    $saved       = Read-PackageFile -Path $FileName
    $installedMap = @{}; $installed | ForEach-Object { $installedMap[$_.Id] = $_.Name }
    $savedMap     = @{}; $saved     | ForEach-Object { $savedMap[$_.Id] = $_.Name }
    $installedIds = @($installed | Select-Object -ExpandProperty Id)
    $savedIds     = @($saved     | Select-Object -ExpandProperty Id)

    $missing = @($savedIds     | Where-Object { $_ -notin $installedIds })
    $extra   = @($installedIds | Where-Object { $_ -notin $savedIds })

    if ($missing) {
        Write-Host "`nIn file, not installed ($($missing.Count)):" -ForegroundColor Yellow
        $missing | ForEach-Object { Write-Host "  - $($savedMap[$_])  [$_]" }
    }
    if ($extra) {
        Write-Host "`nInstalled, not in file ($($extra.Count)):" -ForegroundColor Cyan
        $extra | ForEach-Object { Write-Host "  + $($installedMap[$_])  [$_]" }
    }
    if (-not $missing -and -not $extra) {
        Write-Host 'No differences.' -ForegroundColor Green
    }
}

function Invoke-Install {
    param([string]$FileName)

    if (-not (Test-Path $FileName)) { throw "File not found: $FileName" }

    $packages = Read-PackageFile -Path $FileName
    Write-Host "`nPackages to install ($($packages.Count)):"
    $packages | ForEach-Object { Write-Host "  $($_.Name)  [$($_.Id)]  $($_.Version)" }

    $confirm = Read-Host "`nProceed? [y/N]"
    if ($confirm -notmatch '^[yY]$') { Write-Host 'Cancelled.'; return }

    foreach ($pkg in $packages) {
        Write-Host "`n-> $($pkg.Name)  [$($pkg.Id)]" -ForegroundColor Cyan
        $installArgs = @('install', '--id', $pkg.Id, '--silent',
                         '--accept-package-agreements', '--accept-source-agreements')
        if ($pkg.Source) { $installArgs += '--source', $pkg.Source }
        & winget @installArgs
    }
}

function Show-Help {
    Write-Host 'Usage: winget_sync.bat [-c|--create [filename]] [-d|--diff <filename>] [-i|--install <filename>] [-v|--version] [-h|--help]'
    Write-Host ''
    Write-Host 'Options:'
    Write-Host '  -c, --create   Export installed packages to file (default: COMPUTERNAME_YYYYMMDD.wgl)'
    Write-Host '  -d, --diff     Compare installed packages against file'
    Write-Host '  -i, --install  Install packages listed in file'
    Write-Host '  -v, --version  Show version and author'
    Write-Host '  -h, --help     Show this help'
    Write-Host ''
    Write-Host 'File format: fixed-width columns (Name, Id, Version, Source) with header and separator'
}

function Show-Version {
    Write-Host "winget_sync $Script:Version"
    Write-Host "Author: $Script:Author"
}

if ($Action -eq 'help') {
    Show-Help
    exit 0
}

if ($Action -eq 'version') {
    Show-Version
    exit 0
}

if (-not $Action) {
    Show-Help
    exit 1
}

if (-not $FileName) {
    if ($Action -eq 'create') {
        $FileName = "$($env:COMPUTERNAME)_$(Get-Date -Format 'yyyyMMdd').wgl"
    } else {
        $wglFiles = @(Get-ChildItem -Path (Get-Location) -Filter '*.wgl' | Sort-Object Name)
        if ($wglFiles.Count -eq 0) {
            Write-Host 'No .wgl files found in current directory.' -ForegroundColor Red
            exit 1
        }
        Write-Host 'Select a file:'
        for ($i = 0; $i -lt $wglFiles.Count; $i++) {
            Write-Host "  [$($i + 1)] $($wglFiles[$i].Name)"
        }
        $choice = Read-Host 'Enter number'
        if ($choice -notmatch '^\d+$' -or [int]$choice -lt 1 -or [int]$choice -gt $wglFiles.Count) {
            Write-Host 'Invalid selection.' -ForegroundColor Red
            exit 1
        }
        $FileName = $wglFiles[[int]$choice - 1].FullName
    }
}

switch ($Action) {
    'create'  { Invoke-Create  -FileName $FileName }
    'diff'    { Invoke-Diff    -FileName $FileName }
    'install' { Invoke-Install -FileName $FileName }
}

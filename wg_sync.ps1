#Requires -Version 5.1
<#
.SYNOPSIS
    Synchronises winget packages across PCs.

.DESCRIPTION
    Exports, compares, and installs winget packages using a fixed-width .wgl file.
    Package IDs are sourced from winget export; display names from winget list.
    Only packages with a known winget source are included.

.SYNTAX
    wg_sync [-c|--create [filename]] [-d|--diff [filename]] [-i|--install [filename]]
    wg_sync -h|--help

.AUTHOR
    Daniel Komarek, Claude (Anthropic)

.VERSION
    1.0  2026-04-26  Initial release
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-WingetListNames {
    # Returns hashtable: id_key -> display_name (id_key may be truncated)
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

                # Exact match first; fall back to prefix match for truncated IDs from winget list
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

            if ($id) { $packages.Add([PSCustomObject]@{ Id = $id; Version = $version; Source = $source }) }
        }
    } else {
        # Tab-delimited fallback (old format)
        foreach ($line in $lines) {
            if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('#')) { continue }
            $parts = $line -split '\t'
            $packages.Add([PSCustomObject]@{
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
    $installedIds = @($installed | Select-Object -ExpandProperty Id)
    $savedIds     = @($saved     | Select-Object -ExpandProperty Id)

    $missing = @($savedIds     | Where-Object { $_ -notin $installedIds })
    $extra   = @($installedIds | Where-Object { $_ -notin $savedIds })

    if ($missing) {
        Write-Host "`nIn file, not installed ($($missing.Count)):" -ForegroundColor Yellow
        $missing | ForEach-Object { Write-Host "  - $_" }
    }
    if ($extra) {
        Write-Host "`nInstalled, not in file ($($extra.Count)):" -ForegroundColor Cyan
        $extra | ForEach-Object { Write-Host "  + $_" }
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
    $packages | ForEach-Object { Write-Host "  $($_.Id)  $($_.Version)" }

    $confirm = Read-Host "`nProceed? [y/N]"
    if ($confirm -notmatch '^[yY]$') { Write-Host 'Cancelled.'; return }

    foreach ($pkg in $packages) {
        Write-Host "`n-> $($pkg.Id)" -ForegroundColor Cyan
        $installArgs = @('install', '--id', $pkg.Id, '--silent',
                         '--accept-package-agreements', '--accept-source-agreements')
        if ($pkg.Source) { $installArgs += '--source', $pkg.Source }
        & winget @installArgs
    }
}

# ── Argument parsing ──────────────────────────────────────────────────────────
$action   = $null
$fileName = $null

foreach ($arg in $args) {
    switch -Exact ($arg) {
        '-h'        { $action = 'help' }
        '--help'    { $action = 'help' }
        '-c'        { $action = 'create' }
        '--create'  { $action = 'create' }
        '-d'        { $action = 'diff'   }
        '--diff'    { $action = 'diff'   }
        '-i'        { $action = 'install' }
        '--install' { $action = 'install' }
        default     { if (-not $fileName) { $fileName = $arg } }
    }
}

function Show-Help {
    Write-Host 'Usage: wg_sync [-c|--create [filename]] [-d|--diff] [-i|--install] <filename>'
    Write-Host '       wg_sync -h|--help'
    Write-Host ''
    Write-Host 'Options:'
    Write-Host '  -c, --create   Export installed packages to file (default: COMPUTERNAME_YYYYMMDD.wgl)'
    Write-Host '  -d, --diff     Compare installed packages against file'
    Write-Host '  -i, --install  Install packages listed in file'
    Write-Host '  -h, --help     Show this help'
    Write-Host ''
    Write-Host 'File format: fixed-width columns (Name, Id, Version, Source) with header and separator'
}

if ($action -eq 'help') { Show-Help; exit 0 }

if (-not $action) { Show-Help; exit 1 }

if (-not $fileName) {
    if ($action -eq 'create') {
        $fileName = "$($env:COMPUTERNAME)_$(Get-Date -Format 'yyyyMMdd').wgl"
    } else {
        $wglFiles = @(Get-ChildItem -Path $PSScriptRoot -Filter '*.wgl' | Sort-Object Name)
        if ($wglFiles.Count -eq 0) {
            Write-Host 'No .wgl files found in script directory.' -ForegroundColor Red
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
        $fileName = $wglFiles[[int]$choice - 1].FullName
    }
}

switch ($action) {
    'create'  { Invoke-Create  -FileName $fileName }
    'diff'    { Invoke-Diff    -FileName $fileName }
    'install' { Invoke-Install -FileName $fileName }
}

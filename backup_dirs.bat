@echo off
setlocal EnableExtensions DisableDelayedExpansion

rem ==========================================================
rem  Zaloha podadresaru do sifrovanych 7z archivu
rem
rem  Pouziti:
rem    backup_dirs.bat
rem    backup_dirs.bat "D:\Data"
rem
rem  Vysledek:
rem    jmeno_adresare_YYYYMMDD.7z
rem
rem  Heslo se zadava skryte pres PowerShell.
rem ==========================================================

set "BACKUP_ROOT=%~1"
if not defined BACKUP_ROOT set "BACKUP_ROOT=%CD%"

set "BAT_SELF=%~f0"

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference = 'Stop';" ^
  "try {" ^
  "  $raw = Get-Content -LiteralPath $env:BAT_SELF -Raw;" ^
  "  $marker = '#== POWERSHELL SCRIPT BELOW ==#';" ^
  "  $idx = $raw.LastIndexOf($marker);" ^
  "  if ($idx -lt 0) { throw 'Nenalezena vlozena PowerShell cast skriptu.' }" ^
  "  $script = $raw.Substring($idx + $marker.Length);" ^
  "  & ([scriptblock]::Create($script)) -Root $env:BACKUP_ROOT;" ^
  "  exit 0" ^
  "} catch {" ^
  "  Write-Error $_.Exception.Message;" ^
  "  exit 1" ^
  "}"

exit /b %ERRORLEVEL%

#== POWERSHELL SCRIPT BELOW ==#
param(
    [Parameter(Mandatory = $true)]
    [string]$Root
)

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

    throw "7-Zip nebyl nalezen. Nainstalujte 7-Zip nebo pridejte 7z.exe do PATH."
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

try {
    $sevenZip = Find-7Zip

    $rootItem = Get-Item -LiteralPath $Root -ErrorAction Stop

    if (-not $rootItem.PSIsContainer) {
        throw "Zadana cesta neni adresar: $Root"
    }

    $rootPath = $rootItem.FullName

    $directories = @(Get-ChildItem -LiteralPath $rootPath -Directory -Force | Sort-Object Name)

    if ($directories.Count -eq 0) {
        Write-Host ""
        Write-Host "V adresari nejsou zadne podadresare k zaloze:"
        Write-Host "  $rootPath"
        exit 0
    }

    Write-Host ""
    Write-Host "Adresar pro zalohu:"
    Write-Host "  $rootPath"
    Write-Host ""
    Write-Host "Pocitam velikosti adresaru..."
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

    Write-Host "Zalohovat se budou tyto adresare:"
    Write-Host ""

    $backupItems |
        Select-Object `
            @{Name = "Adresar"; Expression = { $_.Name } },
            @{Name = "Velikost"; Expression = { $_.SizeText } },
            @{Name = "Cesta"; Expression = { $_.FullName } } |
        Format-Table -AutoSize

    Write-Host ""
    Write-Host ("Celkem: {0} adresaru, velikost priblizne {1}" -f $backupItems.Count, (Format-Bytes $totalBytes))
    Write-Host ""

    $securePassword1 = Read-Host -AsSecureString "Zadejte heslo pro sifrovane archivy"
    $securePassword2 = Read-Host -AsSecureString "Zadejte heslo znovu pro kontrolu"

    $password1 = Convert-SecureStringToPlainText $securePassword1
    $password2 = Convert-SecureStringToPlainText $securePassword2

    if ([string]::IsNullOrEmpty($password1)) {
        throw "Heslo nesmi byt prazdne."
    }

    if ($password1 -ne $password2) {
        throw "Hesla se neshoduji."
    }

    $date = Get-Date -Format "yyyyMMdd"

    Write-Host ""
    Write-Host "Zacinam vytvaret sifrovane archivy..."
    Write-Host ""

    $failed = 0
    $warnings = 0

    Push-Location $rootPath

    try {
        foreach ($item in $backupItems) {
            $archiveName = "{0}_{1}.7z" -f $item.Name, $date
            $archivePath = Join-Path $rootPath $archiveName

            if (Test-Path -LiteralPath $archivePath) {
                Write-Warning "Archiv uz existuje, preskakuji: $archivePath"
                continue
            }

            Write-Host "Zalohuji: $($item.Name)"
            Write-Host "Archiv:   $archiveName"

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
                Write-Host "Hotovo."
                Write-Host ""
            }
            elseif ($exitCode -eq 1) {
                $warnings++
                Write-Warning "Archiv byl vytvoren s varovanim: $archivePath"
                Write-Host ""
            }
            else {
                $failed++
                Write-Host "CHYBA pri vytvareni archivu: $archivePath"
                Write-Host "Navratovy kod 7-Zip: $exitCode"
                Write-Host ""
            }
        }
    }
    finally {
        Pop-Location
    }

    Write-Host ""
    Write-Host "Zalohovani dokonceno."
    Write-Host "Varovani: $warnings"
    Write-Host "Chyby:    $failed"

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

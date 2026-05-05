Set-StrictMode -Version Latest

$batPath = Join-Path $PSScriptRoot 'backup_dirs.bat'
$raw     = Get-Content -LiteralPath $batPath -Raw
$marker  = '#== POWERSHELL SCRIPT BELOW ==#'
$idx     = $raw.LastIndexOf($marker)
if ($idx -lt 0) { throw "Marker not found in $batPath" }
$embedded = $raw.Substring($idx + $marker.Length)

$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseInput($embedded, [ref]$tokens, [ref]$errors)
$functions = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
foreach ($fn in $functions) {
    Invoke-Expression $fn.Extent.Text
}

Describe 'Format-Bytes' {
    It 'returns "0 B" for zero' {
        Format-Bytes -Bytes 0 | Should Be '0 B'
    }

    It 'formats bytes below KB' {
        Format-Bytes -Bytes 512 | Should Match '512.*B$'
    }

    It 'formats kilobytes' {
        $result = Format-Bytes -Bytes 2048
        $result | Should Match 'KB'
        $result | Should Match '^2'
    }

    It 'formats megabytes' {
        $result = Format-Bytes -Bytes (5 * 1024 * 1024)
        $result | Should Match 'MB'
    }

    It 'formats gigabytes' {
        $result = Format-Bytes -Bytes ([int64](3 * 1024 * 1024 * 1024))
        $result | Should Match 'GB'
    }
}

Describe 'Get-DirectorySizeBytes' {
    It 'sums sizes of all files recursively' {
        $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("bdtest_" + [guid]::NewGuid().ToString('N'))
        New-Item -Path $tempDir -ItemType Directory -Force | Out-Null
        $sub = Join-Path $tempDir 'sub'
        New-Item -Path $sub -ItemType Directory -Force | Out-Null

        try {
            Set-Content -Path (Join-Path $tempDir 'a.txt') -Value ('a' * 100) -NoNewline -Encoding ASCII
            Set-Content -Path (Join-Path $sub 'b.txt')     -Value ('b' * 250) -NoNewline -Encoding ASCII

            $dirInfo = Get-Item -LiteralPath $tempDir
            $size    = Get-DirectorySizeBytes -Directory $dirInfo

            $size | Should Be 350
        } finally {
            Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'returns 0 for an empty directory' {
        $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("bdtest_" + [guid]::NewGuid().ToString('N'))
        New-Item -Path $tempDir -ItemType Directory -Force | Out-Null

        try {
            $dirInfo = Get-Item -LiteralPath $tempDir
            $size    = Get-DirectorySizeBytes -Directory $dirInfo
            $size | Should Be 0
        } finally {
            Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Convert-SecureStringToPlainText' {
    It 'round-trips a non-empty password' {
        $plain  = 'Tajne-Heslo123!'
        $secure = ConvertTo-SecureString -String $plain -AsPlainText -Force
        Convert-SecureStringToPlainText -SecureString $secure | Should Be $plain
    }

    It 'returns empty string for empty SecureString' {
        $secure = New-Object System.Security.SecureString
        $secure.MakeReadOnly()
        Convert-SecureStringToPlainText -SecureString $secure | Should Be ''
    }
}

Describe 'Find-7Zip' {
    It 'returns existing 7z.exe path when found in PATH' {
        Mock -CommandName 'Get-Command' -ParameterFilter { $Name -eq '7z.exe' } -MockWith {
            return [PSCustomObject]@{ Source = 'C:\fake\7z.exe' }
        }

        Find-7Zip | Should Be 'C:\fake\7z.exe'
    }
}

Describe 'backup_dirs.bat (black-box)' {
    It 'prints version and author on -v' {
        $output = & $batPath -v 2>&1
        $LASTEXITCODE | Should Be 0
        ($output -join "`n") | Should Match 'backup_dirs 0\.1'
        ($output -join "`n") | Should Match 'gnat'
        ($output -join "`n") | Should Match 'gnatak@gmail\.com'
    }

    It 'prints help on -h' {
        $output = & $batPath -h 2>&1
        $LASTEXITCODE | Should Be 0
        ($output -join "`n") | Should Match 'Usage:'
    }
}

Set-StrictMode -Version Latest

$batPath = Join-Path $PSScriptRoot 'winget_sync.bat'
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

Describe 'Read-PackageFile' {
    It 'reads fixed-width format with Name, Id, Version, Source' {
        $tempFile = New-TemporaryFile
        $content = @(
            'Name                  Id                         Version         Source',
            '--------------------------------------------------',
            'Git                   Git.Git                    2.54.0          winget',
            'Docker Desktop        Docker.DockerDesktop       4.70.0          winget'
        ) -join "`n"
        Set-Content -Path $tempFile -Value $content -Encoding UTF8

        try {
            $result = Read-PackageFile -Path $tempFile.FullName
            $result.Count   | Should Be 2
            $result[0].Name | Should Be 'Git'
            $result[0].Id   | Should Be 'Git.Git'
            $result[0].Version | Should Be '2.54.0'
            $result[0].Source  | Should Be 'winget'
            $result[1].Name | Should Be 'Docker Desktop'
        } finally {
            Remove-Item $tempFile -Force
        }
    }

    It 'reads tab-delimited format' {
        $tempFile = New-TemporaryFile
        $content = @(
            "Git.Git`t2.54.0`twinget",
            "Docker.DockerDesktop`t4.70.0`twinget"
        ) -join "`n"
        Set-Content -Path $tempFile -Value $content -Encoding UTF8

        try {
            $result = Read-PackageFile -Path $tempFile.FullName
            $result.Count    | Should Be 2
            $result[0].Id    | Should Be 'Git.Git'
            $result[0].Version | Should Be '2.54.0'
            $result[0].Source  | Should Be 'winget'
        } finally {
            Remove-Item $tempFile -Force
        }
    }

    It 'skips empty lines in fixed-width format' {
        $tempFile = New-TemporaryFile
        $content = @(
            'Name                  Id                         Version         Source',
            '--------------------------------------------------',
            'Git                   Git.Git                    2.54.0          winget',
            '',
            'Docker Desktop        Docker.DockerDesktop       4.70.0          winget'
        ) -join "`n"
        Set-Content -Path $tempFile -Value $content -Encoding UTF8

        try {
            $result = Read-PackageFile -Path $tempFile.FullName
            $result.Count | Should Be 2
        } finally {
            Remove-Item $tempFile -Force
        }
    }

    It 'handles tab-delimited file without separator' {
        $tempFile = New-TemporaryFile
        $content = @(
            "Git.Git`t2.54.0`twinget",
            "Docker.DockerDesktop`t4.70.0`twinget"
        ) -join "`n"
        Set-Content -Path $tempFile -Value $content -Encoding UTF8

        try {
            $result = Read-PackageFile -Path $tempFile.FullName
            $result.Count | Should Be 2
        } finally {
            Remove-Item $tempFile -Force
        }
    }
}

Describe 'Format-WingetTable' {
    It 'produces header, separator and one row per package' {
        $packages = @(
            [PSCustomObject]@{ Name = 'Git';    Id = 'Git.Git';              Version = '2.54.0'; Source = 'winget' },
            [PSCustomObject]@{ Name = 'Docker'; Id = 'Docker.DockerDesktop'; Version = '4.70.0'; Source = 'winget' }
        )
        $result = Format-WingetTable -Packages $packages
        $result.Count | Should Be 4
        $result[0]    | Should Match 'Name'
        $result[0]    | Should Match 'Id'
        $result[0]    | Should Match 'Version'
        $result[0]    | Should Match 'Source'
        $result[1]    | Should Match '^-'
    }

    It 'pads columns so Id position is preserved' {
        $packages = @(
            [PSCustomObject]@{ Name = 'A';      Id = 'A.A';           Version = '1.0';   Source = 'winget' },
            [PSCustomObject]@{ Name = 'Longer'; Id = 'Longer.Pkg.Id'; Version = '2.0.0'; Source = 'winget' }
        )
        $result = Format-WingetTable -Packages $packages
        $headerIdPos = $result[0].IndexOf('Id')
        $row1IdPos   = $result[2].IndexOf('A.A')
        $row2IdPos   = $result[3].IndexOf('Longer.Pkg.Id')
        $headerIdPos | Should Be $row1IdPos
        $headerIdPos | Should Be $row2IdPos
    }

    It 'handles single package' {
        $packages = @(
            [PSCustomObject]@{ Name = 'Git'; Id = 'Git.Git'; Version = '2.54.0'; Source = 'winget' }
        )
        $result = Format-WingetTable -Packages $packages
        $result.Count | Should Be 3
        $result[2]    | Should Match 'Git'
    }
}

Describe 'Invoke-Diff' {
    It 'reports missing packages' {
        $tempFile = New-TemporaryFile
        $content = @(
            'Name                  Id                         Version         Source',
            '--------------------------------------------------',
            'Git                   Git.Git                    2.54.0          winget',
            'Missing               Missing.Pkg                1.0.0           winget'
        ) -join "`n"
        Set-Content -Path $tempFile -Value $content -Encoding UTF8

        try {
            Mock -CommandName 'Get-InstalledPackages' {
                return @([PSCustomObject]@{ Name = 'Git'; Id = 'Git.Git'; Version = '2.54.0'; Source = 'winget' })
            }
            Mock -CommandName 'Write-Host'

            Invoke-Diff -FileName $tempFile.FullName

            Assert-MockCalled -CommandName 'Write-Host' -ParameterFilter { $Object -match 'In file' } -Scope It
        } finally {
            Remove-Item $tempFile -Force
        }
    }

    It 'reports extra installed packages' {
        $tempFile = New-TemporaryFile
        $content = @(
            'Name                  Id                         Version         Source',
            '--------------------------------------------------',
            'Git                   Git.Git                    2.54.0          winget'
        ) -join "`n"
        Set-Content -Path $tempFile -Value $content -Encoding UTF8

        try {
            Mock -CommandName 'Get-InstalledPackages' {
                return @(
                    [PSCustomObject]@{ Name = 'Git';   Id = 'Git.Git';       Version = '2.54.0'; Source = 'winget' },
                    [PSCustomObject]@{ Name = 'Extra'; Id = 'Extra.Package'; Version = '1.0.0';  Source = 'winget' }
                )
            }
            Mock -CommandName 'Write-Host'

            Invoke-Diff -FileName $tempFile.FullName

            Assert-MockCalled -CommandName 'Write-Host' -ParameterFilter { $Object -match 'Installed, not in file' } -Scope It
        } finally {
            Remove-Item $tempFile -Force
        }
    }

    It 'reports no differences when sets match' {
        $tempFile = New-TemporaryFile
        $content = @(
            'Name                  Id                         Version         Source',
            '--------------------------------------------------',
            'Git                   Git.Git                    2.54.0          winget'
        ) -join "`n"
        Set-Content -Path $tempFile -Value $content -Encoding UTF8

        try {
            Mock -CommandName 'Get-InstalledPackages' {
                return @([PSCustomObject]@{ Name = 'Git'; Id = 'Git.Git'; Version = '2.54.0'; Source = 'winget' })
            }
            Mock -CommandName 'Write-Host'

            Invoke-Diff -FileName $tempFile.FullName

            Assert-MockCalled -CommandName 'Write-Host' -ParameterFilter { $Object -match 'No differences' } -Scope It
        } finally {
            Remove-Item $tempFile -Force
        }
    }
}

Describe 'Invoke-Create' {
    It 'writes a fixed-width table file' {
        $outputFile = [System.IO.Path]::GetTempFileName() -replace '\.tmp$', '.wgl'
        Remove-Item $outputFile -Force -ErrorAction SilentlyContinue

        try {
            Mock -CommandName 'Get-InstalledPackages' {
                return @(
                    [PSCustomObject]@{ Name = 'Git';    Id = 'Git.Git';              Version = '2.54.0'; Source = 'winget' },
                    [PSCustomObject]@{ Name = 'Docker'; Id = 'Docker.DockerDesktop'; Version = '4.70.0'; Source = 'winget' }
                )
            }
            Mock -CommandName 'Write-Host'

            Invoke-Create -FileName $outputFile

            Test-Path $outputFile         | Should Be $true
            (Get-Content $outputFile -Raw) | Should Match 'Git\.Git'
            (Get-Content $outputFile -Raw) | Should Match 'Docker\.DockerDesktop'
        } finally {
            Remove-Item $outputFile -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Invoke-Install' {
    It 'cancels on user decline and does not invoke winget' {
        $tempFile = New-TemporaryFile
        $content = @(
            'Name                  Id                         Version         Source',
            '--------------------------------------------------',
            'Git                   Git.Git                    2.54.0          winget'
        ) -join "`n"
        Set-Content -Path $tempFile -Value $content -Encoding UTF8

        try {
            Mock -CommandName 'Write-Host'
            Mock -CommandName 'Read-Host' { return 'n' }
            Mock -CommandName 'winget'

            Invoke-Install -FileName $tempFile.FullName

            Assert-MockCalled -CommandName 'winget' -Times 0 -Scope It
        } finally {
            Remove-Item $tempFile -Force
        }
    }
}

Describe 'winget_sync.bat (black-box)' {
    It 'forwards -h flag and shows usage' {
        $output = & $batPath -h 2>&1
        ($output -join "`n") | Should Match 'Usage:'
        ($output -join "`n") | Should Match '--create'
    }

    It 'shows usage and exits non-zero when no args given' {
        $output = & $batPath 2>&1
        $LASTEXITCODE | Should Be 1
        ($output -join "`n") | Should Match 'Usage:'
    }
}

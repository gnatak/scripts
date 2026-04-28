# Load script functions (but not main logic)
. (Join-Path $PSScriptRoot 'wg_sync.ps1') *>&1 | Out-Null

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

            $result.Count | Should Be 2
            $result[0].Name | Should Be 'Git'
            $result[0].Id | Should Be 'Git.Git'
            $result[0].Version | Should Be '2.54.0'
            $result[0].Source | Should Be 'winget'
            $result[1].Name | Should Be 'Docker Desktop'
        }
        finally {
            Remove-Item $tempFile -Force
        }
    }

    It 'reads tab-delimited format' {
        $tempFile = New-TemporaryFile
        $content = @(
            'Git.Git	2.54.0	winget',
            'Docker.DockerDesktop	4.70.0	winget'
        ) -join "`n"
        Set-Content -Path $tempFile -Value $content -Encoding UTF8

        try {
            $result = Read-PackageFile -Path $tempFile.FullName

            $result.Count | Should Be 2
            $result[0].Id | Should Be 'Git.Git'
            $result[0].Version | Should Be '2.54.0'
            $result[0].Source | Should Be 'winget'
        }
        finally {
            Remove-Item $tempFile -Force
        }
    }

    It 'skips empty lines' {
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
        }
        finally {
            Remove-Item $tempFile -Force
        }
    }

    It 'handles files without separator line' {
        $tempFile = New-TemporaryFile
        $content = @(
            'Git.Git	2.54.0	winget',
            'Docker.DockerDesktop	4.70.0	winget'
        ) -join "`n"
        Set-Content -Path $tempFile -Value $content -Encoding UTF8

        try {
            $result = Read-PackageFile -Path $tempFile.FullName

            $result.Count | Should Be 2
        }
        finally {
            Remove-Item $tempFile -Force
        }
    }
}

Describe 'Format-WingetTable' {
    It 'formats packages with proper columns' {
        $packages = @(
            [PSCustomObject]@{ Name = 'Git'; Id = 'Git.Git'; Version = '2.54.0'; Source = 'winget' },
            [PSCustomObject]@{ Name = 'Docker'; Id = 'Docker.DockerDesktop'; Version = '4.70.0'; Source = 'winget' }
        )

        $result = Format-WingetTable -Packages $packages

        $result.Count | Should Be 4
        $result[0] | Should Match 'Name'
        $result[1] | Should Match '^-'
    }

    It 'handles single package' {
        $packages = @(
            [PSCustomObject]@{ Name = 'Git'; Id = 'Git.Git'; Version = '2.54.0'; Source = 'winget' }
        )

        $result = Format-WingetTable -Packages $packages

        $result.Count | Should Be 3
        $result[2] | Should Match 'Git'
    }
}

Describe 'Invoke-Diff' {
    It 'identifies missing packages' {
        $tempFile = New-TemporaryFile
        $content = @(
            'Name                  Id                         Version         Source',
            '--------------------------------------------------',
            'Git                   Git.Git                    2.54.0          winget',
            'Missing Package       Missing.Package            1.0.0           winget'
        ) -join "`n"
        Set-Content -Path $tempFile -Value $content -Encoding UTF8

        try {
            Mock -CommandName 'Get-InstalledPackages' {
                return @([PSCustomObject]@{ Name = 'Git'; Id = 'Git.Git'; Version = '2.54.0'; Source = 'winget' })
            }

            Mock -CommandName 'Write-Host'

            Invoke-Diff -FileName $tempFile.FullName

            Assert-MockCalled -CommandName 'Write-Host' -ParameterFilter { $Object -match 'In file' } -Scope It
        }
        finally {
            Remove-Item $tempFile -Force
        }
    }

    It 'identifies extra packages' {
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
                    [PSCustomObject]@{ Name = 'Git'; Id = 'Git.Git'; Version = '2.54.0'; Source = 'winget' },
                    [PSCustomObject]@{ Name = 'Extra'; Id = 'Extra.Package'; Version = '1.0.0'; Source = 'winget' }
                )
            }

            Mock -CommandName 'Write-Host'

            Invoke-Diff -FileName $tempFile.FullName

            Assert-MockCalled -CommandName 'Write-Host' -Times 1 -ParameterFilter { $Object -match 'Installed' } -Scope It
        }
        finally {
            Remove-Item $tempFile -Force
        }
    }

    It 'reports matching packages' {
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

            Assert-MockCalled -CommandName 'Write-Host' -Times 1 -ParameterFilter { $Object -match 'No differences' } -Scope It
        }
        finally {
            Remove-Item $tempFile -Force
        }
    }
}

Describe 'Invoke-Create' {
    It 'exports packages to file' {
        $outputFile = [System.IO.Path]::GetTempFileName() -replace '\.tmp$', '.wgl'
        Remove-Item $outputFile -Force -ErrorAction SilentlyContinue

        try {
            Mock -CommandName 'Get-InstalledPackages' {
                return @(
                    [PSCustomObject]@{ Name = 'Git'; Id = 'Git.Git'; Version = '2.54.0'; Source = 'winget' },
                    [PSCustomObject]@{ Name = 'Docker'; Id = 'Docker.DockerDesktop'; Version = '4.70.0'; Source = 'winget' }
                )
            }
            Mock -CommandName 'Write-Host'

            Invoke-Create -FileName $outputFile

            Test-Path $outputFile | Should Be $true
            (Get-Content $outputFile | Out-String) | Should Match 'Git'
        }
        finally {
            Remove-Item $outputFile -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Invoke-Install' {
    It 'shows packages to install' {
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

            Invoke-Install -FileName $tempFile.FullName

            Assert-MockCalled -CommandName 'Write-Host' -Times 1 -ParameterFilter { $Object -match 'Packages to install' } -Scope It
        }
        finally {
            Remove-Item $tempFile -Force
        }
    }

    It 'cancels on user decline' {
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

            Assert-MockCalled -CommandName 'winget' -Times 0
        }
        finally {
            Remove-Item $tempFile -Force
        }
    }
}

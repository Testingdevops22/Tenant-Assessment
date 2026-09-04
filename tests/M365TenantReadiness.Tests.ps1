$modulePath = Join-Path $PSScriptRoot '../src/M365TenantReadiness.psm1'
$samplePath = Join-Path $PSScriptRoot '../examples/sample-snapshot.json'
Import-Module $modulePath -Force

Describe 'M365 Tenant Readiness rules' {
    BeforeAll {
        $snapshot = Get-Content -Raw $samplePath | ConvertFrom-Json -Depth 100
        $findings = @(Get-M365ReadinessFindings -Snapshot $snapshot -StaleUserDays 90 -CredentialWarningDays 90)
    }

    It 'detects a license assignment error' {
        $findings.id | Should -Contain 'LIC-001'
    }

    It 'detects missing UsageLocation' {
        $findings.id | Should -Contain 'LIC-003'
    }

    It 'detects the mailbox and PDL mismatch' {
        $findings.id | Should -Contain 'GEO-003'
    }

    It 'does not treat report-only Conditional Access as enabled' {
        $findings.id | Should -Contain 'CMP-001'
    }

    It 'detects expired application credentials' {
        $findings.id | Should -Contain 'APP-001'
    }
}

Describe 'M365 Tenant Readiness renderer' {
    It 'renders the report and audit artifacts from an offline snapshot' {
        $target = Join-Path ([System.IO.Path]::GetTempPath()) ("mtr-{0}" -f [guid]::NewGuid())
        try {
            $result = Invoke-M365TenantReadiness -SnapshotPath $samplePath -OutputPath $target
            Test-Path $result.Report | Should -BeTrue
            Test-Path $result.Snapshot | Should -BeTrue
            Test-Path $result.Findings | Should -BeTrue
            Test-Path $result.LicenseAssignments | Should -BeTrue
            Test-Path $result.PdlUsers | Should -BeTrue
            (Get-Content -Raw $result.Report) | Should -Match 'Contoso \(Sample\)'
        }
        finally {
            if (Test-Path $target) { Remove-Item $target -Recurse -Force }
        }
    }
}

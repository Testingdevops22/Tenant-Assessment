function Invoke-M365TenantReadiness {
    [CmdletBinding(DefaultParameterSetName='Live')]
    param(
        [Parameter(ParameterSetName='Live')][string]$TenantId,
        [Parameter(ParameterSetName='Live')][string]$ClientId,
        [Parameter(ParameterSetName='Live')][string]$CertificateThumbprint,
        [Parameter(ParameterSetName='Live')][ValidateSet('Standard','Full')][string]$Profile = 'Standard',
        [Parameter(ParameterSetName='Live')][switch]$IncludeExchange,
        [Parameter(ParameterSetName='Live')][switch]$IncludeSharePoint,
        [Parameter(ParameterSetName='Live')][string]$SharePointAdminUrl,
        [Parameter(ParameterSetName='Live')][string]$ExchangeUserPrincipalName,
        [Parameter(ParameterSetName='Live')][switch]$UseDeviceCode,
        [Parameter(ParameterSetName='Live')][switch]$SkipConnect,
        [Parameter(Mandatory,ParameterSetName='Snapshot')][string]$SnapshotPath,
        [Parameter(Mandatory)][string]$OutputPath,
        [ValidateRange(1,3650)][int]$StaleUserDays = 90,
        [ValidateRange(1,3650)][int]$CredentialWarningDays = 90,
        [switch]$RedactIdentifiers
    )

    if ($PSCmdlet.ParameterSetName -eq 'Snapshot') {
        Write-MtrStatus "Loading offline snapshot '$SnapshotPath'..."
        if (-not (Test-Path $SnapshotPath)) { throw "Snapshot not found: $SnapshotPath" }
        $snapshot = Get-Content -Raw -Path $SnapshotPath | ConvertFrom-Json -Depth 100
    }
    else {
        Write-MtrStatus "Starting live tenant collection with the $Profile profile."
        $snapshot = Get-MtrSnapshot -TenantId $TenantId -ClientId $ClientId -CertificateThumbprint $CertificateThumbprint -Profile $Profile -IncludeExchange:$IncludeExchange -IncludeSharePoint:$IncludeSharePoint -SharePointAdminUrl $SharePointAdminUrl -ExchangeUserPrincipalName $ExchangeUserPrincipalName -UseDeviceCode:$UseDeviceCode -SkipConnect:$SkipConnect
    }

    if ($RedactIdentifiers) { $snapshot = Protect-MtrSnapshot -Snapshot $snapshot }
    Write-MtrStatus 'Evaluating readiness rules and writing report artifacts...'
    $findings = @(Get-M365ReadinessFindings -Snapshot $snapshot -StaleUserDays $StaleUserDays -CredentialWarningDays $CredentialWarningDays)
    if (-not (Test-Path $OutputPath)) { New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null }
    $snapshotFile = Join-Path $OutputPath 'tenant-snapshot.json'
    $findingsFile = Join-Path $OutputPath 'findings.csv'
    $licenseAssignmentsFile = Join-Path $OutputPath 'license-assignments.csv'
    $pdlUsersFile = Join-Path $OutputPath 'pdl-users.csv'
    $reportFile = Join-Path $OutputPath 'tenant-readiness-report.html'
    [System.IO.File]::WriteAllText($snapshotFile, ($snapshot | ConvertTo-Json -Depth 100), [System.Text.UTF8Encoding]::new($false))
    $findings | Select-Object id,severity,area,title,evidence,recommendation,affectedCount,@{Name='controlThemes';Expression={$_.controlThemes -join '; '}} | Export-Csv -Path $findingsFile -NoTypeInformation -Encoding utf8
    $licenseRows = @(Get-MtrLicenseExportRows -Snapshot $snapshot)
    Export-MtrCsv -Rows $licenseRows -Columns @('userPrincipalName','displayName','accountEnabled','usageLocation','preferredDataLocation','sku','assignmentSource','state','error','disabledPlanCount','lastSuccessfulSignIn') -Path $licenseAssignmentsFile
    $pdlRows = @(Get-MtrPdlExportRows -Snapshot $snapshot)
    Export-MtrCsv -Rows $pdlRows -Columns @('userPrincipalName','displayName','accountEnabled','identitySource','usageLocation','preferredDataLocation','mailboxRegion','mailboxRegionLastUpdateTime','databaseGeo','placementStatus') -Path $pdlUsersFile
    New-M365ReadinessReport -Snapshot $snapshot -Findings $findings -Path $reportFile | Out-Null
    Write-MtrStatus "Completed. Report: $reportFile"

    return [pscustomobject]@{
        Report             = (Resolve-Path $reportFile).Path
        Snapshot           = (Resolve-Path $snapshotFile).Path
        Findings           = (Resolve-Path $findingsFile).Path
        LicenseAssignments = (Resolve-Path $licenseAssignmentsFile).Path
        PdlUsers           = (Resolve-Path $pdlUsersFile).Path
        Summary            = [pscustomobject]@{
            Critical = @($findings | Where-Object severity -eq 'Critical').Count
            High     = @($findings | Where-Object severity -eq 'High').Count
            Medium   = @($findings | Where-Object severity -eq 'Medium').Count
            Review   = @($findings | Where-Object severity -eq 'Review').Count
            Info     = @($findings | Where-Object severity -eq 'Info').Count
        }
    }
}

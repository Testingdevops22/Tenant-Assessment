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
    [Parameter(ParameterSetName='Live')][switch]$SkipConnect,
    [Parameter(Mandatory,ParameterSetName='Snapshot')][string]$SnapshotPath,
    [string]$OutputPath = (Join-Path $PSScriptRoot ("report-{0}" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))),
    [ValidateRange(1,3650)][int]$StaleUserDays = 90,
    [ValidateRange(1,3650)][int]$CredentialWarningDays = 90,
    [switch]$RedactIdentifiers
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'src/M365TenantReadiness.psm1') -Force

$parameters = @{
    OutputPath               = $OutputPath
    StaleUserDays            = $StaleUserDays
    CredentialWarningDays    = $CredentialWarningDays
    RedactIdentifiers        = $RedactIdentifiers
}

if ($PSCmdlet.ParameterSetName -eq 'Snapshot') {
    $parameters.SnapshotPath = $SnapshotPath
}
else {
    $parameters.TenantId = $TenantId
    $parameters.ClientId = $ClientId
    $parameters.CertificateThumbprint = $CertificateThumbprint
    $parameters.Profile = $Profile
    $parameters.IncludeExchange = $IncludeExchange
    $parameters.IncludeSharePoint = $IncludeSharePoint
    $parameters.SharePointAdminUrl = $SharePointAdminUrl
    $parameters.ExchangeUserPrincipalName = $ExchangeUserPrincipalName
    $parameters.SkipConnect = $SkipConnect
}

$result = Invoke-M365TenantReadiness @parameters
$result | Format-List

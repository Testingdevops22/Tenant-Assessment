Set-StrictMode -Version Latest

$partsPath = Join-Path $PSScriptRoot 'parts'
Get-ChildItem -Path $partsPath -Filter '*-functions.ps1' -File |
    Sort-Object Name |
    ForEach-Object { . $_.FullName }

Export-ModuleMember -Function Invoke-M365TenantReadiness,Get-M365ReadinessFindings,New-M365ReadinessReport

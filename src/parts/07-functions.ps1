function New-M365ReadinessReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Snapshot,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Findings,
        [Parameter(Mandatory)][string]$Path
    )

    $tenant = Get-MtrProperty $Snapshot 'tenant'
    $organizationRows = ConvertTo-MtrArray (Get-MtrProperty $tenant 'organization')
    $organization = $organizationRows | Select-Object -First 1
    $tenantName = [string](Get-MtrProperty $organization 'displayName' 'Microsoft 365 tenant')
    $generated = [string](Get-MtrProperty $Snapshot 'generatedAtUtc' ([DateTime]::UtcNow.ToString('o')))
    $licensing = Get-MtrProperty $Snapshot 'licensing'
    $identity = Get-MtrProperty $Snapshot 'identity'
    $multiGeo = Get-MtrProperty $Snapshot 'multiGeo'
    $users = ConvertTo-MtrArray (Get-MtrProperty $licensing 'users')
    $groups = ConvertTo-MtrArray (Get-MtrProperty $licensing 'groups')
    $skus = ConvertTo-MtrArray (Get-MtrProperty $licensing 'subscribedSkus')
    $policies = ConvertTo-MtrArray (Get-MtrProperty $identity 'conditionalAccessPolicies')
    $collections = ConvertTo-MtrArray (Get-MtrProperty $Snapshot 'collection')
    $failedCount = @($collections | Where-Object { [string](Get-MtrProperty $_ 'status' '') -eq 'Failed' }).Count
    $licensedUsers = @($users | Where-Object { (ConvertTo-MtrArray (Get-MtrProperty $_ 'assignedLicenses')).Count -gt 0 })
    $pdlUsers = @($users | Where-Object { -not [string]::IsNullOrWhiteSpace([string](Get-MtrProperty $_ 'preferredDataLocation' '')) })
    $severityCounts = @{}
    foreach ($severity in @('Critical','High','Medium','Review','Info')) { $severityCounts[$severity] = @($Findings | Where-Object severity -eq $severity).Count }

    $findingRows = foreach ($finding in $Findings) {
        [pscustomobject]@{
            Severity=$finding.severity; Area=$finding.area; Finding=$finding.title
            Evidence=$finding.evidence; Recommendation=$finding.recommendation
        }
    }
    $licenseRows = foreach ($sku in $skus) {
        $enabled = Get-MtrEnabledUnits $sku
        $consumed = [int](Get-MtrProperty $sku 'consumedUnits' 0)
        [pscustomobject]@{ SKU=Get-MtrProperty $sku 'skuPartNumber' ''; Enabled=$enabled; Consumed=$consumed; Available=($enabled-$consumed); Status=Get-MtrProperty $sku 'capabilityStatus' '' }
    }
    $pdlRows = $users | Group-Object { $value=[string](Get-MtrProperty $_ 'preferredDataLocation' ''); if ($value) { $value } else { '(tenant default / blank)' } } | Sort-Object Count -Descending | ForEach-Object { [pscustomobject]@{ Location=$_.Name; Users=$_.Count } }
    $caRows = foreach ($policy in $policies) {
        [pscustomobject]@{
            Name=Get-MtrProperty $policy 'displayName' ''
            State=Get-MtrProperty $policy 'state' ''
            Created=Get-MtrProperty $policy 'createdDateTime' ''
            Modified=Get-MtrProperty $policy 'modifiedDateTime' ''
        }
    }
    $exchange = Get-MtrProperty $multiGeo 'exchange'
    $exchangeOrganizations = ConvertTo-MtrArray (Get-MtrProperty $exchange 'organization')
    $exchangeOrg = $exchangeOrganizations | Select-Object -First 1
    $exchangeMailboxes = ConvertTo-MtrArray (Get-MtrProperty $exchange 'mailboxes')
    $allowedRegions = (ConvertTo-MtrArray (Get-MtrProperty $exchangeOrg 'AllowedMailboxRegions')) -join ', '
    if (-not $allowedRegions) { $allowedRegions = 'Not collected or not configured' }
    $defaultRegion = [string](Get-MtrProperty $exchangeOrg 'DefaultMailboxRegion' 'Not collected')
    $mailboxRegionRows = $exchangeMailboxes | Group-Object { $value=[string](Get-MtrProperty $_ 'MailboxRegion' ''); if ($value) { $value } else { '(blank)' } } | Sort-Object Count -Descending | ForEach-Object { [pscustomobject]@{ Region=$_.Name; Mailboxes=$_.Count } }
    $sharePoint = Get-MtrProperty $multiGeo 'sharePoint'
    $sharePointGeoRows = ConvertTo-MtrArray (Get-MtrProperty $sharePoint 'geoStorageQuotas')

    $findingsTable = ConvertTo-MtrTable -Rows @($findingRows) -Columns @(
        @{Label='Severity';Property='Severity'}, @{Label='Area';Property='Area'}, @{Label='Finding';Property='Finding'},
        @{Label='Evidence';Property='Evidence'}, @{Label='Recommended action';Property='Recommendation'}
    ) -EmptyMessage 'No rule findings were produced.'
    $licensesTable = ConvertTo-MtrTable -Rows @($licenseRows) -Columns @(
        @{Label='SKU';Property='SKU'}, @{Label='Enabled';Property='Enabled'}, @{Label='Consumed';Property='Consumed'}, @{Label='Available';Property='Available'}, @{Label='State';Property='Status'}
    )
    $pdlTable = ConvertTo-MtrTable -Rows @($pdlRows) -Columns @(@{Label='Preferred data location';Property='Location'}, @{Label='Users';Property='Users'})
    $mailboxRegionTable = ConvertTo-MtrTable -Rows @($mailboxRegionRows) -Columns @(@{Label='Mailbox region';Property='Region'}, @{Label='Mailboxes';Property='Mailboxes'}) -EmptyMessage 'Exchange mailbox placement was not collected.'
    $sharePointGeoTable = ConvertTo-MtrTable -Rows @($sharePointGeoRows) -Columns @(
        @{Label='SharePoint geo';Script={ param($row) Get-MtrProperty $row 'GeoLocation' (Get-MtrProperty $row 'Location' '') }},
        @{Label='Allocated quota (MB)';Script={ param($row) Get-MtrProperty $row 'StorageQuotaMB' (Get-MtrProperty $row 'StorageQuota' '') }}
    ) -EmptyMessage 'SharePoint Multi-Geo quota data was not collected or is not configured.'
    $caTable = ConvertTo-MtrTable -Rows @($caRows) -Columns @(@{Label='Policy';Property='Name'}, @{Label='State';Property='State'}, @{Label='Created';Property='Created'}, @{Label='Modified';Property='Modified'})
    $collectionTable = ConvertTo-MtrTable -Rows @($collections) -Columns @(
        @{Label='Collection';Property='name'}, @{Label='Area';Property='area'}, @{Label='Status';Property='status'}, @{Label='Records';Property='count'},
        @{Label='Required read access';Script={ param($row) (ConvertTo-MtrArray (Get-MtrProperty $row 'permissions')) -join ', ' }}, @{Label='Error';Property='error'}
    )

    $html = @"
<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Microsoft 365 tenant readiness — $(ConvertTo-MtrHtml $tenantName)</title>
<style>
:root{--ink:#16233a;--muted:#61708a;--paper:#f5f7fb;--card:#fff;--line:#dce3ee;--brand:#3157d5;--critical:#951d35;--high:#c54132;--medium:#b56a00;--review:#4f6b8a;--info:#33768e}
*{box-sizing:border-box}body{margin:0;background:var(--paper);color:var(--ink);font:14px/1.48 Inter,Segoe UI,Arial,sans-serif}.page{max-width:1280px;margin:0 auto;padding:36px}.hero{padding:36px;border-radius:20px;background:linear-gradient(135deg,#142444,#3157d5);color:white;box-shadow:0 18px 60px #1c39732b}.eyebrow{text-transform:uppercase;letter-spacing:.12em;font-size:12px;opacity:.75}.hero h1{font-size:36px;line-height:1.15;margin:10px 0}.hero p{max-width:780px;margin:0;opacity:.86}.metrics{display:grid;grid-template-columns:repeat(6,1fr);gap:12px;margin:20px 0}.metric,.card{background:var(--card);border:1px solid var(--line);border-radius:14px;box-shadow:0 8px 24px #22365a0d}.metric{padding:18px}.metric strong{display:block;font-size:28px}.metric span{color:var(--muted);font-size:12px}.card{padding:22px;margin:16px 0}h2{font-size:22px;margin:0 0 6px}h3{font-size:16px;margin:20px 0 8px}.muted,.empty{color:var(--muted)}.callout{border-left:4px solid var(--brand);background:#eef3ff;padding:13px 16px;border-radius:8px;margin:14px 0}.geo{display:grid;grid-template-columns:repeat(3,1fr);gap:12px}.geo div{padding:14px;background:#f8faff;border:1px solid var(--line);border-radius:10px}.geo b{display:block;margin-bottom:4px}.table-wrap{overflow:auto;border:1px solid var(--line);border-radius:10px}table{width:100%;border-collapse:collapse;background:white}th,td{text-align:left;vertical-align:top;padding:10px 12px;border-bottom:1px solid var(--line)}th{background:#edf2fa;font-size:12px;text-transform:uppercase;letter-spacing:.04em}tr:last-child td{border-bottom:0}.badge{display:inline-block;color:white;border-radius:999px;padding:3px 9px;font-size:12px;margin:2px}.critical{background:var(--critical)}.high{background:var(--high)}.medium{background:var(--medium)}.review{background:var(--review)}.info{background:var(--info)}footer{color:var(--muted);font-size:12px;margin:28px 0}.print-note{float:right}@media(max-width:900px){.page{padding:16px}.metrics{grid-template-columns:repeat(2,1fr)}.geo{grid-template-columns:1fr}.hero h1{font-size:28px}}@media print{body{background:white}.page{max-width:none;padding:0}.hero,.metric,.card{box-shadow:none}.card{break-inside:avoid}.print-note{display:none}}
</style></head><body><main class="page">
<section class="hero"><div class="eyebrow">Read-only discovery report</div><h1>$(ConvertTo-MtrHtml $tenantName)</h1><p>Microsoft 365 tenant readiness, licensing, identity controls, applications, and Multi-Geo / Preferred Data Location evidence.</p><p class="print-note">Use your browser's Print → Save as PDF.</p></section>
<section class="metrics">
<div class="metric"><strong>$($users.Count)</strong><span>Users collected</span></div>
<div class="metric"><strong>$($licensedUsers.Count)</strong><span>Licensed users</span></div>
<div class="metric"><strong>$($groups.Count)</strong><span>Groups collected</span></div>
<div class="metric"><strong>$($skus.Count)</strong><span>Subscribed SKUs</span></div>
<div class="metric"><strong>$($pdlUsers.Count)</strong><span>Users with PDL</span></div>
<div class="metric"><strong>$failedCount</strong><span>Failed collections</span></div>
</section>
<section class="card"><h2>Executive findings</h2><p class="muted">Rules prioritize evidence for human review; they do not certify compliance.</p><p><span class="badge critical">Critical $($severityCounts.Critical)</span><span class="badge high">High $($severityCounts.High)</span><span class="badge medium">Medium $($severityCounts.Medium)</span><span class="badge review">Review $($severityCounts.Review)</span><span class="badge info">Info $($severityCounts.Info)</span></p>$findingsTable</section>
<section class="card"><h2>Licensing audit</h2><p class="muted">Purchased capacity, consumption, assignment health, UsageLocation, disabled accounts, and—when Full collection succeeds—stale licensed identities.</p>$licensesTable</section>
<section class="card"><h2>Multi-Geo and PDL</h2><div class="geo"><div><b>Exchange default mailbox region</b>$(ConvertTo-MtrHtml $defaultRegion)</div><div><b>Allowed mailbox regions</b>$(ConvertTo-MtrHtml $allowedRegions)</div><div><b>Mailbox evidence</b>$($exchangeMailboxes.Count) mailboxes collected</div></div><h3>User PDL distribution</h3>$pdlTable<h3>Exchange mailbox-region distribution</h3>$mailboxRegionTable<h3>SharePoint geo storage quotas</h3>$sharePointGeoTable<div class="callout">For synchronized identities, update PDL in the authoritative on-premises directory and let Entra Connect synchronize it. For cloud-only identities, Microsoft Graph can manage PDL. This tool never changes either.</div></section>
<section class="card"><h2>Conditional Access evidence</h2><p class="muted">Policy presence is not equivalent to effective coverage. Validate exclusions, workload identities, authentication strengths, and What If results during human review.</p>$caTable</section>
<section class="card"><h2>Collection status</h2><p class="muted">A failed or uncollected section is unknown, not empty. Endpoint and read-access hints are retained for troubleshooting.</p>$collectionTable</section>
<section class="card"><h2>Interpretation boundaries</h2><p>This report is a point-in-time configuration snapshot. It does not test end-user connectivity, DNS propagation, data-at-rest location for every workload, legal compliance, contractual license rights, or the effectiveness of operational processes. Validate high-impact findings with service owners before remediation.</p></section>
<footer>Generated $(ConvertTo-MtrHtml $generated) · M365 Tenant Readiness $($script:ToolVersion) · Local report artifact</footer>
</main></body></html>
"@
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    [System.IO.File]::WriteAllText($Path, $html, [System.Text.UTF8Encoding]::new($false))
    return (Resolve-Path $Path).Path
}

function Get-MtrLicenseExportRows {
    param([Parameter(Mandatory)][object]$Snapshot)

    $licensing = Get-MtrProperty $Snapshot 'licensing'
    $users = ConvertTo-MtrArray (Get-MtrProperty $licensing 'users')
    $skus = ConvertTo-MtrArray (Get-MtrProperty $licensing 'subscribedSkus')
    $skuMap = Get-MtrSkuMap -Skus $skus
    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($user in $users) {
        $states = ConvertTo-MtrArray (Get-MtrProperty $user 'licenseAssignmentStates')
        $assignedLicenses = ConvertTo-MtrArray (Get-MtrProperty $user 'assignedLicenses')
        $activity = Get-MtrProperty $user 'signInActivity'
        $lastSignIn = Get-MtrProperty $activity 'lastSuccessfulSignInDateTime' (Get-MtrProperty $activity 'lastSignInDateTime' '')
        if ($states.Count -gt 0) {
            foreach ($state in $states) {
                $skuId = [string](Get-MtrProperty $state 'skuId' '')
                $groupId = [string](Get-MtrProperty $state 'assignedByGroup' '')
                $skuName = if ($skuId -and $skuMap.ContainsKey($skuId.ToLowerInvariant())) { $skuMap[$skuId.ToLowerInvariant()] } else { $skuId }
                $rows.Add([pscustomobject]@{
                    userPrincipalName = Get-MtrProperty $user 'userPrincipalName' ''
                    displayName = Get-MtrProperty $user 'displayName' ''
                    accountEnabled = Get-MtrProperty $user 'accountEnabled' ''
                    usageLocation = Get-MtrProperty $user 'usageLocation' ''
                    preferredDataLocation = Get-MtrProperty $user 'preferredDataLocation' ''
                    sku = $skuName
                    assignmentSource = if ($groupId) { "Group:$groupId" } else { 'Direct' }
                    state = Get-MtrProperty $state 'state' ''
                    error = Get-MtrProperty $state 'error' ''
                    disabledPlanCount = (ConvertTo-MtrArray (Get-MtrProperty $state 'disabledPlans')).Count
                    lastSuccessfulSignIn = $lastSignIn
                })
            }
        }
        else {
            foreach ($license in $assignedLicenses) {
                $skuId = [string](Get-MtrProperty $license 'skuId' '')
                $skuName = if ($skuId -and $skuMap.ContainsKey($skuId.ToLowerInvariant())) { $skuMap[$skuId.ToLowerInvariant()] } else { $skuId }
                $rows.Add([pscustomobject]@{
                    userPrincipalName = Get-MtrProperty $user 'userPrincipalName' ''
                    displayName = Get-MtrProperty $user 'displayName' ''
                    accountEnabled = Get-MtrProperty $user 'accountEnabled' ''
                    usageLocation = Get-MtrProperty $user 'usageLocation' ''
                    preferredDataLocation = Get-MtrProperty $user 'preferredDataLocation' ''
                    sku = $skuName
                    assignmentSource = 'Unknown'
                    state = 'Unknown'
                    error = ''
                    disabledPlanCount = (ConvertTo-MtrArray (Get-MtrProperty $license 'disabledPlans')).Count
                    lastSuccessfulSignIn = $lastSignIn
                })
            }
        }
    }
    return @($rows)
}

function Get-MtrPdlExportRows {
    param([Parameter(Mandatory)][object]$Snapshot)

    $licensing = Get-MtrProperty $Snapshot 'licensing'
    $users = ConvertTo-MtrArray (Get-MtrProperty $licensing 'users')
    $multiGeo = Get-MtrProperty $Snapshot 'multiGeo'
    $exchange = Get-MtrProperty $multiGeo 'exchange'
    $mailboxes = ConvertTo-MtrArray (Get-MtrProperty $exchange 'mailboxes')
    $mailboxMap = @{}
    foreach ($mailbox in $mailboxes) {
        $upn = [string](Get-MtrProperty $mailbox 'UserPrincipalName' '')
        if ($upn) { $mailboxMap[$upn.ToLowerInvariant()] = $mailbox }
    }

    $rows = foreach ($user in $users) {
        $upn = [string](Get-MtrProperty $user 'userPrincipalName' '')
        $mailbox = if ($upn -and $mailboxMap.ContainsKey($upn.ToLowerInvariant())) { $mailboxMap[$upn.ToLowerInvariant()] } else { $null }
        $pdl = [string](Get-MtrProperty $user 'preferredDataLocation' '')
        $mailboxRegion = [string](Get-MtrProperty $mailbox 'MailboxRegion' '')
        $database = [string](Get-MtrProperty $mailbox 'Database' '')
        $databaseGeo = if ($database.Length -ge 3) { $database.Substring(0, 3) } else { '' }
        $placementStatus = if (-not $pdl) { 'Tenant default / blank PDL' } elseif (-not $mailboxRegion) { 'Mailbox evidence not collected' } elseif ($pdl -eq $mailboxRegion) { 'PDL and MailboxRegion aligned' } else { 'Review PDL / MailboxRegion mismatch' }
        [pscustomobject]@{
            userPrincipalName = $upn
            displayName = Get-MtrProperty $user 'displayName' ''
            accountEnabled = Get-MtrProperty $user 'accountEnabled' ''
            identitySource = if ([bool](Get-MtrProperty $user 'onPremisesSyncEnabled' $false)) { 'On-premises synchronized' } else { 'Cloud managed' }
            usageLocation = Get-MtrProperty $user 'usageLocation' ''
            preferredDataLocation = $pdl
            mailboxRegion = $mailboxRegion
            mailboxRegionLastUpdateTime = Get-MtrProperty $mailbox 'MailboxRegionLastUpdateTime' ''
            databaseGeo = $databaseGeo
            placementStatus = $placementStatus
        }
    }
    return @($rows)
}

function Export-MtrCsv {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Rows,
        [Parameter(Mandatory)][string[]]$Columns,
        [Parameter(Mandatory)][string]$Path
    )
    if ($Rows.Count -gt 0) {
        $Rows | Select-Object -Property $Columns | Export-Csv -Path $Path -NoTypeInformation -Encoding utf8
    }
    else {
        $header = '"' + ($Columns -join '","') + '"' + [Environment]::NewLine
        [System.IO.File]::WriteAllText($Path, $header, [System.Text.UTF8Encoding]::new($false))
    }
}

function Get-M365ReadinessFindings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Snapshot,
        [ValidateRange(1, 3650)][int]$StaleUserDays = 90,
        [ValidateRange(1, 3650)][int]$CredentialWarningDays = 90
    )

    $findings = [System.Collections.Generic.List[object]]::new()
    $now = [DateTime]::UtcNow
    $tenant = Get-MtrProperty $Snapshot 'tenant'
    $licensing = Get-MtrProperty $Snapshot 'licensing'
    $identity = Get-MtrProperty $Snapshot 'identity'
    $multiGeo = Get-MtrProperty $Snapshot 'multiGeo'
    $domains = ConvertTo-MtrArray (Get-MtrProperty $tenant 'domains')
    $users = ConvertTo-MtrArray (Get-MtrProperty $licensing 'users')
    $groups = ConvertTo-MtrArray (Get-MtrProperty $licensing 'groups')
    $skus = ConvertTo-MtrArray (Get-MtrProperty $licensing 'subscribedSkus')
    $skuMap = Get-MtrSkuMap -Skus $skus

    $customVerified = @($domains | Where-Object { (Get-MtrProperty $_ 'isVerified' $false) -and -not ([string](Get-MtrProperty $_ 'id' '')).EndsWith('.onmicrosoft.com') })
    if ($domains.Count -gt 0 -and $customVerified.Count -eq 0) {
        $findings.Add((New-MtrFinding -Id 'TEN-001' -Severity 'High' -Area 'Tenant readiness' -Title 'No verified custom domain discovered' -Evidence 'The domain collection did not contain a verified domain outside onmicrosoft.com.' -Recommendation 'Verify the production custom domain and its required DNS records before workload rollout.' -ControlThemes @('Tenant foundation','Service readiness')))
    }

    foreach ($sku in $skus) {
        $enabled = Get-MtrEnabledUnits $sku
        $consumed = [int](Get-MtrProperty $sku 'consumedUnits' 0)
        $available = $enabled - $consumed
        $name = [string](Get-MtrProperty $sku 'skuPartNumber' 'Unknown SKU')
        if ($enabled -gt 0 -and $available -lt 0) {
            $findings.Add((New-MtrFinding -Id "LIC-CAP-$name" -Severity 'Critical' -Area 'Licensing' -Title "$name is over allocated" -Evidence "$consumed licenses are consumed from $enabled enabled units." -Recommendation 'Reconcile subscription quantity and assignments immediately.' -AffectedCount ([Math]::Abs($available)) -ControlThemes @('License governance','Operational continuity')))
        }
        elseif ($enabled -gt 0 -and $available -le [Math]::Max(2, [Math]::Floor($enabled * 0.05))) {
            $findings.Add((New-MtrFinding -Id "LIC-LOW-$name" -Severity 'Medium' -Area 'Licensing' -Title "$name has low remaining capacity" -Evidence "$available of $enabled enabled units remain." -Recommendation 'Validate forecast demand and remove unused assignments or procure capacity.' -AffectedCount $available -ControlThemes @('License governance','Cost management')))
        }
    }

    $assignmentErrors = [System.Collections.Generic.List[object]]::new()
    $disabledLicensed = [System.Collections.Generic.List[object]]::new()
    $missingUsageLocation = [System.Collections.Generic.List[object]]::new()
    $staleLicensed = [System.Collections.Generic.List[object]]::new()
    foreach ($user in $users) {
        $assigned = ConvertTo-MtrArray (Get-MtrProperty $user 'assignedLicenses')
        $states = ConvertTo-MtrArray (Get-MtrProperty $user 'licenseAssignmentStates')
        $isLicensed = $assigned.Count -gt 0
        foreach ($state in $states) {
            $stateValue = [string](Get-MtrProperty $state 'state' '')
            $errorValue = [string](Get-MtrProperty $state 'error' '')
            if ($stateValue -in @('Error','ActiveWithError') -or -not [string]::IsNullOrWhiteSpace($errorValue)) { $assignmentErrors.Add([pscustomobject]@{ user=$user; state=$state }) }
        }
        if ($isLicensed -and -not [bool](Get-MtrProperty $user 'accountEnabled' $true)) { $disabledLicensed.Add($user) }
        if ($isLicensed -and [bool](Get-MtrProperty $user 'accountEnabled' $true) -and [string]::IsNullOrWhiteSpace([string](Get-MtrProperty $user 'usageLocation' ''))) { $missingUsageLocation.Add($user) }

        $activity = Get-MtrProperty $user 'signInActivity'
        if ($isLicensed -and [bool](Get-MtrProperty $user 'accountEnabled' $true) -and $null -ne $activity) {
            $last = ConvertTo-MtrDateTime (Get-MtrProperty $activity 'lastSuccessfulSignInDateTime')
            if ($null -eq $last) { $last = ConvertTo-MtrDateTime (Get-MtrProperty $activity 'lastSignInDateTime') }
            if ($null -eq $last -or $last -lt $now.AddDays(-$StaleUserDays)) { $staleLicensed.Add($user) }
        }
    }
    if ($assignmentErrors.Count -gt 0) {
        $findings.Add((New-MtrFinding -Id 'LIC-001' -Severity 'High' -Area 'Licensing' -Title 'License assignment errors detected' -Evidence "$($assignmentErrors.Count) user-license assignment states report an error." -Recommendation 'Review the assignment error, usage location, conflicting plans, and available capacity for each affected user.' -AffectedCount $assignmentErrors.Count -ControlThemes @('License governance','Joiner-mover-leaver')))
    }
    if ($disabledLicensed.Count -gt 0) {
        $findings.Add((New-MtrFinding -Id 'LIC-002' -Severity 'Medium' -Area 'Licensing' -Title 'Disabled accounts retain licenses' -Evidence "$($disabledLicensed.Count) disabled accounts have one or more assigned licenses." -Recommendation 'Validate retention requirements, then remove licenses that are no longer needed.' -AffectedCount $disabledLicensed.Count -ControlThemes @('Cost management','Joiner-mover-leaver')))
    }
    if ($missingUsageLocation.Count -gt 0) {
        $findings.Add((New-MtrFinding -Id 'LIC-003' -Severity 'High' -Area 'Licensing' -Title 'Licensed users are missing UsageLocation' -Evidence "$($missingUsageLocation.Count) enabled licensed users have no UsageLocation value." -Recommendation 'Set a valid two-letter usage location before changing or assigning licenses.' -AffectedCount $missingUsageLocation.Count -ControlThemes @('License readiness','Data quality')))
    }
    if ($staleLicensed.Count -gt 0) {
        $findings.Add((New-MtrFinding -Id 'LIC-004' -Severity 'Review' -Area 'Licensing' -Title 'Licensed accounts appear inactive' -Evidence "$($staleLicensed.Count) enabled licensed accounts have no successful sign-in within $StaleUserDays days or no recorded sign-in." -Recommendation 'Validate service, shared, new, and leave-of-absence accounts before reclaiming licenses.' -AffectedCount $staleLicensed.Count -ControlThemes @('Cost management','Access reviews')))
    }

    $policies = ConvertTo-MtrArray (Get-MtrProperty $identity 'conditionalAccessPolicies')
    $enabledPolicies = @($policies | Where-Object { [string](Get-MtrProperty $_ 'state' '') -ieq 'enabled' })
    if ($policies.Count -gt 0 -and $enabledPolicies.Count -eq 0) {
        $findings.Add((New-MtrFinding -Id 'CMP-001' -Severity 'High' -Area 'Identity controls' -Title 'No enabled Conditional Access policies discovered' -Evidence "$($policies.Count) policies were collected, but none are enabled." -Recommendation 'Design, test in report-only mode, and enable a Conditional Access baseline with emergency-access exclusions.' -ControlThemes @('Access control','Zero Trust')))
    }
    elseif ($policies.Count -gt 0) {
        $broadMfa = @($enabledPolicies | Where-Object { (Test-MtrPolicyHasControl $_ 'mfa') -and (Test-MtrPolicyTargetsBroadUsers $_) })
        if ($broadMfa.Count -eq 0) {
            $findings.Add((New-MtrFinding -Id 'CMP-002' -Severity 'High' -Area 'Identity controls' -Title 'No broad enabled MFA policy detected' -Evidence 'No enabled Conditional Access policy both targets All users and requires the built-in MFA grant control.' -Recommendation 'Review the complete policy set and ensure MFA coverage for users and administrators, with documented exclusions.' -ControlThemes @('Strong authentication','Access control')))
        }
        $legacyBlocks = @($enabledPolicies | Where-Object {
            if (-not (Test-MtrPolicyHasControl $_ 'block')) { return $false }
            $conditions = Get-MtrProperty $_ 'conditions'
            $apps = ConvertTo-MtrArray (Get-MtrProperty $conditions 'clientAppTypes')
            return @($apps | Where-Object { [string]$_ -in @('exchangeActiveSync','other') }).Count -gt 0
        })
        if ($legacyBlocks.Count -eq 0) {
            $findings.Add((New-MtrFinding -Id 'CMP-003' -Severity 'Medium' -Area 'Identity controls' -Title 'No enabled legacy-authentication block detected' -Evidence 'The collected enabled policies did not contain a block control for Exchange ActiveSync or other legacy clients.' -Recommendation 'Confirm legacy authentication is blocked through Conditional Access or an equivalent workload control.' -ControlThemes @('Strong authentication','Attack surface reduction')))
        }
    }

    $roleDefinitions = ConvertTo-MtrArray (Get-MtrProperty $identity 'roleDefinitions')
    $roleAssignments = ConvertTo-MtrArray (Get-MtrProperty $identity 'roleAssignments')
    $globalRole = $roleDefinitions | Where-Object { [string](Get-MtrProperty $_ 'displayName' '') -eq 'Global Administrator' } | Select-Object -First 1
    if ($null -ne $globalRole) {
        $globalRoleId = [string](Get-MtrProperty $globalRole 'id' '')
        $globalAssignments = @($roleAssignments | Where-Object { [string](Get-MtrProperty $_ 'roleDefinitionId' '') -eq $globalRoleId })
        if ($globalAssignments.Count -lt 2) {
            $findings.Add((New-MtrFinding -Id 'TEN-002' -Severity 'High' -Area 'Privileged access' -Title 'Fewer than two active Global Administrator assignments discovered' -Evidence "$($globalAssignments.Count) active tenant-wide assignment(s) were collected. PIM-eligible assignments are not counted by this MVP." -Recommendation 'Confirm at least two cloud-only emergency-access accounts exist and are monitored; separately review PIM eligibility.' -AffectedCount $globalAssignments.Count -ControlThemes @('Resilience','Privileged access')))
        }
        elseif ($globalAssignments.Count -gt 5) {
            $findings.Add((New-MtrFinding -Id 'TEN-003' -Severity 'Review' -Area 'Privileged access' -Title 'Large number of active Global Administrator assignments' -Evidence "$($globalAssignments.Count) active tenant-wide assignments were collected." -Recommendation 'Validate least privilege and move standing access to narrower roles or eligible PIM assignments where licensed.' -AffectedCount $globalAssignments.Count -ControlThemes @('Least privilege','Privileged access')))
        }
    }

    $credentials = [System.Collections.Generic.List[object]]::new()
    foreach ($kind in @('applications','servicePrincipals')) {
        foreach ($app in (ConvertTo-MtrArray (Get-MtrProperty $identity $kind))) {
            foreach ($credentialType in @('passwordCredentials','keyCredentials')) {
                foreach ($credential in (ConvertTo-MtrArray (Get-MtrProperty $app $credentialType))) {
                    $end = ConvertTo-MtrDateTime (Get-MtrProperty $credential 'endDateTime')
                    if ($null -ne $end -and $end -le $now.AddDays($CredentialWarningDays)) {
                        $credentials.Add([pscustomobject]@{ app=$app; credential=$credential; type=$credentialType; end=$end })
                    }
                }
            }
        }
    }
    $expired = @($credentials | Where-Object { $_.end -lt $now })
    $expiring = @($credentials | Where-Object { $_.end -ge $now })
    if ($expired.Count -gt 0) {
        $findings.Add((New-MtrFinding -Id 'APP-001' -Severity 'High' -Area 'Applications' -Title 'Expired application credentials discovered' -Evidence "$($expired.Count) password or certificate credentials are past their end date." -Recommendation 'Confirm whether each application is active, rotate required credentials, and remove obsolete credentials and applications.' -AffectedCount $expired.Count -ControlThemes @('Credential hygiene','Application governance')))
    }
    if ($expiring.Count -gt 0) {
        $findings.Add((New-MtrFinding -Id 'APP-002' -Severity 'Medium' -Area 'Applications' -Title 'Application credentials nearing expiry' -Evidence "$($expiring.Count) password or certificate credentials expire within $CredentialWarningDays days." -Recommendation 'Assign owners and rotate credentials before expiry; prefer managed identities or federated credentials when supported.' -AffectedCount $expiring.Count -ControlThemes @('Credential hygiene','Operational continuity')))
    }

    $exchange = Get-MtrProperty $multiGeo 'exchange'
    $exchangeOrganizations = ConvertTo-MtrArray (Get-MtrProperty $exchange 'organization')
    $mailboxes = ConvertTo-MtrArray (Get-MtrProperty $exchange 'mailboxes')
    $allowedRegions = [System.Collections.Generic.List[string]]::new()
    foreach ($organization in $exchangeOrganizations) {
        foreach ($region in (ConvertTo-MtrArray (Get-MtrProperty $organization 'AllowedMailboxRegions'))) {
            $regionText = [string]$region
            if ($regionText -and -not $allowedRegions.Contains($regionText)) { $allowedRegions.Add($regionText) }
        }
    }
    $usersWithPdl = @($users | Where-Object { -not [string]::IsNullOrWhiteSpace([string](Get-MtrProperty $_ 'preferredDataLocation' '')) })
    $multiGeoDetected = $allowedRegions.Count -gt 1 -or $usersWithPdl.Count -gt 0
    if ($multiGeoDetected) {
        $licensedMissingPdl = @($users | Where-Object {
            (ConvertTo-MtrArray (Get-MtrProperty $_ 'assignedLicenses')).Count -gt 0 -and
            [string]::IsNullOrWhiteSpace([string](Get-MtrProperty $_ 'preferredDataLocation' ''))
        })
        if ($licensedMissingPdl.Count -gt 0) {
            $findings.Add((New-MtrFinding -Id 'GEO-001' -Severity 'Medium' -Area 'Multi-Geo / PDL' -Title 'Licensed users are missing PreferredDataLocation' -Evidence "$($licensedMissingPdl.Count) licensed users have no PDL while Multi-Geo indicators are present. A blank PDL normally uses the tenant default geo." -Recommendation 'Confirm whether default-geo placement is intentional and populate PDL from the authoritative identity source where required.' -AffectedCount $licensedMissingPdl.Count -ControlThemes @('Data residency','Identity data quality')))
        }
        if ($allowedRegions.Count -gt 0) {
            $invalidPdl = @($usersWithPdl | Where-Object { -not $allowedRegions.Contains([string](Get-MtrProperty $_ 'preferredDataLocation' '')) })
            if ($invalidPdl.Count -gt 0) {
                $findings.Add((New-MtrFinding -Id 'GEO-002' -Severity 'High' -Area 'Multi-Geo / PDL' -Title 'PDL values fall outside Exchange allowed mailbox regions' -Evidence "$($invalidPdl.Count) users have PDL values not present in: $($allowedRegions -join ', ')." -Recommendation 'Validate geo codes and the tenant Multi-Geo entitlement before provisioning or moving workloads.' -AffectedCount $invalidPdl.Count -ControlThemes @('Data residency','Configuration integrity')))
            }
        }
        if ($mailboxes.Count -gt 0) {
            $mailboxMap = @{}
            foreach ($mailbox in $mailboxes) {
                $upn = [string](Get-MtrProperty $mailbox 'UserPrincipalName' '')
                if ($upn) { $mailboxMap[$upn.ToLowerInvariant()] = $mailbox }
            }
            $mismatches = [System.Collections.Generic.List[object]]::new()
            foreach ($user in $usersWithPdl) {
                $upn = [string](Get-MtrProperty $user 'userPrincipalName' '')
                if ($upn -and $mailboxMap.ContainsKey($upn.ToLowerInvariant())) {
                    $mailbox = $mailboxMap[$upn.ToLowerInvariant()]
                    $mailboxRegion = [string](Get-MtrProperty $mailbox 'MailboxRegion' '')
                    $pdl = [string](Get-MtrProperty $user 'preferredDataLocation' '')
                    if ($mailboxRegion -and $pdl -and $mailboxRegion -ne $pdl) { $mismatches.Add([pscustomobject]@{ user=$user; mailbox=$mailbox }) }
                }
            }
            if ($mismatches.Count -gt 0) {
                $findings.Add((New-MtrFinding -Id 'GEO-003' -Severity 'Review' -Area 'Multi-Geo / PDL' -Title 'MailboxRegion and PreferredDataLocation differ' -Evidence "$($mismatches.Count) mailboxes have a MailboxRegion that differs from the user's PDL. A move may be pending or failed." -Recommendation 'Check move status and workload provisioning before changing PDL again.' -AffectedCount $mismatches.Count -ControlThemes @('Data residency','Operational assurance')))
            }

            $databaseMismatches = @($mailboxes | Where-Object {
                $mailboxRegion = [string](Get-MtrProperty $_ 'MailboxRegion' '')
                $database = [string](Get-MtrProperty $_ 'Database' '')
                $databaseGeo = if ($database.Length -ge 3) { $database.Substring(0, 3) } else { '' }
                $mailboxRegion -and $databaseGeo -and $mailboxRegion -ne $databaseGeo
            })
            if ($databaseMismatches.Count -gt 0) {
                $findings.Add((New-MtrFinding -Id 'GEO-005' -Severity 'Review' -Area 'Multi-Geo / PDL' -Title 'Mailbox database geo and MailboxRegion differ' -Evidence "$($databaseMismatches.Count) mailbox database names begin with a geo code different from MailboxRegion. Exchange may have queued relocation." -Recommendation 'Review mailbox relocation state and wait for a confirmed move outcome before making another placement change.' -AffectedCount $databaseMismatches.Count -ControlThemes @('Data residency','Operational assurance')))
            }
        }
        $unifiedGroups = @($groups | Where-Object { (ConvertTo-MtrArray (Get-MtrProperty $_ 'groupTypes')) -contains 'Unified' })
        $groupsMissingPdl = @($unifiedGroups | Where-Object { [string]::IsNullOrWhiteSpace([string](Get-MtrProperty $_ 'preferredDataLocation' '')) })
        if ($groupsMissingPdl.Count -gt 0) {
            $findings.Add((New-MtrFinding -Id 'GEO-004' -Severity 'Review' -Area 'Multi-Geo / PDL' -Title 'Microsoft 365 groups use no explicit PDL' -Evidence "$($groupsMissingPdl.Count) Unified groups have no PreferredDataLocation value." -Recommendation 'Confirm group workload placement is correct; a blank group PDL may be expected when default-geo placement is intended.' -AffectedCount $groupsMissingPdl.Count -ControlThemes @('Data residency','Collaboration governance')))
        }
    }
    else {
        $findings.Add((New-MtrFinding -Id 'GEO-000' -Severity 'Info' -Area 'Multi-Geo / PDL' -Title 'No Multi-Geo indicators discovered in core data' -Evidence 'No user PDL values or multiple Exchange allowed mailbox regions were collected.' -Recommendation 'If Multi-Geo is expected, rerun with -IncludeExchange and confirm the tenant entitlement and workload configuration.' -ControlThemes @('Data residency')))
    }

    $collectionRows = ConvertTo-MtrArray (Get-MtrProperty $Snapshot 'collection')
    $failed = @($collectionRows | Where-Object { [string](Get-MtrProperty $_ 'status' '') -eq 'Failed' })
    if ($failed.Count -gt 0) {
        $names = @($failed | ForEach-Object { [string](Get-MtrProperty $_ 'name' '') }) -join ', '
        $findings.Add((New-MtrFinding -Id 'COL-001' -Severity 'Review' -Area 'Collection quality' -Title 'One or more evidence collections failed' -Evidence "$($failed.Count) collection(s) failed: $names." -Recommendation 'Review the report collection-status section, grant only the listed read permissions that are needed, and rerun.' -AffectedCount $failed.Count -ControlThemes @('Evidence quality')))
    }

    $severityOrder = @{ Critical=0; High=1; Medium=2; Review=3; Info=4 }
    return @($findings | Sort-Object @{ Expression={ $severityOrder[[string]$_.severity] } }, area, id)
}

function Get-MtrSnapshot {
    param(
        [string]$TenantId,
        [string]$ClientId,
        [string]$CertificateThumbprint,
        [ValidateSet('Standard','Full')][string]$Profile = 'Standard',
        [switch]$IncludeExchange,
        [switch]$IncludeSharePoint,
        [string]$SharePointAdminUrl,
        [string]$ExchangeUserPrincipalName,
        [switch]$UseDeviceCode,
        [switch]$SkipConnect
    )

    $scopes = [System.Collections.Generic.List[string]]::new()
    @(
        'User.Read.All', 'Group.Read.All', 'Organization.Read.All', 'Domain.Read.All',
        'LicenseAssignment.Read.All', 'Policy.Read.All', 'Policy.Read.AuthenticationMethod',
        'RoleManagement.Read.Directory', 'Application.Read.All'
    ) | ForEach-Object { $scopes.Add($_) }
    if ($Profile -eq 'Full') {
        $scopes.Add('AuditLog.Read.All')
        $scopes.Add('SecurityEvents.Read.All')
    }

    $context = Connect-MtrGraph -TenantId $TenantId -ClientId $ClientId -CertificateThumbprint $CertificateThumbprint -Scopes @($scopes) -UseDeviceCode:$UseDeviceCode -SkipConnect:$SkipConnect
    $manifest = [System.Collections.Generic.List[object]]::new()
    $data = @{}

    $requests = @(
        @{ Key='organization'; Name='Organization'; Area='Tenant'; Uri='/v1.0/organization?$select=id,displayName,createdDateTime,tenantType,countryLetterCode,defaultUsageLocation,onPremisesSyncEnabled,technicalNotificationMails,verifiedDomains'; Permissions=@('Organization.Read.All') },
        @{ Key='domains'; Name='Domains'; Area='Tenant'; Uri='/v1.0/domains'; Permissions=@('Domain.Read.All') },
        @{ Key='subscribedSkus'; Name='Subscribed SKUs'; Area='Licensing'; Uri='/v1.0/subscribedSkus'; Permissions=@('LicenseAssignment.Read.All') },
        @{ Key='users'; Name='Users and license assignments'; Area='Licensing'; Uri='/v1.0/users?$select=id,displayName,userPrincipalName,userType,accountEnabled,createdDateTime,usageLocation,preferredDataLocation,onPremisesSyncEnabled,assignedLicenses,licenseAssignmentStates&$top=999'; Permissions=@('User.Read.All','LicenseAssignment.Read.All') },
        @{ Key='groups'; Name='Groups and group licensing'; Area='Licensing'; Uri='/v1.0/groups?$select=id,displayName,mail,groupTypes,mailEnabled,securityEnabled,visibility,preferredDataLocation,assignedLicenses&$top=999'; Permissions=@('Group.Read.All','LicenseAssignment.Read.All') },
        @{ Key='conditionalAccessPolicies'; Name='Conditional Access policies'; Area='Compliance'; Uri='/v1.0/identity/conditionalAccess/policies'; Permissions=@('Policy.Read.All') },
        @{ Key='namedLocations'; Name='Conditional Access named locations'; Area='Compliance'; Uri='/v1.0/identity/conditionalAccess/namedLocations'; Permissions=@('Policy.Read.All') },
        @{ Key='authenticationMethodsPolicy'; Name='Authentication methods policy'; Area='Compliance'; Uri='/v1.0/policies/authenticationMethodsPolicy'; Permissions=@('Policy.Read.AuthenticationMethod') },
        @{ Key='authorizationPolicy'; Name='Authorization policy'; Area='Tenant'; Uri='/v1.0/policies/authorizationPolicy'; Permissions=@('Policy.Read.All') },
        @{ Key='roleDefinitions'; Name='Directory role definitions'; Area='Tenant'; Uri='/v1.0/roleManagement/directory/roleDefinitions?$select=id,displayName,isBuiltIn,isEnabled'; Permissions=@('RoleManagement.Read.Directory') },
        @{ Key='roleAssignments'; Name='Active directory role assignments'; Area='Tenant'; Uri='/v1.0/roleManagement/directory/roleAssignments?$select=id,principalId,roleDefinitionId,directoryScopeId'; Permissions=@('RoleManagement.Read.Directory') },
        @{ Key='applications'; Name='Application registrations'; Area='Tenant'; Uri='/v1.0/applications?$select=id,appId,displayName,createdDateTime,signInAudience,keyCredentials,passwordCredentials&$top=999'; Permissions=@('Application.Read.All') },
        @{ Key='servicePrincipals'; Name='Enterprise applications'; Area='Tenant'; Uri='/v1.0/servicePrincipals?$select=id,appId,displayName,accountEnabled,servicePrincipalType,appOwnerOrganizationId,createdDateTime,keyCredentials,passwordCredentials&$top=999'; Permissions=@('Application.Read.All') }
    )

    foreach ($request in $requests) {
        Write-MtrStatus "Collecting $($request.Name)..."
        $collection = Get-MtrGraphCollection -Name $request.Name -Area $request.Area -Uri $request.Uri -Permissions $request.Permissions
        Add-MtrCollectionResult -Manifest $manifest -Result $collection
        $data[$request.Key] = @($collection.Items)
        Write-MtrStatus "$($request.Name): $($collection.Status) ($($collection.Count) records)."
    }

    if ($Profile -eq 'Full') {
        Write-MtrStatus 'Collecting user sign-in activity...'
        $signIns = Get-MtrGraphCollection -Name 'User sign-in activity' -Area 'Compliance' -Uri '/v1.0/users?$select=id,userPrincipalName,signInActivity&$top=500' -Permissions @('User.Read.All','AuditLog.Read.All') -Optional
        Add-MtrCollectionResult -Manifest $manifest -Result $signIns
        if ($signIns.Status -eq 'Complete') { $data.users = @(Merge-MtrSignInActivity -Users @($data.users) -SignInRows @($signIns.Items)) }

        Write-MtrStatus "User sign-in activity: $($signIns.Status) ($($signIns.Count) records)."
        Write-MtrStatus 'Collecting Microsoft Secure Score...'
        $secureScore = Get-MtrGraphCollection -Name 'Microsoft Secure Score' -Area 'Compliance' -Uri '/v1.0/security/secureScores?$top=1' -Permissions @('SecurityEvents.Read.All') -Optional
        Add-MtrCollectionResult -Manifest $manifest -Result $secureScore
        $data.secureScores = @($secureScore.Items)
        Write-MtrStatus "Microsoft Secure Score: $($secureScore.Status) ($($secureScore.Count) records)."
    }
    else { $data.secureScores = @() }

    $exchange = [ordered]@{ organization=@(); mailboxes=@() }
    if ($IncludeExchange) {
        Write-MtrStatus 'Collecting Exchange Online Multi-Geo evidence...'
        $exchange = Get-MtrExchangeEvidence -Manifest $manifest -UserPrincipalName $ExchangeUserPrincipalName -SkipConnect:$SkipConnect
    }
    $sharePoint = [ordered]@{ tenant=@(); geoStorageQuotas=@() }
    if ($IncludeSharePoint) {
        if ([string]::IsNullOrWhiteSpace($SharePointAdminUrl)) { throw '-IncludeSharePoint requires -SharePointAdminUrl (for example, https://contoso-admin.sharepoint.com).' }
        Write-MtrStatus 'Collecting SharePoint Online Multi-Geo evidence...'
        $sharePoint = Get-MtrSharePointEvidence -Manifest $manifest -AdminUrl $SharePointAdminUrl -SkipConnect:$SkipConnect
    }

    return [ordered]@{
        schemaVersion     = '1.0'
        toolVersion       = $script:ToolVersion
        generatedAtUtc    = [DateTime]::UtcNow.ToString('o')
        collectionProfile = $Profile
        graphContext      = [ordered]@{ tenantId=$context.TenantId; account=$context.Account; authType=$context.AuthType }
        tenant            = [ordered]@{ organization=@($data.organization); domains=@($data.domains) }
        licensing         = [ordered]@{ subscribedSkus=@($data.subscribedSkus); users=@($data.users); groups=@($data.groups) }
        identity          = [ordered]@{
            conditionalAccessPolicies=@($data.conditionalAccessPolicies)
            namedLocations=@($data.namedLocations)
            authenticationMethodsPolicy=@($data.authenticationMethodsPolicy)
            authorizationPolicy=@($data.authorizationPolicy)
            roleDefinitions=@($data.roleDefinitions)
            roleAssignments=@($data.roleAssignments)
            applications=@($data.applications)
            servicePrincipals=@($data.servicePrincipals)
            secureScores=@($data.secureScores)
        }
        multiGeo          = [ordered]@{ exchange=$exchange; sharePoint=$sharePoint }
        collection        = @($manifest)
    }
}

function Connect-MtrGraph {
    param(
        [string]$TenantId,
        [string]$ClientId,
        [string]$CertificateThumbprint,
        [string[]]$Scopes,
        [switch]$UseDeviceCode,
        [switch]$SkipConnect
    )

    Write-MtrStatus 'Checking Microsoft Graph PowerShell...'
    if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication)) {
        throw 'Microsoft.Graph.Authentication is required. Install it with: Install-Module Microsoft.Graph.Authentication -Scope CurrentUser'
    }
    Import-Module Microsoft.Graph.Authentication -ErrorAction Stop

    if ($SkipConnect) {
        Write-MtrStatus 'Using the existing Microsoft Graph session.'
        $context = Get-MgContext
        if ($null -eq $context) { throw '-SkipConnect was specified, but no Microsoft Graph context is active.' }
        return $context
    }

    if (-not [string]::IsNullOrWhiteSpace($CertificateThumbprint)) {
        if ([string]::IsNullOrWhiteSpace($ClientId) -or [string]::IsNullOrWhiteSpace($TenantId)) {
            throw 'Certificate authentication requires -ClientId and -TenantId.'
        }
        Write-MtrStatus "Connecting to Microsoft Graph with certificate authentication for tenant '$TenantId'..."
        Connect-MgGraph -TenantId $TenantId -ClientId $ClientId -CertificateThumbprint $CertificateThumbprint -NoWelcome | Out-Null
    }
    else {
        $parameters = @{ Scopes = $Scopes; NoWelcome = $true }
        if (-not [string]::IsNullOrWhiteSpace($TenantId)) { $parameters.TenantId = $TenantId }
        if (-not [string]::IsNullOrWhiteSpace($ClientId)) { $parameters.ClientId = $ClientId }
        if ($UseDeviceCode) {
            $parameters.UseDeviceCode = $true
            Write-MtrStatus 'Starting device-code sign-in. Follow the URL and code shown below.'
        }
        else {
            Write-MtrStatus 'Opening Microsoft sign-in. Check your browser if this terminal appears to pause.'
        }
        Connect-MgGraph @parameters | Out-Null
    }
    $context = Get-MgContext
    Write-MtrStatus "Connected to tenant '$($context.TenantId)' as '$($context.Account)'."
    return $context
}

function Get-MtrExchangeEvidence {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Manifest,
        [string]$UserPrincipalName,
        [switch]$SkipConnect
    )

    $result = [ordered]@{ organization = @(); mailboxes = @() }
    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        if (-not (Get-Module -ListAvailable -Name ExchangeOnlineManagement)) {
            throw 'ExchangeOnlineManagement is not installed.'
        }
        Import-Module ExchangeOnlineManagement -ErrorAction Stop
        if (-not $SkipConnect) {
            $connect = @{ ShowBanner = $false }
            if (-not [string]::IsNullOrWhiteSpace($UserPrincipalName)) { $connect.UserPrincipalName = $UserPrincipalName }
            Connect-ExchangeOnline @connect | Out-Null
        }

        $organization = Get-OrganizationConfig | Select-Object Name,DefaultMailboxRegion,AllowedMailboxRegions
        $mailboxes = @(Get-Mailbox -ResultSize Unlimited |
            Select-Object DisplayName,UserPrincipalName,PrimarySmtpAddress,ExternalDirectoryObjectId,MailboxRegion,MailboxRegionLastUpdateTime,Database,ArchiveDatabase,RecipientTypeDetails)
        $result.organization = @($organization)
        $result.mailboxes = $mailboxes
        $timer.Stop()
        $Manifest.Add([pscustomobject]@{ name='Exchange Multi-Geo'; area='Multi-Geo'; endpoint='Exchange Online PowerShell'; permissions=@('View-Only Recipients','View-Only Configuration'); optional=$true; status='Complete'; count=$mailboxes.Count; durationMs=$timer.ElapsedMilliseconds; error=$null })
    }
    catch {
        $timer.Stop()
        $Manifest.Add([pscustomobject]@{ name='Exchange Multi-Geo'; area='Multi-Geo'; endpoint='Exchange Online PowerShell'; permissions=@('View-Only Recipients','View-Only Configuration'); optional=$true; status='Failed'; count=0; durationMs=$timer.ElapsedMilliseconds; error=$_.Exception.Message })
    }
    return $result
}

function Get-MtrSharePointEvidence {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Manifest,
        [Parameter(Mandatory)][string]$AdminUrl,
        [switch]$SkipConnect
    )

    $result = [ordered]@{ tenant = @(); geoStorageQuotas = @() }
    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        if (-not (Get-Module -ListAvailable -Name Microsoft.Online.SharePoint.PowerShell)) {
            throw 'Microsoft.Online.SharePoint.PowerShell is not installed.'
        }
        Import-Module Microsoft.Online.SharePoint.PowerShell -ErrorAction Stop
        if (-not $SkipConnect) { Connect-SPOService -Url $AdminUrl }
        $result.tenant = @(Get-SPOTenant | Select-Object StorageQuota,StorageQuotaAllocated,OneDriveStorageQuota,SharingCapability,ConditionalAccessPolicy,DefaultSharingLinkType)
        try { $result.geoStorageQuotas = @(Get-SPOGeoStorageQuota -AllLocations) } catch { $result.geoStorageQuotas = @() }
        $timer.Stop()
        $Manifest.Add([pscustomobject]@{ name='SharePoint Multi-Geo'; area='Multi-Geo'; endpoint='SharePoint Online PowerShell'; permissions=@('SharePoint Administrator or Global Reader'); optional=$true; status='Complete'; count=$result.geoStorageQuotas.Count; durationMs=$timer.ElapsedMilliseconds; error=$null })
    }
    catch {
        $timer.Stop()
        $Manifest.Add([pscustomobject]@{ name='SharePoint Multi-Geo'; area='Multi-Geo'; endpoint='SharePoint Online PowerShell'; permissions=@('SharePoint Administrator or Global Reader'); optional=$true; status='Failed'; count=0; durationMs=$timer.ElapsedMilliseconds; error=$_.Exception.Message })
    }
    return $result
}

function Merge-MtrSignInActivity {
    param([object[]]$Users, [object[]]$SignInRows)
    $lookup = @{}
    foreach ($row in $SignInRows) {
        $id = [string](Get-MtrProperty $row 'id' '')
        if ($id) { $lookup[$id] = Get-MtrProperty $row 'signInActivity' }
    }
    foreach ($user in $Users) {
        $id = [string](Get-MtrProperty $user 'id' '')
        $activity = if ($lookup.ContainsKey($id)) { $lookup[$id] } else { $null }
        $user | Add-Member -NotePropertyName signInActivity -NotePropertyValue $activity -Force
    }
    return @($Users)
}

Set-StrictMode -Version Latest

$script:ToolVersion = '0.1.1'

function Write-MtrStatus {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "[M365 Readiness] $Message" -ForegroundColor Cyan
}

function Get-MtrProperty {
    param(
        [AllowNull()][object]$InputObject,
        [Parameter(Mandatory)][string]$Name,
        [AllowNull()][object]$Default = $null
    )

    if ($null -eq $InputObject) { return $Default }
    if ($InputObject -is [System.Collections.IDictionary]) {
        if ($InputObject.Contains($Name)) { return $InputObject[$Name] }
        return $Default
    }

    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -ne $property) { return $property.Value }
    return $Default
}

function ConvertTo-MtrArray {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) {
        Write-Output -NoEnumerate @()
        return
    }
    Write-Output -NoEnumerate @($Value)
}

function ConvertTo-MtrHtml {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return '' }
    return [System.Net.WebUtility]::HtmlEncode([string]$Value)
}

function ConvertTo-MtrDateTime {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return $null }
    if ($Value -is [DateTimeOffset]) { return $Value.UtcDateTime }
    if ($Value -is [DateTime]) { return $Value.ToUniversalTime() }
    try {
        return [DateTimeOffset]::Parse(
            [string]$Value,
            [System.Globalization.CultureInfo]::InvariantCulture,
            [System.Globalization.DateTimeStyles]::AssumeUniversal
        ).UtcDateTime
    }
    catch { return $null }
}

function Get-MtrHashLabel {
    param([AllowNull()][string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return 'User-unknown' }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value.ToLowerInvariant())
        $hash = [System.BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-', '').Substring(0, 10)
        return "User-$hash"
    }
    finally { $sha.Dispose() }
}

function Invoke-MtrGraphRequestWithRetry {
    param(
        [Parameter(Mandatory)][string]$Uri,
        [ValidateRange(1, 8)][int]$MaxAttempts = 4
    )

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            return Invoke-MgGraphRequest -Method GET -Uri $Uri -OutputType PSObject
        }
        catch {
            $message = $_.Exception.Message
            $retryable = $message -match '(429|Too Many Requests|503|Service Unavailable|504|Gateway Timeout|temporarily unavailable)'
            if (-not $retryable -or $attempt -eq $MaxAttempts) { throw }
            Start-Sleep -Seconds ([Math]::Min(8, [Math]::Pow(2, $attempt)))
        }
    }
}

function Invoke-MtrGraphPagedRequest {
    param([Parameter(Mandatory)][string]$Uri)

    $items = [System.Collections.Generic.List[object]]::new()
    $nextLink = $Uri
    do {
        $response = Invoke-MtrGraphRequestWithRetry -Uri $nextLink
        $value = Get-MtrProperty -InputObject $response -Name 'value'
        if ($null -ne $value) {
            foreach ($item in (ConvertTo-MtrArray $value)) { $items.Add($item) }
            $nextLink = [string](Get-MtrProperty -InputObject $response -Name '@odata.nextLink' -Default '')
        }
        else {
            $items.Add($response)
            $nextLink = ''
        }
    } while (-not [string]::IsNullOrWhiteSpace($nextLink))

    return @($items)
}

function Get-MtrGraphCollection {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Area,
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][string[]]$Permissions,
        [switch]$Optional
    )

    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $items = @(Invoke-MtrGraphPagedRequest -Uri $Uri)
        $timer.Stop()
        return [pscustomobject]@{
            Name        = $Name
            Area        = $Area
            Endpoint    = $Uri
            Permissions = $Permissions
            Optional    = [bool]$Optional
            Status      = 'Complete'
            Count       = $items.Count
            DurationMs  = $timer.ElapsedMilliseconds
            Error       = $null
            Items       = $items
        }
    }
    catch {
        $timer.Stop()
        return [pscustomobject]@{
            Name        = $Name
            Area        = $Area
            Endpoint    = $Uri
            Permissions = $Permissions
            Optional    = [bool]$Optional
            Status      = 'Failed'
            Count       = 0
            DurationMs  = $timer.ElapsedMilliseconds
            Error       = $_.Exception.Message
            Items       = @()
        }
    }
}

function Add-MtrCollectionResult {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Manifest,
        [Parameter(Mandatory)][object]$Result
    )

    $Manifest.Add([pscustomobject]@{
        name        = $Result.Name
        area        = $Result.Area
        endpoint    = $Result.Endpoint
        permissions = @($Result.Permissions)
        optional    = $Result.Optional
        status      = $Result.Status
        count       = $Result.Count
        durationMs  = $Result.DurationMs
        error       = $Result.Error
    })
}

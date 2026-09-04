function New-MtrFinding {
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][ValidateSet('Critical','High','Medium','Review','Info')][string]$Severity,
        [Parameter(Mandatory)][string]$Area,
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$Evidence,
        [Parameter(Mandatory)][string]$Recommendation,
        [int]$AffectedCount = 0,
        [string[]]$ControlThemes = @()
    )
    return [pscustomobject]@{ id=$Id; severity=$Severity; area=$Area; title=$Title; evidence=$Evidence; recommendation=$Recommendation; affectedCount=$AffectedCount; controlThemes=@($ControlThemes) }
}

function Get-MtrEnabledUnits {
    param([object]$Sku)
    $prepaid = Get-MtrProperty $Sku 'prepaidUnits'
    return [int](Get-MtrProperty $prepaid 'enabled' 0)
}

function Get-MtrSkuMap {
    param([object[]]$Skus)
    $map = @{}
    foreach ($sku in $Skus) {
        $id = [string](Get-MtrProperty $sku 'skuId' '')
        if ($id) { $map[$id.ToLowerInvariant()] = [string](Get-MtrProperty $sku 'skuPartNumber' $id) }
    }
    return $map
}

function Test-MtrPolicyHasControl {
    param([object]$Policy, [string]$Control)
    $grantControls = Get-MtrProperty $Policy 'grantControls'
    $controls = ConvertTo-MtrArray (Get-MtrProperty $grantControls 'builtInControls')
    return @($controls | Where-Object { [string]$_ -ieq $Control }).Count -gt 0
}

function Test-MtrPolicyTargetsBroadUsers {
    param([object]$Policy)
    $conditions = Get-MtrProperty $Policy 'conditions'
    $users = Get-MtrProperty $conditions 'users'
    $includes = ConvertTo-MtrArray (Get-MtrProperty $users 'includeUsers')
    return @($includes | Where-Object { [string]$_ -ieq 'All' }).Count -gt 0
}

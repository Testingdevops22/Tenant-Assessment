function Protect-MtrSnapshot {
    param([Parameter(Mandatory)][object]$Snapshot)

    $copy = $Snapshot | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100
    $licensing = Get-MtrProperty $copy 'licensing'
    foreach ($user in (ConvertTo-MtrArray (Get-MtrProperty $licensing 'users'))) {
        $upn = [string](Get-MtrProperty $user 'userPrincipalName' '')
        $label = Get-MtrHashLabel $upn
        $user | Add-Member -NotePropertyName displayName -NotePropertyValue $label -Force
        $user | Add-Member -NotePropertyName userPrincipalName -NotePropertyValue $label -Force
    }
    $context = Get-MtrProperty $copy 'graphContext'
    if ($null -ne $context) { $context | Add-Member -NotePropertyName account -NotePropertyValue '[Redacted]' -Force }
    $tenant = Get-MtrProperty $copy 'tenant'
    foreach ($organization in (ConvertTo-MtrArray (Get-MtrProperty $tenant 'organization'))) {
        if ($null -ne (Get-MtrProperty $organization 'technicalNotificationMails')) {
            $organization | Add-Member -NotePropertyName technicalNotificationMails -NotePropertyValue @('[Redacted]') -Force
        }
    }
    $identity = Get-MtrProperty $copy 'identity'
    foreach ($app in @((ConvertTo-MtrArray (Get-MtrProperty $identity 'applications')) + (ConvertTo-MtrArray (Get-MtrProperty $identity 'servicePrincipals')))) {
        $name = [string](Get-MtrProperty $app 'displayName' '')
        if ($name) { $app | Add-Member -NotePropertyName displayName -NotePropertyValue "Application-$((Get-MtrHashLabel $name).Substring(5))" -Force }
    }
    $multiGeo = Get-MtrProperty $copy 'multiGeo'
    $exchange = Get-MtrProperty $multiGeo 'exchange'
    foreach ($mailbox in (ConvertTo-MtrArray (Get-MtrProperty $exchange 'mailboxes'))) {
        $upn = [string](Get-MtrProperty $mailbox 'UserPrincipalName' '')
        $label = Get-MtrHashLabel $upn
        $mailbox | Add-Member -NotePropertyName DisplayName -NotePropertyValue $label -Force
        $mailbox | Add-Member -NotePropertyName UserPrincipalName -NotePropertyValue $label -Force
        $mailbox | Add-Member -NotePropertyName PrimarySmtpAddress -NotePropertyValue $label -Force
    }
    return $copy
}

function ConvertTo-MtrTable {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Rows,
        [Parameter(Mandatory)][hashtable[]]$Columns,
        [string]$EmptyMessage = 'No data collected.'
    )

    if ($Rows.Count -eq 0) { return "<p class='empty'>$(ConvertTo-MtrHtml $EmptyMessage)</p>" }
    $head = ($Columns | ForEach-Object { "<th>$(ConvertTo-MtrHtml $_.Label)</th>" }) -join ''
    $body = foreach ($row in $Rows) {
        $cells = foreach ($column in $Columns) {
            $value = if ($column.ContainsKey('Script')) { & $column.Script $row } else { Get-MtrProperty $row $column.Property }
            "<td>$(ConvertTo-MtrHtml $value)</td>"
        }
        "<tr>$($cells -join '')</tr>"
    }
    return "<div class='table-wrap'><table><thead><tr>$head</tr></thead><tbody>$($body -join '')</tbody></table></div>"
}

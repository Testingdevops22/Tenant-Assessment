# M365 Tenant Readiness

An original, read-only PowerShell assessment that collects Microsoft 365 tenant evidence and creates a self-contained HTML report, a machine-readable JSON snapshot, and a CSV findings register.

The MVP covers:

- licensing inventory, capacity, assignment source/error state, disabled licensed users, missing `UsageLocation`, and optional inactivity review;
- tenant identity, domains, directory roles, Conditional Access, authentication methods, authorization policy, application registrations, and enterprise applications;
- Multi-Geo and Preferred Data Location (PDL) distribution;
- optional Exchange mailbox-region and SharePoint geo quota evidence;
- transparent collection status, including failed endpoints and their required read permissions;
- locally generated artifacts and optional identifier redaction.

It does **not** change the tenant, certify compliance, interpret Microsoft Product Terms, or prove the physical data location of every workload. Findings are evidence-led prompts for a qualified administrator to validate.

The implementation is original. The referenced Entra/Intune tools informed product principles such as read-only collection, local report generation, and visible partial failures; their source code was not copied.

## Requirements

- PowerShell 7.2 or later
- `Microsoft.Graph.Authentication`
- Optional: `ExchangeOnlineManagement` for Exchange Multi-Geo evidence
- Optional: `Microsoft.Online.SharePoint.PowerShell` for SharePoint evidence

Install the core dependency for the current user:

```powershell
Install-Module Microsoft.Graph.Authentication -Scope CurrentUser
```

Optional service modules:

```powershell
Install-Module ExchangeOnlineManagement -Scope CurrentUser
Install-Module Microsoft.Online.SharePoint.PowerShell -Scope CurrentUser
```

The tool never installs modules itself.

## Quick start

Standard interactive collection:

```powershell
./Invoke-M365TenantReadiness.ps1 \
  -TenantId 'contoso.onmicrosoft.com' \
  -OutputPath './contoso-readiness'
```

Full collection adds user sign-in activity and Microsoft Secure Score. These datasets depend on tenant licensing, role, and consent:

```powershell
./Invoke-M365TenantReadiness.ps1 \
  -TenantId 'contoso.onmicrosoft.com' \
  -Profile Full \
  -IncludeExchange \
  -ExchangeUserPrincipalName 'admin@contoso.com' \
  -IncludeSharePoint \
  -SharePointAdminUrl 'https://contoso-admin.sharepoint.com' \
  -OutputPath './contoso-full-readiness'
```

To use an existing Graph, Exchange, and SharePoint session, connect them first and add `-SkipConnect`.

For unattended Graph collection, provide an app ID, tenant ID, and a certificate thumbprint. The app registration must already have the relevant **application** permissions and admin consent:

```powershell
./Invoke-M365TenantReadiness.ps1 \
  -TenantId '00000000-0000-0000-0000-000000000000' \
  -ClientId '11111111-1111-1111-1111-111111111111' \
  -CertificateThumbprint 'ABCDEF0123456789ABCDEF0123456789ABCDEF01' \
  -Profile Full \
  -OutputPath './scheduled-readiness'
```

Redact user and application display identifiers in persisted output:

```powershell
./Invoke-M365TenantReadiness.ps1 -TenantId 'contoso.onmicrosoft.com' -RedactIdentifiers
```

## Read permissions

The Standard profile requests delegated read scopes:

| Area | Microsoft Graph scopes |
|---|---|
| Tenant and domains | `Organization.Read.All`, `Domain.Read.All` |
| Licensing and PDL | `User.Read.All`, `Group.Read.All`, `LicenseAssignment.Read.All` |
| Conditional Access and tenant policy | `Policy.Read.All`, `Policy.Read.AuthenticationMethod` |
| Directory roles | `RoleManagement.Read.Directory` |
| Applications | `Application.Read.All` |

Full adds `AuditLog.Read.All` for `signInActivity` and `SecurityEvents.Read.All` for Secure Score. Microsoft may also require a supported directory role for delegated calls. The collection-status chapter records failures rather than treating inaccessible data as empty.

Exchange and SharePoint use their own role model. Prefer Global Reader or the narrowest service reader roles that expose the required configuration. Do not use write roles solely for this report.

## Outputs

Each run creates:

- `tenant-readiness-report.html` — standalone report; open it in a browser and use Print → Save as PDF.
- `tenant-snapshot.json` — normalized point-in-time evidence for diffing or rerendering.
- `findings.csv` — review/remediation register.
- `license-assignments.csv` — user-to-SKU assignment source, state, error, disabled-plan count, location, and optional sign-in evidence.
- `pdl-users.csv` — identity source, UsageLocation, PDL, Exchange mailbox region/database geo, and alignment status.

Render an existing snapshot without signing in:

```powershell
./Invoke-M365TenantReadiness.ps1 \
  -SnapshotPath './examples/sample-snapshot.json' \
  -OutputPath './sample-output'
```

## Assessment behavior

- A missing/failed collection means **unknown**, not compliant and not empty.
- PDL checks become active when the snapshot contains user PDL values or multiple Exchange allowed regions.
- A blank PDL normally means tenant-default placement; it is a review item only when Multi-Geo indicators exist.
- For synchronized users, PDL should be changed in the authoritative on-premises directory. Cloud-only users can be managed through Microsoft Graph, but this tool performs no changes.
- Conditional Access checks are deliberately conservative. They detect broad structural gaps but cannot prove effective coverage or safe exclusions.
- Sign-in inactivity is a review signal; shared, service, new, or leave-of-absence accounts can be legitimate exceptions.

## Safe operating model

1. Run interactively with the Standard profile first.
2. Review collection failures before interpreting findings.
3. Add Full and service collectors only when their evidence is required.
4. Store snapshots as sensitive tenant data; use `-RedactIdentifiers` for wider circulation.
5. Validate remediation with service owners and change-control processes.

## Project structure

```text
Invoke-M365TenantReadiness.ps1   Entry point
src/M365TenantReadiness.psm1    Collectors, rules, redaction, renderer
examples/sample-snapshot.json   Sanitized offline test fixture
tests/                           Pester tests
```

## Primary Microsoft references

- [List subscribed SKUs](https://learn.microsoft.com/en-us/graph/api/subscribedsku-list?view=graph-rest-1.0)
- [List users and supported properties](https://learn.microsoft.com/en-us/graph/api/user-list?view=graph-rest-1.0)
- [License assignment state](https://learn.microsoft.com/en-us/graph/api/resources/licenseassignmentstate?view=graph-rest-1.0)
- [Configure Preferred Data Location](https://learn.microsoft.com/en-us/entra/identity/hybrid/connect/how-to-connect-sync-feature-preferreddatalocation)
- [Exchange Online data residency and Multi-Geo properties](https://learn.microsoft.com/en-us/microsoft-365/enterprise/m365-dr-service-exo?view=o365-worldwide)
- [SharePoint Multi-Geo storage quota](https://learn.microsoft.com/en-us/powershell/module/microsoft.online.sharepoint.powershell/get-spogeostoragequota?view=sharepoint-ps)
- [Conditional Access policy API](https://learn.microsoft.com/en-us/graph/api/conditionalaccesspolicy-get?view=graph-rest-1.0)

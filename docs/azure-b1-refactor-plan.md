# CWM Reporting — Azure B1 Refactor Plan

Plan for rebuilding the ConnectWise Manage (CWM) helpdesk reporting system as a single
ASP.NET Core app on an Azure App Service **Basic B1 (Linux)** plan. Written 2026-07-12
from analysis of https://github.com/OpsChasingDev/cwm-container-testing (`main` @ c5a98ef).

---

## 1. Current-state summary (what we're replacing)

| Aspect | Today |
|---|---|
| Reports | 7 PowerShell scripts (`services/app03`–`app09`), one ACI container group each, infinite loop, `$FrequencyMinutes = 2` (UI says 5) |
| Shared code | `shared/modules/CWMShared.psm1` (885 lines), baked into every image; `ConnectWiseManageAPI` module installed from PSGallery **at container boot** |
| Data flow | Each container → CWM REST API → CSV + HTML to Azure File Share → Node/Express web container reads share and serves files |
| Web | Node 18 + Express + vanilla JS SPA; also start/stop ACI via Azure SDK with service-principal creds |
| Auth | **None** — public endpoint exposes reports *and* container power controls |
| Deploy | 10 GitHub Actions workflows; each deploy `az container delete` + recreate + (web) rewrite DNS A record |
| Duplication | 6 of 7 reports independently run `Get-CWMFullTicket` per board every cycle; 5 do N+1 `Get-CWMTicket -id` per ticket; 3 independently pull the same per-ticket time entries |
| Cost | ACR + ~9 always-on ACI groups + 4 file shares — roughly $250–350/mo (verify in Cost Analysis before/after) |

Fragile points worth not carrying forward: runtime PSGallery installs, audit-trail
free-text parsing in the reopened-ticket report (splits on `"` and indexes `[-4]`),
hard-coded stop-word arrays, ACI name-map duplication, IP churn on deploy.

## 2. Target architecture

**One ASP.NET Core 10 (.NET 10 LTS) web app** on a Linux B1 plan. Everything in-process;
no containers, no ACR, no file shares, no database.

```
┌─ App Service Plan B1 Linux (~$13/mo) ────────────────────────────┐
│  ┌─ Web App: cwm-reports (prod) ─────────────────────────────┐   │
│  │  Easy Auth (Entra ID, org-only)  ← every request           │   │
│  │  ┌────────────────────────────────────────────────────┐   │   │
│  │  │ ASP.NET Core 10                                     │   │   │
│  │  │  • CollectorService : BackgroundService             │   │   │
│  │  │      every 5 min → CWM REST API → Snapshot          │   │   │
│  │  │  • SnapshotStore (singleton, in-memory, atomic swap)│   │   │
│  │  │  • IReport implementations (one class per report)   │   │   │
│  │  │  • UI (Blazor Server) + /api/reports/{id}/export    │   │   │
│  │  └────────────────────────────────────────────────────┘   │   │
│  └───────────────────────────────────────────────────────────┘   │
│  ┌─ Web App: cwm-reports-staging (same plan, $0 extra) ───────┐  │
│  └───────────────────────────────────────────────────────────┘   │
└───────────────────────────────────────────────────────────────────┘
```

### Key decisions and why

1. **In-process background collector instead of separate containers.**
   B1 supports **Always On** (Basic tier and up), so a `BackgroundService` runs reliably
   24/7 inside the web app. One collector fetches each CWM data set **once** per cycle —
   board tickets, per-ticket detail, time entries, audit trails, board teams/members —
   into an immutable `Snapshot` object that all reports read. This eliminates all the
   cross-container duplication by construction. No slots/WebJobs/Functions needed.

2. **No persistent storage.** The snapshot lives in memory. On app restart the collector
   repopulates within one cycle; the UI shows a "warming up" state with last-refresh
   timestamp. (Requirement: persistence not necessary.) Optional cheap insurance: write
   the last snapshot JSON to `%HOME%/data` (App Service's built-in persistent disk, free)
   so restarts serve stale-but-labeled data instantly.

3. **Direct REST client, drop PowerShell.** The `ConnectWiseManageAPI` module is a thin
   wrapper over the CWM REST API (`/v4_6_release/apis/3.0/...`). A typed `CwmClient`
   (`HttpClient` + auth header + `conditions` builder + pagination + `fields=`
   projection + Polly retry/rate-limit handling) replaces it. The module's open source
   is the Rosetta stone for endpoint mapping (see spike S2).

4. **Blazor Server for the UI.** .NET-native interactivity (sortable tables, board
   filter, live freshness indicator) with no JS framework, no client API surface to
   secure separately, and SignalR works fine on Linux B1. Fallback if preferred: Razor
   Pages + minimal JS (closer to today's vanilla approach). Either way: server-rendered,
   one deployable.

5. **Easy Auth (App Service Authentication) with Entra ID.** Zero code: enable the auth
   module, provider = Microsoft Entra, supported account types = *My organization only*,
   unauthenticated requests → redirect to login. Optionally require user assignment on
   the enterprise app to restrict to a Support-managers group. User identity arrives in
   `X-MS-CLIENT-PRINCIPAL` headers for display ("signed in as ..."). Works on all tiers.

6. **Reports as plug-ins.** `IReport { Id, Title, Description, Category,
   ReportTable Build(Snapshot) }`, discovered via DI. Adding a report = adding one class;
   the UI menu, refresh cadence, and export endpoints come for free. Reports never call
   the API — they only read the snapshot — so a new report can never add API load.

7. **Container power controls disappear.** They existed to manage ACI lifecycles.
   Replacement: an **Operations page** showing per-source collector status (last run,
   duration, row counts, errors, next run) and a "Refresh now" button that triggers an
   immediate collector cycle. Same operational clarity, no Azure SDK, no service
   principal in the web tier.

8. **Staging = second web app on the same B1 plan** (deployment slots require Standard
   tier — confirmed limitation). Apps on one plan share the same VM, so staging's
   collector should run at a slow cadence (e.g. 30 min) or on-demand only, to protect
   prod CPU/memory and CWM rate limits. Deploy flow: push to `staging` branch → staging
   app; tag/merge to `main` → prod app. Both via `azure/webapps-deploy` code deploy
   (no Docker anywhere — B1 Linux runs `DOTNETCORE|10.0` natively).

9. **Exports.** Every report gets `GET /api/reports/{id}/export?format=csv|xlsx|json`
   generated on the fly from the snapshot (CsvHelper + ClosedXML). Since Easy Auth
   fronts every request, exports are automatically org-restricted too.

### Cost estimate (minimal-cost requirement)

| Item | Monthly |
|---|---|
| App Service Plan B1 Linux (1 core / 1.75 GB / 10 GB) | ~$13 |
| Staging app on same plan | $0 |
| Entra ID / Easy Auth | $0 |
| App Service managed certificate + custom domain | $0 (cert free on Basic) |
| Application Insights (sampled, low volume) | ~$0–3 |
| **Total** | **~$13–16/mo** |

Everything retired: ACR, ~9 ACI groups, 4 file shares, DNS-rewriting deploy machinery.

## 3. Solution layout (new repo)

```
cwm-reports/
├─ src/
│  ├─ Cwm.Client/            # REST client: auth, conditions, paging, models, retries
│  ├─ Cwm.Collector/         # BackgroundService, Snapshot, SnapshotStore, source fetchers
│  ├─ Cwm.Reports/           # IReport + one class per report + shared table/format helpers
│  └─ Cwm.Web/               # Blazor Server UI, export endpoints, ops page, health checks
├─ tests/
│  ├─ Cwm.Client.Tests/      # unit + recorded-response tests
│  ├─ Cwm.Reports.Tests/     # golden-file tests per report (fixed snapshot in, table out)
│  └─ Cwm.Parity.Tests/      # legacy-CSV comparison harness (Stage 3 only)
├─ infra/                    # Bicep: plan, 2 web apps, Easy Auth config, App Insights
└─ .github/workflows/        # build+test, deploy-staging, deploy-prod
```

Report logic becomes pure functions over the snapshot — trivially unit-testable, which
the PowerShell loops never were.

## 4. Spikes (do these before/alongside Stage 1)

**S1 — CWM REST auth + pagination from .NET** *(½ day; gates everything)*
Console app: Basic auth header `base64(company+publicKey:privateKey)` + `clientId`
header → `GET /service/tickets?conditions=board/name="..." and closedFlag=false
&pageSize=1000&fields=id,summary,...`. Verify: auth works, `conditions` syntax for the
board list, Link-header pagination, `fields=` projection shrinks payloads. Read-only
GETs only, small page sizes first.

**S2 — Safe API exploration / endpoint mapping** *(1 day, parallel with S1)*
The official docs are behind auth; four safe angles, in order of value:
- **Read the PowerShell module's source** (github.com/christaylorcodes/ConnectWiseManageAPI):
  every `Get-CWM*` cmdlet used by `CWMShared.psm1` maps to a concrete REST endpoint.
  Build a table: cmdlet → endpoint → params used → response fields consumed.
- **Trace the existing system**: run the current scripts locally with the module's
  `-Debug`/`-Verbose` output (or a logging `HttpClientHandler` proxy) against the
  staging boards to capture the exact requests today's reports make.
- **Authenticated docs**: log into developer.connectwise.com with the company account;
  browser automation (Claude in Chrome) can walk the authenticated doc pages and
  extract endpoint/schema notes into a local reference file.
- **Ground truth probing**: a scratch notebook/console using a **read-only API member
  key** against a low-traffic board; never POST/PUT/PATCH during exploration.
Deliverable: `docs/cwm-endpoints.md` in the new repo — the contract for `Cwm.Client`.

**S3 — B1 sizing / snapshot memory** *(½ day)*
Deploy the S1 skeleton to a throwaway B1 app. Fetch a full real cycle (all boards,
tickets, time entries) and measure: snapshot size in memory, cycle wall-time, API call
count. Pass criteria: snapshot ≪ ~500 MB (leaves headroom in 1.75 GB), cycle < 5 min.
This also verifies `DOTNETCORE|10.0` is available in your region
(`az webapp list-runtimes --os linux`).

**S4 — Easy Auth end-to-end** *(½ day)*
Enable Entra auth on the skeleton: verify org-only login, external/personal accounts
rejected, claims headers present, and that SignalR/websockets (Blazor Server circuits)
work through the auth module. Test the group-assignment restriction if leadership-only
access is wanted.

**S5 — Audit-trail structure for the Reopened report** *(½ day, before porting app04)*
Today's reopened-ticket logic parses free-text audit entries — the most brittle code in
the system. Pull `/service/tickets/{id}/auditTrail` raw JSON for known-reopened tickets
and determine whether structured fields (`auditType`, `oldValue`/`newValue`-style data)
can replace text parsing. Decide: structured parse, or keep text parse but isolate +
golden-test it.

**S6 — Export formats** *(¼ day, low risk, can fold into Stage 5)*
CSV via CsvHelper, XLSX via ClosedXML from a `ReportTable`; confirm managers' Excel
opens both cleanly.

## 5. Build stages

**Stage 0 — Foundations** *(after S1/S2 pass)*
New repo, solution scaffold, `infra/` Bicep (plan + prod/staging apps + Always On +
App Insights + Easy Auth settings), CI workflow (build, test, publish artifact),
deploy workflows. Secrets: CWM keys in app settings (Key Vault references optional
later). Exit: skeleton app with `/healthz` deployed to staging by pipeline.

**Stage 1 — `Cwm.Client`**
Typed client per the S2 endpoint map: tickets (board/closed/lastDays conditions),
ticket detail, time entries, audit trail, contacts, members, board teams. Pagination,
`fields=` projection, Polly retry + throttle handling, cancellation. Recorded-response
unit tests; one opt-in integration test suite against read-only keys.
Exit: every data need of the 7 reports retrievable through the client.

**Stage 2 — Collector + Snapshot**
`Snapshot` (immutable): tickets by board, time entries by ticket, contacts, members,
board teams, audit summaries; plus per-source metadata (fetchedAt, duration, count,
error). `CollectorService`: 5-min cadence (config), fetches sources concurrently where
safe, builds new snapshot, atomic swap into `SnapshotStore`. Failure of one source
keeps the previous data for that source, labeled stale. Manual trigger endpoint.
Exit: staging app holds a live, self-refreshing snapshot; ops data visible via a raw
JSON status endpoint.

**Stage 3 — Report engine + port all 7 reports**
Port order (easy → hard): KeywordsLast7Days → POCOpenTicket → AvgTimeEntryDuration →
AvgTimeEntryGap → TimeSinceLastTimeEntry → TicketsWorkedToday (timezone handling —
replace the `UTCTimeZone` offset env var with proper `TimeZoneInfo`) → ReopenedTicket
(apply S5 decision). Each report: golden-file unit test + **parity check** — run legacy
and new side by side on the same boards, diff CSVs, explain every difference (some will
be legacy bugs; document, don't replicate).
Exit: all 7 reports byte-explainable vs legacy.

**Stage 4 — Web UI**
Blazor Server pages: dashboard landing (headline numbers per report, data freshness),
report pages (sortable columns, board multi-filter, ticket-ID deep links to CWM,
description panel — port `desc.json` content), Operations page (collector status,
refresh-now), staging banner. Design for "full clarity": every table shows *as-of*
timestamp and the boards it covers.
Exit: managers can do everything today's UI does, minus container power buttons,
plus freshness/ops visibility.

**Stage 5 — Exports**
`/api/reports/{id}/export?format=csv|xlsx|json` + per-report Export buttons + "export
all (zip)". JSON export doubles as a machine interface if BrightGauge-style ingestion
ever returns.

**Stage 6 — AuthN/AuthZ + custom domain**
Enable Easy Auth on staging first (S4 made this rote), verify, then prod. Optional:
require assignment + Entra group for Support leaders. Custom domain
(`cwm-reporting.opschasingdev.com`) + free managed cert; DNS is now set once, not
rewritten per deploy.

**Stage 7 — Parallel run + cutover**
Two weeks side-by-side: managers use the new site, legacy keeps running. Compare
numbers on real workdays (esp. TicketsWorkedToday around midnight/timezone edges).
Then: point DNS at the new app, stop ACI groups (keep a week, then delete), delete
ACR, file shares, deploy workflows, the DNS-rewrite machinery, and the old service
principal. Archive the old repo with a pointer to the new one.

## 6. Risks & mitigations

| Risk | Mitigation |
|---|---|
| B1 single instance: restart loses snapshot | Refetch on start (~1 cycle); optional `%HOME%` JSON cache; "warming up" UI state |
| Collector cycle exceeds cadence (CWM slow / rate limits) | S3 measures it; `fields=` projection + one-fetch-per-source cuts today's call volume by ~6×; overlap guard (skip next tick if running); per-source timing on ops page |
| CWM API rate limiting | Polly (respect 429/`Retry-After`), sequential-with-concurrency-cap fetching, alert if throttled |
| Audit-trail parsing (Reopened report) | Spike S5 before port; golden tests either way |
| Staging app steals prod resources on shared plan | Staging collector slow/off by default; both apps under App Insights; if ever needed, move staging to its own Free/B1 plan |
| .NET 10 runtime availability on Linux App Service in region | Verified during S3 (`az webapp list-runtimes`); fallback: self-contained deploy |
| Memory ceiling 1.75 GB | S3 measures snapshot; `fields=` keeps models thin; if huge boards ever blow it, B2 (~$26/mo) is a config change, or trim retained fields |
| Timezone bugs (legacy used fixed `-5` offset — wrong half the year) | Use `TimeZoneInfo` ("America/New_York"); parity diffs around DST are expected and correct |

## 7. Explicit non-goals

- No database, queue, or cache service (in-memory snapshot suffices).
- No container infrastructure of any kind.
- No per-user authorization tiers beyond org/group gate (add later via Entra groups if needed).
- No write operations against CWM — the entire system stays read-only.

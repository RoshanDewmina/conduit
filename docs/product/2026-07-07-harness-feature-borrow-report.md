# Harness feature borrow report — mobile-native Lancer ideas

Compiled: 2026-07-07  
Goal: identify popular desktop/dev harnesses, their highest-value features, and what Lancer should cherry-pick for a phone-first agent workflow.

## Framing

“Harness” here means any tool developers use to prove, reproduce, inspect, or validate software:

- browser E2E harnesses
- mobile app test harnesses
- API harnesses
- load/performance harnesses
- visual regression harnesses
- component/story harnesses
- accessibility harnesses
- observability/session replay harnesses
- CI artifact/report harnesses

The pattern across the best tools is clear:

> The killer desktop harness features are not the test runners themselves. They are the **debug artifacts**: trace viewers, time travel, screenshots, videos, logs, network requests, DOM/UI trees, visual diffs, metrics, assertions, and before/after baselines.

Lancer should not try to rebuild Playwright, Cypress, Appium, k6, or Storybook on the phone. Lancer should let agents run those tools on the user’s machine, then turn their artifacts into a mobile-native decision surface.

## Sources checked

- Playwright Trace Viewer, UI Mode, Codegen: `https://playwright.dev/docs/trace-viewer`, `https://playwright.dev/docs/test-ui-mode`, `https://playwright.dev/docs/codegen`
- Cypress Why Cypress / visual testing / Test Replay: `https://docs.cypress.io/app/get-started/why-cypress`, `https://docs.cypress.io/app/tooling/visual-testing`
- Selenium / web automation comparisons: `https://stackoverflow.blog/2026/06/15/selenium-vs-cypress-vs-playwright-choosing-your-test-automation-framework/`
- Appium docs and Inspector: `https://appium.io/docs/en/`, `https://appium.github.io/appium-inspector/2026.5/`
- Maestro docs/product: `https://docs.maestro.dev/`, `https://maestro.dev/`
- Postman mock servers and collection runner: `https://learning.postman.com/docs/design-apis/mock-apis/set-up-mock-servers`, `https://learning.postman.com/docs/tests-and-scripts/running-collections/intro-to-collection-runs`
- Bruno: `https://www.usebruno.com/`, `https://docs.usebruno.com/introduction/getting-started`
- k6 / Grafana docs: `https://k6.io/`, `https://grafana.com/docs/k6/latest/using-k6-browser/metrics/`
- Apache JMeter: `https://jmeter.apache.org/`
- Storybook interaction/visual tests: `https://storybook.js.org/docs/writing-tests/interaction-testing`, `https://storybook.js.org/docs/writing-tests/visual-testing`
- Chromatic / Percy visual testing: `https://www.chromatic.com/storybook`, `https://www.browserstack.com/docs/percy/overview/visual-testing-basics`
- axe-core / Axe DevTools: `https://github.com/dequelabs/axe-core`, `https://www.deque.com/axe/devtools/`
- Sentry / Datadog Session Replay: `https://docs.sentry.io/platforms/javascript/session-replay/configuration/`, `https://docs.datadoghq.com/real_user_monitoring/`
- GitHub Actions artifacts: `https://docs.github.com/en/actions/tutorials/store-and-share-data`

## Top harnesses and what to steal

This is not a perfect popularity ranking by downloads; it is the pragmatic “top 10” set that shows up repeatedly across current testing/tooling comparisons and covers the highest-value engineering workflows.

| Harness | What developers use it for | Best desktop features | Lancer mobile feature to borrow |
|---|---|---|---|
| Playwright | Modern browser E2E and agent/browser automation | Trace Viewer, UI Mode, codegen, screenshots/videos, network logs, multi-browser, affected-test filtering | **Pocket Trace Review**: agent runs Playwright, phone shows step timeline, screenshot per step, console/network failures, “repro failed before / passed after” |
| Cypress | Frontend E2E/component testing | Time Travel command log, DOM snapshots, automatic waiting, readable errors, visual debugging, cloud replay | **Command Time Travel**: tap a failed step and see app state, assertion, network call, and agent’s proposed fix |
| Selenium/WebDriver | Mature cross-browser automation | Huge ecosystem, grid/cloud execution, language flexibility, enterprise browser matrix | **Browser Matrix Receipt**: mobile summary of Chrome/Firefox/Safari/edge cases, not raw logs |
| Appium | Native/hybrid mobile automation | Appium Inspector, UI hierarchy, screenshots, element search, driver actions, recording | **Mobile UI Inspector Card**: show failing screen + accessibility/tree selectors + tap target that failed |
| Maestro | Simple mobile/web UI flows | YAML flows, fast local simulator runs, Studio, video recording, cloud reports, MCP/device control | **Flow-as-Proof**: agent converts bug into readable YAML journey; phone can approve generated flow and watch video |
| Postman / Bruno | API exploration, collections, mocks, API tests | Collections, environments, mock servers, collection runner, Git-native local collections in Bruno | **API Contract Proof**: agent runs endpoint collection, shows changed request/response examples, latency, auth failures, schema drift |
| k6 / JMeter | Load/performance testing | Thresholds, virtual users, p95/p99/error rate, ramp-up, dashboards, load profiles | **Performance Budget Card**: “this change added 120ms p95 on checkout under 50 VUs; reject or continue?” |
| Storybook | Component development and test harness | Isolated stories, interaction tests, sidebar statuses, component states, docs-as-harness | **Component State Grid**: agent runs affected stories; phone shows changed component states and failed interactions |
| Chromatic / Percy | Visual regression testing | Baselines, screenshot diffs, responsive widths, review/approve workflow | **Visual Diff Approval**: side-by-side mobile image diff with “intended / bug / ask agent” actions |
| axe-core / Axe DevTools | Accessibility testing | Automated a11y checks, labels/contrast/duplicate IDs, clear actionable findings, CI/browser integration | **A11y Gate Card**: only show new violations, severity, affected UI, fix suggestion, and before/after status |
| Sentry / Datadog Replay | Production/debugging harness | Session replay, breadcrumbs, errors, network/user actions, RUM correlation, performance traces | **Production Repro Capsule**: error + user journey + replay clip becomes a Lancer mission |
| GitHub Actions artifacts/reports | CI proof and build/test outputs | Persist test reports, coverage, screenshots, crash dumps, logs, binaries | **Artifact Digest**: mobile parses CI artifacts into proof cards instead of making user download zips |

## Workflow-by-workflow opportunities

### 1. Intake

Current desktop pattern:

- Sentry/Datadog replay captures real user sessions.
- Clips/Loom capture human feedback.
- Postman/Bruno collections capture API examples.
- GitHub Actions artifacts capture CI failures.

Mobile Lancer feature:

## Evidence Inbox

The user shares:

- Sentry issue
- Datadog replay
- Clip/Loom
- screenshot/video
- GitHub failed check
- Postman/Bruno collection
- support/customer message

Lancer turns it into:

- suspected user journey
- repro confidence
- missing info
- affected surface
- suggested mission contract
- first proof requirement

Why this is strong:

- Competitors mostly ingest prompts and sessions.
- Lancer would ingest evidence.

### 2. Reproduction

Current desktop pattern:

- Playwright/Cypress codegen can turn interactions into tests.
- Maestro flows are readable YAML.
- Appium Inspector identifies native elements.
- Sentry/Datadog replay shows the real path to failure.

Mobile Lancer feature:

## Auto-Repro Builder

Agent generates the smallest runnable repro:

- Playwright test for web
- Maestro flow for mobile
- Appium/XCUITest path for native
- API collection/request for backend
- manual repro if automation is not possible

The phone shows:

- “Repro found” / “could not reproduce”
- exact steps
- failing assertion
- screenshot/video
- confidence
- ask-user question if needed

Killer detail:

> Lancer should require “fails before fix” for high-confidence bug fixes whenever possible.

That is a stronger proof standard than most agent clients.

### 3. Planning / scoping

Current desktop pattern:

- Harnesses define scope implicitly through suites, projects, tags, devices, browsers, viewports, thresholds.

Mobile Lancer feature:

## Harness Plan

Before work starts, Lancer shows:

- which harnesses will be used
- why each one matters
- expected run time
- required pass/fail thresholds
- what would block completion

Example:

- Playwright checkout regression: required
- API payment collection: required
- Visual diff checkout mobile width: required
- k6 smoke profile: optional unless API changed
- Axe scan: optional unless UI changed

This makes Mission Contract much more concrete.

### 4. Implementation

Current desktop pattern:

- Test runners expose progress, failed steps, logs, screenshots, videos, retry history.

Mobile Lancer feature:

## Harness-Aware Work Thread

Instead of raw agent chat:

- “Reproduced bug”
- “Changed files”
- “Ran checkout.spec.ts”
- “Failed at step 4”
- “Captured screenshot”
- “Retried after selector fix”
- “Proof passed”

Every timeline event has an artifact behind it.

### 5. Validation

Current desktop pattern:

- Playwright/Cypress traces.
- Cypress command snapshots.
- Chromatic/Percy visual baselines.
- k6 thresholds.
- Axe violations.
- Postman collection results.

Mobile Lancer feature:

## Proof Matrix

Rows:

- Repro fails before fix
- Repro passes after fix
- Existing tests pass
- Visual diff reviewed
- API contract stable
- Accessibility unchanged
- Performance budget not violated
- Forbidden files untouched

Columns:

- status
- evidence
- risk
- action

This is one of the clearest killer features. It turns all desktop harnesses into one mobile decision panel.

### 6. Debugging failures

Current desktop pattern:

- Playwright Trace Viewer.
- Cypress Time Travel.
- Appium Inspector.
- Storybook interaction panel.
- JMeter/k6 graphs.

Mobile Lancer feature:

## Failure Replay Card

For each failed harness:

- exact failing step
- screenshot/video frame
- selector/request/assertion
- console/network error
- related diff hunk
- agent’s diagnosis
- suggested next action

Actions:

- retry
- ask agent to fix
- accept as unrelated
- mark flaky
- escalate to desktop

### 7. Review

Current desktop pattern:

- Visual tools ask users to approve or reject diffs.
- CI reports annotate failures.
- Storybook/Chromatic focus review on changed UI states.

Mobile Lancer feature:

## Review by Evidence

Do not start with raw code diff. Start with claims and harness proof:

- Claim: “Checkout no longer crashes on missing address”
- Evidence: Playwright trace + before/after screenshot + test pass
- Claim: “Payment API behavior unchanged”
- Evidence: Postman/Bruno collection pass
- Claim: “Mobile layout did not regress”
- Evidence: Percy/Chromatic diff approved

Then let the user open code only when needed.

### 8. Ship

Current desktop pattern:

- CI artifacts persist logs, reports, screenshots, coverage, crash dumps.

Mobile Lancer feature:

## PR Proof Packet

Attach to PR:

- mission contract
- repro
- proof matrix
- visual diffs
- trace links
- API collection result
- performance/a11y summary
- unresolved risks

Small teams would actually understand and trust agent PRs faster.

### 9. Post-ship

Current desktop pattern:

- Sentry/Datadog observe production errors and replays.
- OpenTelemetry connects traces/logs/metrics.

Mobile Lancer feature:

## Watch Window

After merge/deploy:

- watch original error signature
- watch affected route/API
- watch replay/RUM recurrence
- watch latency/error budgets
- report after 15/30/60 minutes

Phone message:

> “Fix has been live 30m. Original error has not recurred. Checkout p95 unchanged. One unrelated warning appeared.”

This is very useful for solo devs and small teams.

### 10. Regression memory

Current desktop pattern:

- Harnesses keep tests, baselines, collections, and thresholds.

Mobile Lancer feature:

## Regression Vault

Every finished mission stores:

- original evidence
- generated repro
- proof matrix
- visual baseline
- API request examples
- performance budget
- known failure signature
- affected files/components

Next time an agent touches related code, Lancer warns:

> “This area has a saved checkout crash repro. Run it before marking ready.”

This is probably the deepest moat from harnesses.

## Best cherry-picks for Lancer

### P0: Proof Matrix

Borrow from all harnesses.

One phone panel showing:

- pass/fail
- before/after
- screenshots/videos
- traces
- API results
- visual diffs
- a11y/perf status
- unresolved risk

This should be the core Lancer differentiator.

### P0: Pocket Trace Review

Borrow from Playwright/Cypress.

Mobile timeline:

- step
- screenshot
- assertion
- network/console
- diff link
- agent explanation

This is the “video feature” but more useful than raw video.

### P0: Auto-Repro Builder

Borrow from Playwright codegen, Cypress, Maestro, Appium, Sentry/Datadog.

Turn evidence into runnable repro. Require fails-before / passes-after when possible.

### P1: Visual Diff Approval

Borrow from Chromatic/Percy.

A small team can approve UI changes from phone without reading every CSS diff.

### P1: API Contract Proof

Borrow from Postman/Bruno.

Very useful for backend work:

- request before/after
- response diff
- schema drift
- auth failures
- status/latency

### P1: Failure Replay Card

Borrow from Trace Viewer, Cypress Time Travel, Appium Inspector.

Show only the failure moment and the likely cause.

### P1: Watch Window

Borrow from Sentry/Datadog/OpenTelemetry.

After ship, Lancer monitors whether the fix actually worked.

### P2: Regression Vault

Borrow from every harness’s baselines/tests.

Save useful proof forever and auto-run it when related areas change.

## Potential killer feature

The strongest single packaged feature:

## Pocket Harness Cockpit

The desktop runs every serious harness. The phone shows the decision cockpit.

It has five tabs or sections:

1. **Repro** — can we reproduce the issue?
2. **Trace** — what happened at the failing step?
3. **Proof** — did the fix meet the contract?
4. **Risk** — what changed, what is unproven?
5. **Memory** — should this become a regression guard?

User actions:

- approve proof
- ask another pass
- rerun one harness
- mark flaky
- save as regression
- open on desktop

Why this is different:

- Orca/Happier/Cursor can run agents.
- Lancer would make harness output mobile-native and decision-ready.
- The user does not feel compromised on mobile because they are not coding on mobile. They are reviewing the exact proof artifacts they need.

## Private beta slice

Do not build all harnesses.

Build this narrow path:

1. Intake: screenshot/video/URL.
2. Agent generates Playwright or Maestro repro.
3. Lancer stores proof object:
   - failing repro before
   - passing repro after
   - screenshots/video/trace
   - changed files
4. Phone shows Proof Matrix + Pocket Trace Review.
5. User can approve, ask another pass, or save as regression.

This one slice is enough to validate whether the harness idea is valuable.

## Product naming options

- Pocket Harness Cockpit
- Proof Matrix
- Repro-to-Proof
- Case File
- Regression Vault
- Trace Review
- Harness Receipts
- Fix Provenance

Best names:

- **Proof Matrix** for the feature surface.
- **Case File** for the full work artifact.
- **Regression Vault** for long-term memory.

## Recommendation

Add this to Lancer’s direction:

> Lancer does not replace desktop harnesses. It makes their outputs usable from a phone.

Near-term:

- Finish Tier 0.
- Add Proof Matrix as the first post-Tier-0 product surface.
- Support Playwright traces first because they produce rich artifacts and map well to web/agent workflows.
- Add Maestro next for mobile app flows.
- Add Postman/Bruno API proof for backend teams.
- Add Sentry/Datadog intake/watch later.


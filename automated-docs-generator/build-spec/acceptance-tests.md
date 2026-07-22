# Acceptance Tests — Automated Docs Generator

> Verifiable behaviors for engineering sign-off. Run against your app before bumping `kit.json.status` to `published`.

## Functional

### T1 — Create a run
- **Setup:** Deployed stack; UI loaded.
- **Action:** Click "New Empty Run."
- **Expected:** A run record exists in the runs table with `status: created` and a `createdAt`; it appears in the UI runs list.
- **Maps to:** FR1, FR9

### T2 — Trigger a screenshot run
- **Setup:** A created run; valid app credentials.
- **Action:** Click "Trigger Screenshot Run" and supply credentials.
- **Expected:** Lambda calls `ecs:RunTask` on the screenshot task def; run moves to `status: running`; an ECS task is visible in the console.
- **Maps to:** FR1, FR9

### T3 — Login + navigation
- **Setup:** Screenshot job running against the target app.
- **Action:** Observe the `step_login` + first navigation steps.
- **Expected:** Nova Act logs in and reaches the first documented page; `ensure_on_app` recovers if the browser drifts.
- **Maps to:** FR2

### T4 — Screen capture
- **Setup:** Running capture.
- **Action:** Let the workflow walk its `step_*` functions.
- **Expected:** One PNG per intended screen is captured and uploaded to `runs/{runId}/screenshots/{name}.png`.
- **Maps to:** FR2, FR4

### T5 — AI description per screenshot
- **Setup:** A captured screenshot.
- **Action:** Inspect the section.
- **Expected:** A non-empty Claude-generated description exists at `runs/{runId}/descriptions/{name}.txt` and on the section record.
- **Maps to:** FR3, FR4

### T6 — Section persistence + ordering
- **Setup:** Completed capture.
- **Action:** List sections for the run.
- **Expected:** Sections table has one item per capture (PK `runId`, SK `sectionId`) with title, screenshot key, description key, and order; `sectionCount` on the run matches.
- **Maps to:** FR4

### T7 — Edit a description
- **Setup:** A run with sections.
- **Action:** Edit a description inline in the UI and save.
- **Expected:** The updated description persists (PUT succeeds) and is shown on reload.
- **Maps to:** FR5

### T8 — Replace a screenshot
- **Setup:** A run with sections.
- **Action:** Upload a replacement image via the presigned URL flow.
- **Expected:** The new image is stored at the section's screenshot key and displayed; the presigned PUT succeeds.
- **Maps to:** FR5

### T9 — Generate guide
- **Setup:** A reviewed run.
- **Action:** Click "Generate Guide."
- **Expected:** Run moves `generating → generated`; `runs/{runId}/user_guide.html` exists; the HTML has a populated sidebar nav and one card per section.
- **Maps to:** FR6, FR9

### T10 — View / download guide
- **Setup:** A generated run.
- **Action:** Click "View Guide."
- **Expected:** A presigned S3 URL returns the HTML guide; it renders in the browser.
- **Maps to:** FR6, FR8

### T11 — Regenerate with feedback
- **Setup:** A generated run.
- **Action:** Click "Regenerate with Feedback" with a concrete instruction (e.g., "group the billing screens together").
- **Expected:** The guide is revised per the instruction (not rebuilt blank); the change is visible in the new HTML.
- **Maps to:** FR7

### T12 — Live status refresh
- **Setup:** An active run.
- **Action:** Watch the UI while a run progresses.
- **Expected:** The UI auto-refreshes ~every 8s and reflects status transitions without a manual reload.
- **Maps to:** FR9

## Non-functional / operational

### T13 — Safe capture (no destructive actions)
- **Setup:** A workflow that opens a creation form and a screen with a Delete control.
- **Action:** Run the capture; review the captured states and the app's data afterward.
- **Expected:** Forms are captured then closed without saving; no Delete/Remove/submit is clicked; no real data is created or removed.
- **Maps to:** FR10

### T14 — Timeout resilience
- **Setup:** Force a short `JOB_TIMEOUT_SECONDS` (or a workflow that exceeds it).
- **Action:** Run the capture past the limit.
- **Expected:** The job stops gracefully, persists everything captured so far, and marks the run `completed` with `timedOut: true`.
- **Maps to:** FR11

### T15 — Least privilege + network posture
- **Setup:** Deployed stack.
- **Action:** Inspect IAM roles, subnet placement, and how credentials are passed.
- **Expected:** Task roles are scoped per the deployment spec; Fargate tasks run in private subnets with `assignPublicIp: DISABLED`; app credentials are runtime overrides, not baked into images or committed; data buckets block public access.
- **Maps to:** NFR2, NFR3

---

## Sign-off

| Role | Name | Date |
|---|---|---|
| Build lead | __________________ | __________ |
| Your engineering lead | __________________ | __________ |

All tests T1–T15 must pass against your app before `kit.json.status` is bumped to `published`.

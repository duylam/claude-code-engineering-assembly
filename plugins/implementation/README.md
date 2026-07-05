# Implementation Plugin

A structured workflow for taking a software development task from raw requirement to a verified change on a running app — validate completeness, then exercise the result with QA test automation.

## Overview

Development tasks fail most often not because the code is wrong, but because teams skip steps: they act on a requirement before it's clear, or ship a change without anyone actually driving it through the app to confirm it works. `/validate` checks whether a requirement is ready to act on.

Separately, the plugin bundles **QA test automation**: the `playwright-cli` skill drives a real browser, and the `automation-expert` agent executes manual test cases and reproduction steps step-by-step on web (via `playwright-cli`) or Android (via `adb`) — useful for verifying acceptance criteria, reproducing a bug, or running a regression check once a change is made.

## Skills

### `/validate [task_requirement] [output_location?]`

Checks whether a requirement (bug, story, or general task) has enough information to move forward with planning. Classifies the requirement, then checks it against the relevant completeness criteria.

- **Requires the requirement text itself** — it does not fetch tickets from Jira or any other tracker. If the requirement is missing or too unclear to classify, this is a fatal error rather than a guess.
- **On failure**: reports exactly which required elements are missing (e.g., "Pre-condition is missing — no environment or test account specified", "Acceptance Criteria not stated") so the author knows what to fix.
- **On success**: reports the result and type. There is no enrichment step — a complete requirement is handed off as-is.

| Argument | Required | Description |
|---|---|---|
| `task_requirement` | yes | The requirement text (bug report, user story, task description) |
| `output_location` | no | File path or directory. Defaults to inline if omitted. |

Completeness criteria by type:
- **bug** — three distinct categories: **pre-condition** (environment, login/credentials, under-test project or data), **steps to reproduce** (the ordered actions that trigger the defect), and **assertion** (expected vs. actual result)
- **story** — change description + acceptance criteria + scope
- **general_task** — mission/objective + acceptance criteria + scope

### `playwright-cli`

Browser automation for testing web pages and working with Playwright tests — open a page, take an accessibility snapshot, click/fill/type by ref, manage tabs and storage state, mock network requests, and record traces or video. See `skills/playwright-cli/SKILL.md` and its `references/` for the full command surface (session management, spec-driven testing, test generation, tracing, video recording).

## Agents

### `automation-expert`

Executes manual test cases and flows step-by-step — end-to-end flows, smoke tests, regression checks, bug reproduction, or acceptance criteria verification. Detects the target platform from the input:

- **Web** — drives the browser through the `playwright-cli` skill (never invoked as a shell command), with each flow running in its own named session so parallel flows don't collide.
- **Android** — inspects the UI via `adb exec-out uiautomator dump` and drives the emulator via `adb shell input`.

Before running any steps, it rebuilds and restarts the app under test (dev server for web, fresh APK install for Android) so results reflect the current codebase, not stale state. It inspects app state before every action, tries multiple locator fallbacks before failing a step, and reports a final PASS/FAIL table with per-step notes. Artifacts (screenshots, UI dumps) are only captured when a step explicitly asks for one, and are saved to the launching directory using a `<type>_<slug>_<timestamp>.<ext>` naming convention.

## System prerequisites

The `playwright-cli` skill and the web path of `automation-expert` require the `playwright-cli` command-line tool ([microsoft/playwright-cli](https://github.com/microsoft/playwright-cli)):

- **Node.js 18 or newer**.
- Install globally: `npm install -g @playwright/cli@latest` — or, if a global install isn't available, the skill falls back to `npx playwright-cli`.
- After installing, run `playwright-cli install --skills` to register the skill integration for coding agents.

The Android path of `automation-expert` requires **adb** (Android platform-tools) and a running emulator or device; no additional setup is needed for the web path beyond `playwright-cli` itself.

## Installation

```
/plugin install implementation@engineering-assembly
```

## Recommended workflow

```
/validate "Users report 500 errors when uploading files over 10MB on Safari. Expected: upload succeeds. Actual: server returns 500."
```

Then, once a change is in place, hand acceptance criteria or a bug's steps to reproduce to the `automation-expert` agent to drive the app and confirm the result:

```
Run these test steps against staging and report pass/fail: ...
```

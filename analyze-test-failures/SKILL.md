---
name: analyze-test-failures
description: Analyze failed e2e tests from a PR's CI run. Downloads CI artifacts using artifactsdownloader, finds test output files, then spins up one investigation agent per failed test (up to 3 concurrent) examining FRR dumps, controller logs, pod logs, and node logs to identify root causes.
disable-model-invocation: true
argument-hint: (no arguments needed — auto-detects from current branch)
---

# Analyze Failed E2E Tests

This skill is invoked from a branch that has an open PR. It automatically finds the PR for the current branch, locates the last failed CI run, downloads the artifacts, and investigates all failed tests.

## Inputs

No arguments required. Everything is derived from the current git branch.

## Step 0: Download CI Artifacts

1. Determine the current branch and repo:
   ```bash
   BRANCH=$(git rev-parse --abbrev-ref HEAD)
   ```
   Use `gh repo view --json owner,name` to get owner and repo.

2. Find the PR for this branch:
   ```bash
   gh pr view "$BRANCH" --json number,headRefOid -q '.number'
   ```
   If no PR exists for this branch, tell the user and stop.

3. Find the last failed workflow run for this PR:
   ```bash
   gh api "repos/{owner}/{repo}/actions/runs?branch=$BRANCH&status=failure&per_page=1" --jq '.workflow_runs[0].id'
   ```
   If no failed runs exist, tell the user and stop.

4. Run `artifactsdownloader` to download the artifacts:

   Create a directory named `logs_{run_id}`, move in there and run:

   ```bash
   artifactsdownloader {owner} {repo} {run_id}
   ```
   This will download test output files and log dumps.
   

   If `artifactsdownloader` is not installed, tell the user to install it:
   ```
   go install github.com/fedepaol/artifactsdownloader@latest
   ```
   Also remind them to set `GITHUB_TOKEN` if not already set.

5. Locate the test output files and log dump directories in the downloaded `logs_{runid}/` directory:
   - Test output files: `logs_{runid}/logs/*e2etests*.txt` or similar patterns
   - Log dump directories: `logs_{runid}/kind-logs-*/` directories

   For each test output file, pair it with the corresponding log dump directory (match by name, e.g., `4_e2etests (operator).txt` pairs with `kind-logs-operator/`).

## Step 1: Identify Failed Tests

For each test output file (there may be multiple — e.g., operator tests, systemd mode tests), read it and find all failed tests. Look for patterns like:
- `[FAILED]` markers
- `Summarizing N Failure` sections
- `FAIL!` summary lines

Skip test output files that have no failures (all tests passed).

For each failed test, extract:
- The full test name (e.g., `Routes between bgp and the fabric > should create ... > OVS bridge existing for single stack ipv4`)
- The error message (e.g., `curl 192.171.24.3:8090 failed: Host is unreachable`)
- The source file and line number where it failed
- The test steps that succeeded before the failure
- Any skipped tests caused by the failure (ordered containers)
- Which test suite it belongs to (operator, systemdmode, etc.)

Report the list of all failed tests across all suites to the user before proceeding.

## Step 2: Investigate Each Failure

For each failed test (up to 3), spin up an Agent in parallel. Each agent should investigate independently.

### What to tell each agent

Give the agent:
1. The exact test name and error message
2. The path to the logs directory
3. The relevant lines from the test output showing the failure context (steps, timing, error details)

### What each agent should investigate

Tell the agent to look at ALL of the following in the logs directory:

**Per-test dump directory** (if it exists — often named after the test):
- FRR dump files (`frrdump-*.log`) — check BGP sessions, EVPN routes, interface state
- CRD dumps (`L2VNIList.log`, `L3VNIList.log`, `UnderlayList.log`, `FRRConfigurationList.log`)
- Pod logs (`*_pods_logs.log`) — especially router, controller, frr-k8s, operator pods
- Pod specs (`*_pods_specs.log`)
- Events (`events.log`)
- Node info (`nodes.log`)

**Node-level logs** (in `pe-kind-control-plane/` and `pe-kind-worker/` subdirs):
- `journal.log` — systemd journal with controller, FRR, and reloader logs
- `kubelet.log` — pod scheduling and networking issues
- `openvswitch/` — OVS configuration and errors
- `containers/` or `pods/` — individual container logs

**Other logs**:
- `check_veths.log` — veth pair stability

Tell the agent to search for:
- Errors, warnings, panics in the failure timeframe
- FRR reload failures (status 500, socket errors, "Can not configure the local system as neighbor")
- BGP session state (Established vs Active/Connect)
- OVS bridge state (UP vs DOWN)
- Missing interfaces, routes, or VNI configuration
- Controller reconciliation errors
- Any asymmetry between nodes

### What each agent should report

Tell the agent to report:
1. What the test does step by step
2. The state of the system at failure time
3. Key errors/warnings found (with timestamps and log file references)
4. **5 possible reasons for the failure, ranked by likelihood**
5. Whether there is an obvious code fix

The agent should do research only, NOT make code changes.

## Step 3: Synthesize and Report

After all agents complete, synthesize their findings into a summary for the user:

For each failed test:
- **Test name**
- **Error**: one-line summary
- **Root cause**: the most likely explanation
- **5 possible reasons** (ranked)
- **Obvious fix?**: yes/no, and what it would be

If any failure has an obvious fix, ask the user if they want you to apply it.

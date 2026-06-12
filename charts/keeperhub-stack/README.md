# keeperhub-stack

Umbrella chart that deploys the KeeperHub execution pipeline as a **single Helm
release** so the whole stack can be upgraded and rolled back atomically.

## Why

Today each KeeperHub component is its own Helm release of the `common` chart
(`keeperhub-common`, `keeperhub-executor-common`, `keeperhub-schedule-common`,
`keeperhub-block-common`, `keeperhub-metrics-collector-common`), deployed by
separate CI workflows on independent triggers. A deploy therefore rolls the
components over a multi-minute window. While the dispatchers are already on the
new version but the executor/app are still cycling, triggers keep being created
that no runner picks up. Those executions sit until the 30-minute reaper marks
them `Execution timed out: no progress for 30 minutes`, which is classified as a
system error and pages on-call (incident Q1005I00XZ1ZPH).

Collapsing the components into one release lets `--atomic --wait` flip the whole
stack in one coordinated operation and roll **everything** back if any component
fails its readiness check, instead of leaving a half-upgraded stack.

## How it works

The chart depends on `common` once per component, aliased (`app`, `executor`,
`schedule`, `block`, `metricsCollector`). Each alias is an independent instance
of `common`, so the values under each alias key are passed straight through to
that subchart. Rendered resources are named `<release>-<alias>`
(`keeperhub-app`, `keeperhub-executor`, ...).

## Usage

```sh
# resolve the common subchart (vendored as charts/common-<ver>.tgz)
helm dependency build charts/keeperhub-stack

# atomic, all-or-nothing deploy of the whole stack
helm upgrade --install keeperhub charts/keeperhub-stack \
  -f keeperhub/deploy/keeperhub/<env>/values.yaml \
  --namespace keeperhub \
  --atomic --wait --timeout 15m
```

Real image tags, env vars and SSM-backed secrets come from the per-environment
values files in the keeperhub repo (`-f`), exactly as the standalone releases
work today. The defaults in `values.yaml` are placeholders.

Disable a component for an environment that does not run it:

```yaml
metricsCollector:
  enabled: false
```

## Notes / caveats

- `--wait` blocks until every Deployment reaches its ready replica count, so set
  `--timeout` to cover the slowest component plus image pulls.
- DB migrations run as the `db-migration` initContainer on the `app` component.
  `--atomic` rolls pods back but not applied schema, so migrations must remain
  backward compatible (already required).
- Atomic deploy shrinks the rollover window to a single coordinated flip; pair
  it with graceful drain on the dispatchers (a `preStop` that stops emitting
  triggers before termination) to fully eliminate orphaned executions.
- CronJobs (reaper, execution digest) are not gated by `--wait`; add them as
  further aliases if you want them in the same release.

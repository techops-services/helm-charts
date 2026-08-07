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

## Optional bundled data plane

A self-hosted install can let the chart run its own PostgreSQL and queue rather
than requiring an operator to bring both. Both default to `false`, so nothing
changes for environments that already supply them, which includes staging and
production.

```yaml
postgresql:
  bundled: true
  instances: 3                       # HA; needs that many schedulable nodes
  credentialsSecret: keeperhub-db    # kubernetes.io/basic-auth
queue:
  bundled: true
  persistence:
    enabled: true
```

High availability, failover, backup and restore for the database are
CloudNativePG's, not this chart's: `postgresql.backup` and `postgresql.recovery`
are passed through to the operator verbatim.

### These are templates, not dependencies

Deliberately, and it should stay that way.

Helm fails chart load when a `dependencies:` entry has no matching archive under
`charts/`, and it decides that by dependency **name** without ever reading
`condition`. So a dependency that is disabled by default would still have to be
vendored as a committed `.tgz` — and this repo's CI has no
`helm dependency build` step, which is also why `common` is vendored today. A
second hand-maintained binary in git, for something off by default, is a poor
trade against two template files.

CloudNativePG could not be a subchart in any case. Its CRDs are cluster-scoped,
and CRDs cannot be installed reliably by a condition-gated subchart inside a
single `--atomic` release.

### CloudNativePG is a prerequisite

The operator must already be installed cluster-wide; this chart renders only the
`Cluster` object.

```sh
kubectl apply --server-side -f \
  https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.24/releases/cnpg-1.24.1.yaml
```

Rendering is not gated on `.Capabilities.APIVersions`, because that is false
under `helm template` and the enabled path would then silently render nothing
and prove nothing in CI. Check for the CRD before installing instead.

### Pinning the endpoints

`common` renders env values without `tpl`, so a values file cannot compute a
hostname — `{{ .Release.Name }}-postgres` would ship literally. The endpoints
are therefore pinned literals in the consuming values file, and this chart
verifies them at render time via `strictEndpointCheck`. `helm install` prints
the exact strings to use.

Both mismatches are worth guarding because neither looks like a failure:

- A wrong **queue** URL still works at the transport layer, because ElasticMQ
  resolves the queue from the last path segment and ignores the host. The URL is
  an HMAC signing input, so every message then fails verification and is
  dropped while all pods stay healthy.
- A wrong **database** host still resolves, but the application forces
  `sslmode=verify-full` on any host not ending `.svc.cluster.local`, which then
  fails TLS against CloudNativePG's in-cluster certificate. Note this rules out
  CNPG's own generated `uri` and `fqdn-uri` Secret keys — compose the connection
  string with the full `<cluster>-rw.<namespace>.svc.cluster.local` form.

### Queue characteristics

ElasticMQ has no clustering, so the queue is single-node by design: a restart is
a brief outage, not a failover. `replicas` is deliberately not configurable — a
second replica would be a second independent queue that silently splits
messages.

Persistence is on by default so that outage is not also data loss. Verified on
`elasticmq-native:1.6.16`: the native image persists messages, `DeleteMessage`
is persisted so processed work is not redelivered after a restart, and the H2
lock released cleanly across 13 consecutive restarts with the grace period and
`preStop` this chart sets.

One behaviour to know: `PurgeQueue` is **not** persisted, so purged messages
reappear after a restart. Nothing in the application calls it — only tests do.

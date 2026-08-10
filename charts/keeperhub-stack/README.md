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

A `type: kv` env value is written out verbatim, so a values file using one cannot
compute a hostname - `{{ .Release.Name }}-postgres` would ship literally. Since
`common` 0.6.0 a value can instead be declared `type: template`, which is
rendered through `tpl` and can therefore reach `.Values.global` and
`.Release.Namespace`:

```yaml
global:
  queueName: elasticmq

app:
  env:
    SQS_QUEUE_URL:
      type: template
      value: "http://{{ .Values.global.queueName }}.{{ .Release.Namespace }}.svc.cluster.local:9324/000000000000/keeperhub-workflow-queue"
```

That removes most of the opportunity for drift, but not all of it, so
`strictEndpointCheck` still verifies the result at render time. It renders a
`type: template` value before comparing it, and ignores `type: secret`
altogether. `helm install` prints the exact strings to use.

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

## Install secrets

`secrets.generate` is off by default. Staging and production get these values
from SSM through External Secrets and must keep doing so; this exists for an
install that has no secret manager, where the alternative is a person generating
eight values by hand.

Two of them have formats that are not interchangeable and fail in ways that do
not look like a format problem, which is the main reason this belongs in the
chart rather than in an instruction:

- `INTERNAL_SERVICE_HMAC_SECRET` and `AGENTIC_WALLET_HMAC_KMS_KEY` must base64
  decode to exactly 32 bytes
- `INTEGRATION_ENCRYPTION_KEY` must be 64 hex characters, aes-256-gcm material

Each key resolves in order: an explicit value in `secrets.values`, then the value
already in the cluster, then a generated one. The middle step is what stops an
upgrade rotating a key.

`SENDGRID_API_KEY` and the three `TURNKEY_` keys are never generated. They are
rendered empty instead, because an invented API key replaces a clean
unconfigured state with 401s, and the components reference the Secrets with a
plain `secretKeyRef` that has no `optional` field - a missing Secret is
`CreateContainerConfigError`, not a degraded install.

### Two limits worth knowing before you rely on it

**`lookup` is empty during templating.** The "keep what is already installed"
step reads the cluster, and `helm template` and `--dry-run` do not. A rendered
manifest therefore shows fresh values every time, and a
`helm template | kubectl apply` pipeline **rotates these keys on every run**.
Losing `INTEGRATION_ENCRYPTION_KEY` orphans every stored integration credential.
If you deploy that way, pin every key in `secrets.values` or set
`generate: false` and create the Secrets yourself.

**Changing a secret does not restart anything.** An env var is resolved once, at
pod start, so updating a Secret leaves the running pods on the old value. Roll
them yourself:

```sh
kubectl rollout restart deployment -n <namespace> -l app.kubernetes.io/instance=<release>
```

A checksum annotation would do this automatically, but an umbrella chart cannot
write a pod annotation into a subchart's template.

### Secrets are kept on rollback

Every generated Secret carries `helm.sh/resource-policy: keep`. Without it an
`--atomic` rollback of a failed first install deletes the key the database was
just bootstrapped with, and the credentials that encrypt stored integrations.
That is not theoretical - the same annotation is on the `Cluster` and its PVCs
for exactly the reason it was proven necessary there.

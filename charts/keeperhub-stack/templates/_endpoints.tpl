{{/*
Endpoints for the optional bundled data plane, and a guard that the values
pinning them agree with what this chart actually renders.

Why a guard is needed at all: `common` renders a `type: kv` env value verbatim,
so a hostname written that way is a pinned literal that nothing keeps in step
with the chart. `type: template` (common 0.6.0) lets the value be computed
instead, which removes most of the opportunity for drift but not all of it - an
operator can still compute the wrong thing. This chart's job either way is to
make a disagreement fail loudly at render time rather than silently at runtime.

Silently is the operative word. A wrong queue URL is not a connection error:
ElasticMQ resolves the queue from the last path segment and ignores the host,
so requests succeed while every message fails HMAC verification and is dropped.
A wrong database host is not a connection error either: anything not ending
.svc.cluster.local gets sslmode=verify-full forced onto it by the application,
which then fails TLS against a self-signed in-cluster certificate.
*/}}

{{/* Name of the bundled CNPG Cluster object. */}}
{{- define "keeperhub-stack.pgName" -}}
{{- .Values.postgresql.nameOverride | default (printf "%s-postgres" .Release.Name) -}}
{{- end -}}

{{/*
Host applications must use for the bundled database.

CNPG creates <cluster>-rw, -ro and -r Services. -rw always points at the current
primary and is repointed automatically on failover, which is what makes
instances > 1 transparent to the application. Everything KeeperHub does is
read-write, so there is no read-splitting to consider.

The fully qualified .svc.cluster.local form is required, not optional: the
application only skips forcing sslmode=verify-full for that suffix. CNPG's own
generated `uri` and `fqdn-uri` Secret keys use shorter forms and will fail TLS.
*/}}
{{- define "keeperhub-stack.pgHost" -}}
{{- printf "%s-rw.%s.svc.cluster.local" (include "keeperhub-stack.pgName" .) .Release.Namespace -}}
{{- end -}}

{{/*
Name of the basic-auth Secret CloudNativePG bootstraps the database from.

Derived in one place because two templates need the same answer. secrets.yaml
writes this Secret and postgres-cnpg.yaml points the Cluster at it; if they
disagreed, the operator would generate its own credentials and the connection
string the chart composed would authenticate against nothing.
*/}}
{{- define "keeperhub-stack.pgCredentialsSecret" -}}
{{- .Values.postgresql.credentialsSecret | default (printf "%s-db-credentials" .Release.Name) -}}
{{- end -}}

{{/* Base endpoint for the bundled queue. */}}
{{- define "keeperhub-stack.queueEndpoint" -}}
{{- printf "http://%s.%s.svc.cluster.local:%v" .Values.queue.name .Release.Namespace .Values.queue.port -}}
{{- end -}}

{{/* Full URL of a named queue, which is what components must be configured with. */}}
{{- define "keeperhub-stack.queueUrl" -}}
{{- printf "%s/%s/%s" (include "keeperhub-stack.queueEndpoint" .root) .root.Values.queue.accountId .name -}}
{{- end -}}

{{/*
Fail the render when the value pinning an endpoint disagrees with what we render.

Fires for env entries that exist and are either type: kv or type: template. A
bring-your-own install using type: secret passes untouched, and so does
test-values.yaml, which sets no env at all. Set strictEndpointCheck: false to
bypass for topologies this does not anticipate.

A type: template value is rendered before it is compared, because the raw string
is a template and comparing it would be meaningless. The rendering context here
mirrors what the `common` subchart sees: the component's own values with the
parent's `global` map merged in, and the shared `.Release`. Those two are what an
endpoint value is built from. A template reaching for anything else resolves
against the parent instead, which will show up as a guard failure rather than a
silent pass.
*/}}
{{- define "keeperhub-stack.checkEnv" -}}
{{- $c := index $.ctx.Values $.alias -}}
{{- with $c -}}
{{- $e := .env | default dict -}}
{{- with (index $e $.key) -}}
{{- $type := .type | default "" -}}
{{- $raw := .value | toString -}}
{{- if or (eq $type "kv") (eq $type "template") -}}
{{- $got := $raw -}}
{{- if eq $type "template" -}}
{{- $subValues := merge (deepCopy $c) (dict "global" ($.ctx.Values.global | default dict)) -}}
{{- $subCtx := dict "Values" $subValues "Release" $.ctx.Release "Chart" $.ctx.Chart "Capabilities" $.ctx.Capabilities "Template" $.ctx.Template -}}
{{- $got = tpl $raw $subCtx -}}
{{- end -}}
{{- if not (contains $.want $got) -}}
{{- fail (printf "\n\n%s.env.%s is %q but the bundled %s renders %q.\n\nA mismatch here does not surface as a connection error, so it is checked at render time.\nFix the values file, or set strictEndpointCheck: false to bypass.\n" $.alias $.key $got $.what $.want) -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "keeperhub-stack.validateEndpoints" -}}
{{- if .Values.strictEndpointCheck -}}

{{- if .Values.postgresql.bundled -}}
{{- $want := include "keeperhub-stack.pgHost" . -}}
{{- range $alias := list "app" "executor" "schedule" "block" "metricsCollector" -}}
{{- range $key := list "DATABASE_URL" "WORKFLOW_POSTGRES_URL" -}}
{{- include "keeperhub-stack.checkEnv" (dict "ctx" $ "alias" $alias "key" $key "want" $want "what" "database") -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- if .Values.queue.bundled -}}
{{- $endpoint := include "keeperhub-stack.queueEndpoint" . -}}
{{- range $alias := list "app" "executor" "schedule" "block" -}}
{{- range $key := list "AWS_ENDPOINT_URL" "SQS_QUEUE_URL" "SQS_DLQ_URL" -}}
{{- include "keeperhub-stack.checkEnv" (dict "ctx" $ "alias" $alias "key" $key "want" $endpoint "what" "queue") -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- end -}}
{{- end -}}

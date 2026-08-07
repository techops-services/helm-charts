{{/*
Endpoints for the optional bundled data plane, and a guard that the values
pinning them agree with what this chart actually renders.

Why a guard is needed at all: the `common` subchart renders env values with
`value: {{ $v.value | quote }}` and never calls `tpl`, so an operator cannot
write `{{ .Release.Name }}-postgres` in a values file and have it resolve - it
would ship literally. The hostname therefore has to be a pinned literal, and
this chart's job is to make a wrong literal fail loudly at render time rather
than silently at runtime.

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

{{/* Base endpoint for the bundled queue. */}}
{{- define "keeperhub-stack.queueEndpoint" -}}
{{- printf "http://%s.%s.svc.cluster.local:%v" .Values.queue.name .Release.Namespace .Values.queue.port -}}
{{- end -}}

{{/* Full URL of a named queue, which is what components must be configured with. */}}
{{- define "keeperhub-stack.queueUrl" -}}
{{- printf "%s/%s/%s" (include "keeperhub-stack.queueEndpoint" .root) .root.Values.queue.accountId .name -}}
{{- end -}}

{{/*
Fail the render when a pinned literal disagrees with what we render.

Only fires for env entries that exist AND are type: kv, so a bring-your-own
install using type: secret passes untouched, and so does test-values.yaml, which
sets no env at all. Set strictEndpointCheck: false to bypass for topologies this
does not anticipate.
*/}}
{{- define "keeperhub-stack.checkEnv" -}}
{{- $c := index $.ctx.Values $.alias -}}
{{- with $c -}}
{{- $e := .env | default dict -}}
{{- with (index $e $.key) -}}
{{- if eq (.type | default "") "kv" -}}
{{- if not (contains $.want (.value | toString)) -}}
{{- fail (printf "\n\n%s.env.%s is %q but the bundled %s renders %q.\n\nA mismatch here does not surface as a connection error, so it is checked at render time.\nFix the values file, or set strictEndpointCheck: false to bypass.\n" $.alias $.key (.value | toString) $.what $.want) -}}
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

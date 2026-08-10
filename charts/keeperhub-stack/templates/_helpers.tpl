{{/*
Labels for the optional bundled data-plane objects.

The five component sub-releases get their labels from `common`; these objects
are rendered by the umbrella itself, so they need their own.
*/}}

{{- define "keeperhub-stack.commonLabels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: keeperhub
{{- end -}}

{{- define "keeperhub-stack.queueSelectorLabels" -}}
app: {{ .Values.queue.name }}
app.kubernetes.io/name: {{ .Values.queue.name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "keeperhub-stack.queueLabels" -}}
{{ include "keeperhub-stack.commonLabels" . }}
app: {{ .Values.queue.name }}
app.kubernetes.io/name: {{ .Values.queue.name }}
app.kubernetes.io/component: queue
{{- end -}}

{{- define "keeperhub-stack.pgLabels" -}}
{{ include "keeperhub-stack.commonLabels" . }}
app.kubernetes.io/name: {{ include "keeperhub-stack.pgName" . }}
app.kubernetes.io/component: database
{{- end -}}

{{/*
Resolve one install secret: an explicit value, else what is already stored in
the cluster, else a generated one. Used only by templates/secrets.yaml, and
defined here because helm parses `define` at chart load and rejects one nested
inside the `if` that gates that file.

Formats are not interchangeable:
  b64  base64 of exactly 32 bytes, for the two HMAC keys
  hex  64 hex characters, aes-256-gcm material
  any  passed through, never generated - an invented API key is worse than none

The stored value is read with `lookup`, which returns nothing during
`helm template` and `--dry-run`. That is why a rendered manifest is not a record
of what is installed, and why values.yaml documents the
`helm template | kubectl apply` hazard.
*/}}
{{- define "keeperhub-stack.secretValue" -}}
{{- $explicit := index .given .key | default "" -}}
{{- if $explicit -}}
{{- $explicit -}}
{{- else -}}
{{- $stored := "" -}}
{{- $existing := lookup "v1" "Secret" .ns .secretName -}}
{{- if $existing -}}
{{- $encoded := index ($existing.data | default dict) .key | default "" -}}
{{- if $encoded -}}
{{- $stored = b64dec $encoded -}}
{{- end -}}
{{- end -}}
{{- if $stored -}}
{{- $stored -}}
{{- else if eq .format "b64" -}}
{{- randBytes 32 -}}
{{- else if eq .format "hex" -}}
{{- sha256sum (randAlphaNum 64) -}}
{{- end -}}
{{- end -}}
{{- end -}}

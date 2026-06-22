{{/*
Expand the name of the chart.
*/}}
{{- define "common.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end -}}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "common.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "common.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "common.labels" -}}
helm.sh/chart: {{ include "common.chart" . }}
{{ include "common.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "common.selectorLabels" -}}
app.kubernetes.io/name: {{ include "common.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/serviceName: {{ include "common.fullname" .}}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "common.serviceAccountName" -}}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}

{{/*
IRSA preflight init container - hard gate that proves IRSA works (assume-role +
a read-only AWS call) before the main container starts. Rendered as a single
initContainers list entry; include with `nindent 8`. The SQS get-queue-url probe
is the only truly read-only call within the role's queue policy.
*/}}
{{- define "common.irsaPreflightInitContainer" -}}
{{- $ic := .Values.serviceAccount.irsaCheck.initContainer -}}
- name: irsa-preflight
  image: {{ .Values.serviceAccount.irsaCheck.image }}
  command: ["/bin/sh", "-c"]
  args:
    - |
      set -euo pipefail
      echo "[irsa-preflight] sts get-caller-identity"
      aws sts get-caller-identity
      echo "[irsa-preflight] sqs get-queue-url ${IRSA_PREFLIGHT_QUEUE_NAME}"
      aws sqs get-queue-url --queue-name "${IRSA_PREFLIGHT_QUEUE_NAME}" --region "${IRSA_PREFLIGHT_REGION}"
  env:
    - name: IRSA_PREFLIGHT_REGION
      value: {{ $ic.region | quote }}
    - name: IRSA_PREFLIGHT_QUEUE_NAME
      value: {{ $ic.queueName | quote }}
  resources:
    {{- if $ic.resources }}
    {{- toYaml $ic.resources | nindent 4 }}
    {{- else }}
    requests:
      cpu: 25m
      memory: 64Mi
    limits:
      cpu: 100m
      memory: 128Mi
    {{- end }}
{{- end }}

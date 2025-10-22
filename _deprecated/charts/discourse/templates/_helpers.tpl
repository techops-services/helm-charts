{{/*
Expand the name of the chart.
*/}}
{{- define "discourse.name" -}}
{{- default .Chart.Name .Values.global.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "discourse.fullname" -}}
{{- if .Values.global.fullnameOverride -}}
{{- .Values.global.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.global.nameOverride -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "discourse.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" -}}
{{- end -}}

{{/*
Common labels.
*/}}
{{- define "discourse.labels" -}}
helm.sh/chart: {{ include "discourse.chart" . }}
app.kubernetes.io/name: {{ include "discourse.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Chart.AppVersion }}
app.kubernetes.io/version: {{ . | quote }}
{{- end }}
{{- end -}}

{{/*
Selector labels.
*/}}
{{- define "discourse.selectorLabels" -}}
app.kubernetes.io/name: {{ include "discourse.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
Service account name.
*/}}
{{- define "discourse.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- if .Values.serviceAccount.name -}}
{{- .Values.serviceAccount.name -}}
{{- else -}}
{{- include "discourse.fullname" . -}}
{{- end -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{/*
PostgreSQL resource names.
*/}}
{{- define "discourse.postgresql.fullname" -}}
{{- printf "%s-postgresql" (include "discourse.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "discourse.postgresql.serviceName" -}}
{{- include "discourse.postgresql.fullname" . -}}
{{- end -}}

{{/*
Redis resource names.
*/}}
{{- define "discourse.redis.fullname" -}}
{{- printf "%s-redis" (include "discourse.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "discourse.redis.serviceName" -}}
{{- include "discourse.redis.fullname" . -}}
{{- end -}}

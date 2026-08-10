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
Render a values string through tpl, but only when it actually contains a Go
template action. A string with no "{{" cannot change under tpl, so the guard
makes this provably identity for every values file written before this chart
supported templating. That is what keeps the upgrade to 0.6.0 render-identical
for existing charts, which cannot all be inspected from one repository.

Call with a dict: {{ include "common.render" (dict "value" .Values.image.repository "ctx" $) }}
The ctx must be the root context, because tpl evaluates the string against it -
that is what lets a values file reach .Values.global and .Release.
*/}}
{{- define "common.render" -}}
{{/*
An absent value renders empty, as it did before this helper existed. `toString`
on nil produces the literal "<nil>", which would reach the manifest - a cronjob
that simply omits imagePullPolicy is the case that finds it.

kindIs rather than a truth test, so a legitimate false or 0 still renders.
*/}}
{{- $value := "" -}}
{{- if not (kindIs "invalid" .value) -}}
{{- $value = toString .value -}}
{{- end -}}
{{- if contains "{{" $value -}}
{{- tpl $value .ctx -}}
{{- else -}}
{{- $value -}}
{{- end -}}
{{- end }}

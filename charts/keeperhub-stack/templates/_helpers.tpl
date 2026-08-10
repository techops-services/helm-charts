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

{{- define "taskapp.name" -}}
{{- .Chart.Name -}}
{{- end -}}

{{- define "taskapp.labels" -}}
app.kubernetes.io/name: {{ include "taskapp.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Values.image.tag | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end -}}

{{- define "taskapp.selectorLabels" -}}
app.kubernetes.io/name: {{ include "taskapp.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

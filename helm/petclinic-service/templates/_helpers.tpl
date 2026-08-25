{{/*
Common labels applied to every resource.
Release name == service name (e.g. "customers-service").
*/}}
{{- define "petclinic-service.labels" -}}
app.kubernetes.io/name: {{ .Release.Name }}
app.kubernetes.io/part-of: petclinic
app.kubernetes.io/managed-by: Helm
app.kubernetes.io/component: {{ .Values.component }}
{{- end }}

{{/*
Selector labels used in matchLabels and pod template labels.
*/}}
{{- define "petclinic-service.selectorLabels" -}}
app.kubernetes.io/name: {{ .Release.Name }}
{{- end }}

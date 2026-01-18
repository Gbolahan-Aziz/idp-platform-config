{{/*
Chart name
*/}}
{{- define "idp.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" -}}
{{- end -}}

{{/*
Service name (Kubernetes-safe)
*/}}
{{- define "idp.name" -}}
{{- required "service.name is required" .Values.service.name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Team name (Kubernetes-safe)
*/}}
{{- define "idp.team" -}}
{{- required "service.team is required" .Values.service.team | lower | replace "_" "-" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Environment name (Kubernetes-safe)
*/}}
{{- define "idp.env" -}}
{{- required "service.env is required" .Values.service.env | lower | replace "_" "-" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Namespace convention: <team>-<env>
Example: payments-dev
*/}}
{{- define "idp.namespace" -}}
{{- printf "%s-%s" (include "idp.team" .) (include "idp.env" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Full resource name: <service>
(We keep it just service name to avoid 63-char issues, but labels carry team/env.)
If you prefer <team>-<service>, tell me and we’ll switch.
*/}}
{{- define "idp.fullname" -}}
{{- include "idp.name" . -}}
{{- end -}}

{{/*
Common labels
*/}}
{{- define "idp.labels" -}}
app.kubernetes.io/name: {{ include "idp.name" . }}
app.kubernetes.io/instance: {{ include "idp.name" . }}
app.kubernetes.io/managed-by: Helm
app.kubernetes.io/part-of: idp
helm.sh/chart: {{ include "idp.chart" . }}
idp.azeex.com/team: {{ include "idp.team" . }}
idp.azeex.com/env: {{ include "idp.env" . }}
idp.azeex.com/type: {{ .Values.service.type | default "stateless" }}
{{- end -}}

{{/*
Selector labels (stable)
*/}}
{{- define "idp.selectorLabels" -}}
app.kubernetes.io/name: {{ include "idp.name" . }}
app.kubernetes.io/instance: {{ include "idp.name" . }}
{{- end -}}

{{/*
Resolve resource profile into requests/limits.
Fails fast if profile doesn't exist in profiles map.
*/}}
{{- define "idp.profile" -}}
{{- $p := required "resources.profile is required" .Values.resources.profile -}}
{{- $profile := index .Values.profiles $p -}}
{{- if not $profile -}}
{{- fail (printf "resources.profile '%s' not found in profiles" $p) -}}
{{- end -}}
{{- $profile | toYaml -}}
{{- end -}}

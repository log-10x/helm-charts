{{/*
Expand the name of the chart.
*/}}
{{- define "log10x-cron.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this
(by the DNS naming spec). If release name contains chart name it is used as a
full name.
*/}}
{{- define "log10x-cron.fullname" -}}
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
{{- define "log10x-cron.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "log10x-cron.labels" -}}
helm.sh/chart: {{ include "log10x-cron.chart" . }}
{{ include "log10x-cron.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "log10x-cron.selectorLabels" -}}
app.kubernetes.io/name: {{ include "log10x-cron.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "log10x-cron.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "log10x-cron.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
The compiler image. log10x/compiler-10x carries the source-fetch toolchain the
pull stage shells out to (git, docker CLI, helm); the lean pipeline-10x runtime
image does not.
*/}}
{{- define "log10x-cron.image" -}}
{{- $tag := default .Chart.AppVersion .Values.image.tag -}}
{{- printf "%s:%s" .Values.image.repository $tag -}}
{{- end }}

{{/*
Resolve the licence JWT the chart should place in its own Secret.

Returns the empty string when the token is not the chart's to manage, which is
either because tenx.licenseSecret names a Secret someone else owns, or because
nothing was supplied at all.

log10xApiKey and log10xLicense are read as the licence because that is the only
thing they could ever have been. TENX_API_KEY, the variable log10xApiKey used to
set, is read by nothing: it does not appear in the compiler image's config tree,
where the compile bootstrap resolves

    licenseKey:  $=TenXEnv.get("TENX_LICENSE_KEY", "NO-LICENSE")
    licenseFile: $=TenXEnv.get("TENX_LICENSE_FILE")

Rather than leave those installs broken, the value is carried over.
*/}}
{{- define "log10x-cron.licenseJwt" -}}
{{- if .Values.tenx.licenseSecret -}}
{{- else if .Values.tenx.licenseJwt -}}
{{- .Values.tenx.licenseJwt -}}
{{- else if .Values.log10xLicense -}}
{{- .Values.log10xLicense -}}
{{- else if .Values.log10xApiKey -}}
{{- .Values.log10xApiKey -}}
{{- end -}}
{{- end }}

{{/*
Name of the Secret that holds the licence: the caller's when tenx.licenseSecret
is set, otherwise the one this chart renders.
*/}}
{{- define "log10x-cron.licenseSecretName" -}}
{{- if .Values.tenx.licenseSecret -}}
{{- .Values.tenx.licenseSecret -}}
{{- else -}}
{{- printf "%s-tenx-license" (include "log10x-cron.fullname" .) -}}
{{- end -}}
{{- end }}

{{/*
Validate tenx.licenseDelivery. "file" projects the Secret and sets
TENX_LICENSE_FILE, "env" injects TENX_LICENSE_KEY.
*/}}
{{- define "log10x-cron.licenseDelivery" -}}
{{- $raw := .Values.tenx.licenseDelivery -}}
{{- if kindIs "invalid" $raw -}}
{{- fail "cron-10x: tenx.licenseDelivery is unset or null. Set it to \"file\" or \"env\"." -}}
{{- end -}}
{{- $v := $raw | toString -}}
{{- if not (has $v (list "file" "env")) -}}
{{- fail (printf "cron-10x: tenx.licenseDelivery must be \"file\" or \"env\", got %q." $v) -}}
{{- end -}}
{{- $v -}}
{{- end }}

{{/*
Absolute path the licence is projected to under "file" delivery.
*/}}
{{- define "log10x-cron.licenseFilePath" -}}
{{- printf "/etc/tenx/license/%s" (.Values.tenx.licenseSecretKey | default "license-jwt") -}}
{{- end }}

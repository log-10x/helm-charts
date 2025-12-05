{{/*
Expand the name of the chart.
*/}}
{{- define "log10x-quarkus.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "log10x-quarkus.fullname" -}}
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
{{- define "log10x-quarkus.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "log10x-quarkus.labels" -}}
helm.sh/chart: {{ include "log10x-quarkus.chart" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "log10x-quarkus.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "log10x-quarkus.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Check if GitHub integration is enabled
Returns "true" if either github.config or github.symbols is defined
*/}}
{{- define "log10x-quarkus.githubEnabled" -}}
{{- if and .Values.github (or .Values.github.config .Values.github.symbols) -}}
true
{{- end -}}
{{- end -}}

{{/*
GitHub init container definition
Clones config and/or symbols repositories to an emptyDir volume
*/}}
{{- define "log10x-quarkus.githubInitContainer" -}}
- name: github-clone
  image: ghcr.io/log-10x/github-config-fetcher:0.4.0
  env:
    - name: GITHUB_TOKEN
      valueFrom:
        secretKeyRef:
          name: {{ include "log10x-quarkus.fullname" . }}-github-token
          key: token
  args:
    {{- if .Values.github.config }}
    - "--config-repo"
    - "https://github.com/{{ .Values.github.config.repo }}.git"
    {{- if .Values.github.config.branch }}
    - "--config-branch"
    - "{{ .Values.github.config.branch }}"
    {{- end }}
    {{- end }}
    {{- if .Values.github.symbols }}
    - "--symbols-repo"
    - "https://github.com/{{ .Values.github.symbols.repo }}.git"
    {{- if .Values.github.symbols.branch }}
    - "--symbols-branch"
    - "{{ .Values.github.symbols.branch }}"
    {{- end }}
    {{- if .Values.github.symbols.path }}
    - "--symbols-path"
    - "{{ .Values.github.symbols.path }}"
    {{- end }}
    {{- end }}
  volumeMounts:
    - name: github-data
      mountPath: /data
{{- end -}}

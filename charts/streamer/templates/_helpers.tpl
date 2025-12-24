{{/*
Expand the name of the chart.
*/}}
{{- define "log10x-streamer.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "log10x-streamer.fullname" -}}
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
{{- define "log10x-streamer.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "log10x-streamer.labels" -}}
helm.sh/chart: {{ include "log10x-streamer.chart" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "log10x-streamer.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "log10x-streamer.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Check if GitHub integration is enabled
Returns "true" if either github.config or github.symbols is defined
*/}}
{{- define "log10x-streamer.githubEnabled" -}}
{{- if and .Values.github (or .Values.github.config .Values.github.symbols) -}}
true
{{- end -}}
{{- end -}}

{{/*
GitHub init container definition
Clones config and/or symbols repositories to an emptyDir volume
*/}}
{{- define "log10x-streamer.githubInitContainer" -}}
- name: github-clone
  image: "{{ .Values.githubConfigFetcherImage.repository }}:{{ .Values.githubConfigFetcherImage.tag }}"
  imagePullPolicy: {{ .Values.githubConfigFetcherImage.pullPolicy }}
  env:
    - name: GITHUB_TOKEN
      valueFrom:
        secretKeyRef:
          name: {{ include "log10x-streamer.fullname" . }}-github-token
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

{{/*
Generate environment variables for cluster roles
Takes a dict with keys: cluster (cluster object), values (root values object)
Generates env vars based on roles array and global queue URLs
*/}}
{{- define "log10x-streamer.roleEnvVars" -}}
{{- $cluster := .cluster -}}
{{- $values := .values -}}
{{- $hasIndex := has "index" $cluster.roles -}}
{{- $hasQuery := has "query" $cluster.roles -}}
{{- $hasStream := has "stream" $cluster.roles -}}
{{- if and $hasIndex $values.indexQueueUrl }}
- name: TENX_QUARKUS_INDEX_QUEUE_URL
  value: {{ $values.indexQueueUrl | quote }}
{{- end }}
{{- if and $hasQuery $values.queryQueueUrl }}
- name: TENX_QUARKUS_QUERY_QUEUE_URL
  value: {{ $values.queryQueueUrl | quote }}
{{- end }}
{{- if and $hasQuery $values.subQueryQueueUrl }}
- name: TENX_QUARKUS_SUBQUERY_QUEUE_URL
  value: {{ $values.subQueryQueueUrl | quote }}
{{- end }}
{{- if and $hasStream $values.streamQueueUrl }}
- name: TENX_QUARKUS_STREAM_QUEUE_URL
  value: {{ $values.streamQueueUrl | quote }}
{{- end }}
{{- if $values.subQueryQueueUrl }}
- name: TENX_INVOKE_PIPELINE_SCAN_ENDPOINT
  value: {{ $values.subQueryQueueUrl | quote }}
{{- end }}
{{- if $values.streamQueueUrl }}
- name: TENX_INVOKE_PIPELINE_STREAM_ENDPOINT
  value: {{ $values.streamQueueUrl | quote }}
{{- end }}
{{- end -}}

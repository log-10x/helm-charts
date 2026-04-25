{{/*
Expand the name of the chart.
*/}}
{{- define "log10x-retriever.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "log10x-retriever.fullname" -}}
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
{{- define "log10x-retriever.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "log10x-retriever.labels" -}}
helm.sh/chart: {{ include "log10x-retriever.chart" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "log10x-retriever.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "log10x-retriever.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Check if any Git cloning is needed
Returns "true" if either config.git or symbols.git is enabled
*/}}
{{- define "log10x-retriever.gitEnabled" -}}
{{- if or (and .Values.config .Values.config.git .Values.config.git.enabled) (and .Values.symbols .Values.symbols.git .Values.symbols.git.enabled) -}}
true
{{- end -}}
{{- end -}}

{{/*
Check if any config/symbols loading is enabled (git or volume)
*/}}
{{- define "log10x-retriever.configEnabled" -}}
{{- if or (and .Values.config .Values.config.git .Values.config.git.enabled) (and .Values.config .Values.config.volume .Values.config.volume.enabled) (and .Values.symbols .Values.symbols.git .Values.symbols.git.enabled) (and .Values.symbols .Values.symbols.volume .Values.symbols.volume.enabled) -}}
true
{{- end -}}
{{- end -}}

{{/*
Git init container definition
Clones config and/or symbols repositories to an emptyDir volume
*/}}
{{- define "log10x-retriever.gitInitContainer" -}}
- name: tenx-git-config
  image: "{{ .Values.configFetcherImage.repository }}:{{ .Values.configFetcherImage.tag }}"
  imagePullPolicy: {{ .Values.configFetcherImage.pullPolicy }}
  env:
    - name: GIT_TOKEN
      valueFrom:
        secretKeyRef:
          name: {{ include "log10x-retriever.fullname" . }}-git-token
          key: token
  args:
    {{- if and .Values.config .Values.config.git .Values.config.git.enabled }}
    - "--config-repo"
    - {{ .Values.config.git.url | quote }}
    {{- if .Values.config.git.branch }}
    - "--config-branch"
    - {{ .Values.config.git.branch | quote }}
    {{- end }}
    {{- end }}
    {{- if and .Values.symbols .Values.symbols.git .Values.symbols.git.enabled }}
    - "--symbols-repo"
    - {{ .Values.symbols.git.url | quote }}
    {{- if .Values.symbols.git.branch }}
    - "--symbols-branch"
    - {{ .Values.symbols.git.branch | quote }}
    {{- end }}
    {{- if .Values.symbols.git.path }}
    - "--symbols-path"
    - {{ .Values.symbols.git.path | quote }}
    {{- end }}
    {{- end }}
  volumeMounts:
    - name: tenx-git
      mountPath: /data
{{- end -}}

{{/*
Generate environment variables for cluster roles
Takes a dict with keys: cluster (cluster object), values (root values object)
Generates env vars based on roles array and global queue URLs
*/}}
{{- define "log10x-retriever.roleEnvVars" -}}
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
{{- if $hasStream }}
- name: TENX_REMOTE_FORWARD_HOST
  value: "127.0.0.1"
- name: TENX_REMOTE_FORWARD_PORT
  value: "24224"
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

{{/*
Ingress ApiVersion according to Kubernetes version
*/}}
{{- define "log10x-retriever.ingress.apiVersion" -}}
{{- if and (.Capabilities.APIVersions.Has "networking.k8s.io/v1") (semverCompare ">=1.19-0" .Capabilities.KubeVersion.GitVersion) -}}
networking.k8s.io/v1
{{- else if and (.Capabilities.APIVersions.Has "networking.k8s.io/v1beta1") (semverCompare ">=1.14-0" .Capabilities.KubeVersion.GitVersion) -}}
networking.k8s.io/v1beta1
{{- else -}}
extensions/v1beta1
{{- end }}
{{- end }}

{{/*
Return if ingress is stable (networking.k8s.io/v1)
*/}}
{{- define "log10x-retriever.ingress.isStable" -}}
{{- eq (include "log10x-retriever.ingress.apiVersion" .) "networking.k8s.io/v1" -}}
{{- end -}}

{{/*
Return if ingress supports ingressClassName
*/}}
{{- define "log10x-retriever.ingress.supportsIngressClassName" -}}
{{- or (eq (include "log10x-retriever.ingress.isStable" .) "true") (and (eq (include "log10x-retriever.ingress.apiVersion" .) "networking.k8s.io/v1beta1") (semverCompare ">= 1.18-0" .Capabilities.KubeVersion.Version)) -}}
{{- end -}}

{{/*
Return if ingress supports pathType
*/}}
{{- define "log10x-retriever.ingress.supportsPathType" -}}
{{- or (eq (include "log10x-retriever.ingress.isStable" .) "true") (and (eq (include "log10x-retriever.ingress.apiVersion" .) "networking.k8s.io/v1beta1") (semverCompare ">= 1.18-0" .Capabilities.KubeVersion.Version)) -}}
{{- end -}}

{{/*
Generate TLS secret name for cluster ingress
Expects dict with keys: cluster, root
*/}}
{{- define "log10x-retriever.cluster.ingress.tlsSecretName" -}}
{{- $cluster := .cluster -}}
{{- $root := .root -}}
{{- $ingressConfig := $cluster.ingress | default dict -}}
{{- $tlsConfig := $ingressConfig.tls | default dict -}}
{{- $tlsSource := $tlsConfig.source | default $root.Values.defaultIngress.tls.source -}}
{{- if eq $tlsSource "secret" -}}
{{ $tlsConfig.secretName | default $root.Values.defaultIngress.tls.secretName }}
{{- else if eq $tlsSource "cert-manager" -}}
{{ include "log10x-retriever.fullname" $root }}-{{ $cluster.name }}-tls-cert
{{- else if eq $tlsSource "alb" -}}
""
{{- end -}}
{{- end -}}

{{/*
Check if cluster has 'index' role
Expects dict with keys: cluster
*/}}
{{- define "log10x-retriever.cluster.hasIndexRole" -}}
{{- $cluster := .cluster -}}
{{- has "index" $cluster.roles -}}
{{- end -}}

{{/*
Check if cluster has 'query' role
Expects dict with keys: cluster
*/}}
{{- define "log10x-retriever.cluster.hasQueryRole" -}}
{{- $cluster := .cluster -}}
{{- has "query" $cluster.roles -}}
{{- end -}}

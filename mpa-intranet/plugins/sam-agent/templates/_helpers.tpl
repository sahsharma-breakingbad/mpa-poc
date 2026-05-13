{{/*
Expand the name of the chart.
*/}}
{{- define "sam.name" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "sam.fullname" -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "sam.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "sam.labels" -}}
helm.sh/chart: {{ include "sam.chart" . }}
{{ include "sam.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "sam.selectorLabels" -}}
app.kubernetes.io/name: {{ include "sam.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- if .Values.componentType }}
app.kubernetes.io/component: {{ .Values.componentType }}
{{- end }}
{{- end }}

{{- define "sam.podAnnotations" -}}
{{- if .Values.podAnnotations }}
{{- .Values.podAnnotations | toYaml }}
{{- end }}
{{- end }}

{{- define "sam.podLabels" -}}
{{- if .Values.podLabels }}
{{- .Values.podLabels | toYaml }}
{{- end }}
{{- end }}

{{- define "sam.annotations" -}}
{{- if .Values.annotations }}
annotations:
  {{- .Values.annotations | toYaml | nindent 2 }}
{{- end }}
{{- end }}

{{- define "sam.ddtags" -}}
{{- $tags := list }}
{{- if .Values.datadog.tags }}
{{- range $key, $value := .Values.datadog.tags }}
  {{- $tags = printf "%s:%s" $key $value | append $tags }}
{{- end }}
{{- end }}
{{- join " " $tags }}
{{- end }}

{{/*
PostgreSQL secret discovery and access helpers
*/}}

{{/*
Get PostgreSQL secret name using service discovery or explicit configuration
*/}}
{{- define "sam.postgresql.secretName" -}}
{{- if eq .Values.deploymentMode "standalone" }}
  {{- if .Values.persistence.existingSecrets.database }}
    {{- .Values.persistence.existingSecrets.database }}
  {{- else }}
    {{- include "sam.fullname" . }}-persistence
  {{- end }}
{{- else }}
  {{- /* deployer mode: auto-discover secret */ -}}
  {{- $allSecrets := (lookup "v1" "Secret" .Release.Namespace "") }}
  {{- if not $allSecrets.items }}{{- fail "Unable to lookup secrets. Make sure you have proper cluster access." }}{{- end }}
  {{- $found := "" }}
  {{- range $allSecrets.items }}
    {{- if and .metadata.labels (eq (index .metadata.labels "app.kubernetes.io/service" | default "") "database") }}
      {{- $found = .metadata.name }}{{- break }}
    {{- end }}
  {{- end }}
  {{- if not $found }}{{- fail (printf "Database secret not found for namespace '%s'. Make sure the chart with persistence is deployed first." .Release.Namespace ) }}{{- end }}
  {{- $found }}
{{- end }}
{{- end }}

{{/*
Generate DATABASE_URL from helpers and discovered PostgreSQL secret
*/}}
{{- define "sam.postgresql.databaseUrl" -}}
{{- if eq .Values.deploymentMode "standalone" }}
  {{- if .Values.persistence.existingSecrets.database }}
    {{- /* Use existing secret - must contain DATABASE_URL */ -}}
    {{- $pgSecret := (lookup "v1" "Secret" .Release.Namespace .Values.persistence.existingSecrets.database) }}
    {{- if not $pgSecret }}{{- fail (printf "PostgreSQL secret '%s' not found" .Values.persistence.existingSecrets.database) }}{{- end }}
    {{- index $pgSecret.data "DATABASE_URL" | b64dec }}
  {{- else if .Values.persistence.database.url }}
    {{- .Values.persistence.database.url }}
  {{- else }}
    {{- printf "postgresql+psycopg2://%s:%s@%s:%s/%s" .Values.persistence.database.username .Values.persistence.database.password .Values.persistence.database.host .Values.persistence.database.port .Values.persistence.database.database }}
  {{- end }}
{{- else }}
  {{- /* deployer mode: auto-discover and build URL */ -}}
  {{- $secretName := include "sam.postgresql.secretName" . }}
  {{- $pgSecret := (lookup "v1" "Secret" .Release.Namespace $secretName) }}
  {{- if not $pgSecret }}{{- fail (printf "PostgreSQL secret '%s' not found" $secretName) }}{{- end }}
  {{- $pgHost := index $pgSecret.data "PGHOST" | b64dec }}
  {{- $pgPort := index $pgSecret.data "PGPORT" | b64dec }}
  {{- $baseUsername := include "sam.database.agentUser" . }}
  {{- $qualifiedUsername := include "sam.database.qualifyUsername" (dict "username" $baseUsername "context" .) }}
  {{- printf "postgresql+psycopg2://%s:%s@%s:%s/%s" $qualifiedUsername (include "sam.database.agentPassword" .) $pgHost $pgPort (include "sam.database.agentName" .) }}
{{- end }}
{{- end }}

{{/*
SeaweedFS secret discovery and access helpers
*/}}

{{/*
Get S3 secret name using service discovery or explicit configuration
*/}}
{{- define "sam.s3.secretName" -}}
{{- if eq .Values.deploymentMode "standalone" }}
  {{- if .Values.persistence.existingSecrets.s3 }}
    {{- .Values.persistence.existingSecrets.s3 }}
  {{- else }}
    {{- include "sam.fullname" . }}-persistence
  {{- end }}
{{- else }}
  {{- /* deployer mode: auto-discover secret */ -}}
  {{- $allSecrets := (lookup "v1" "Secret" .Release.Namespace "") }}
  {{- if not $allSecrets.items }}{{- fail "Unable to lookup secrets. Make sure you have proper cluster access." }}{{- end }}
  {{- $found := "" }}
  {{- range $allSecrets.items }}
    {{- if and .metadata.labels (eq (index .metadata.labels "app.kubernetes.io/service" | default "") "s3") }}
      {{- $found = .metadata.name }}{{- break }}
    {{- end }}
  {{- end }}
  {{- if not $found }}{{- fail (printf "S3 secret not found for namespace '%s'. Make sure the chart with persistence is deployed first." .Release.Namespace ) }}{{- end }}
  {{- $found }}
{{- end }}
{{- end }}

{{/*
Get S3 URL from discovered secret or configuration
*/}}
{{- define "sam.s3.url" -}}
{{- if eq .Values.deploymentMode "standalone" }}
  {{- if .Values.persistence.existingSecrets.s3 }}
    {{- $secret := (lookup "v1" "Secret" .Release.Namespace .Values.persistence.existingSecrets.s3) }}
    {{- if not $secret }}{{- fail (printf "S3 secret '%s' not found" .Values.persistence.existingSecrets.s3) }}{{- end }}
    {{- index $secret.data "S3_ENDPOINT_URL" | b64dec }}
  {{- else }}
    {{- .Values.persistence.s3.endpointUrl }}
  {{- end }}
{{- else }}
  {{- $secretName := include "sam.s3.secretName" . }}
  {{- $secret := (lookup "v1" "Secret" .Release.Namespace $secretName) }}
  {{- if not $secret }}{{- fail (printf "S3 secret '%s' not found" $secretName) }}{{- end }}
  {{- $url := index $secret.data "S3_ENDPOINT_URL" | b64dec }}
  {{- if not $url }}{{- fail "S3_ENDPOINT_URL not found in S3 secret" }}{{- end }}
  {{- $url }}
{{- end }}
{{- end }}

{{/*
S3 configuration helpers - generates consistent S3 settings based on namespaceId
*/}}

{{/*
Get S3 bucket name
*/}}
{{- define "sam.s3.bucketName" -}}
{{- if eq .Values.deploymentMode "standalone" }}
  {{- if .Values.persistence.existingSecrets.s3 }}
    {{- $secret := (lookup "v1" "Secret" .Release.Namespace .Values.persistence.existingSecrets.s3) }}
    {{- if not $secret }}{{- fail (printf "S3 secret '%s' not found" .Values.persistence.existingSecrets.s3) }}{{- end }}
    {{- index $secret.data "S3_BUCKET_NAME" | b64dec }}
  {{- else }}
    {{- .Values.persistence.s3.bucketName }}
  {{- end }}
{{- else }}
  {{- $secretName := include "sam.s3.secretName" . }}
  {{- $secret := (lookup "v1" "Secret" .Release.Namespace $secretName) }}
  {{- if not $secret }}{{- fail (printf "S3 secret '%s' not found" $secretName) }}{{- end }}
  {{- $bucket := index $secret.data "S3_BUCKET" }}
  {{- if not $bucket }}
    {{- .Values.global.persistence.namespaceId }}
  {{- else }}
    {{- $bucket | b64dec }}
  {{- end }}
{{- end }}
{{- end }}

{{/*
Get S3 access key
*/}}
{{- define "sam.s3.accessKey" -}}
{{- if eq .Values.deploymentMode "standalone" }}
  {{- if .Values.persistence.existingSecrets.s3 }}
    {{- $secret := (lookup "v1" "Secret" .Release.Namespace .Values.persistence.existingSecrets.s3) }}
    {{- if not $secret }}{{- fail (printf "S3 secret '%s' not found" .Values.persistence.existingSecrets.s3) }}{{- end }}
    {{- index $secret.data "AWS_ACCESS_KEY_ID" | b64dec }}
  {{- else }}
    {{- .Values.persistence.s3.accessKey }}
  {{- end }}
{{- else }}
  {{- $secretName := include "sam.s3.secretName" . }}
  {{- $secret := (lookup "v1" "Secret" .Release.Namespace $secretName) }}
  {{- if not $secret }}{{- fail (printf "S3 secret '%s' not found" $secretName) }}{{- end }}
  {{- $accessKey := index $secret.data "S3_ACCESS_KEY" }}
  {{- if not $accessKey }}
    {{- .Values.global.persistence.namespaceId }}
  {{- else }}
    {{- $accessKey | b64dec }}
  {{- end }}
{{- end }}
{{- end }}

{{/*
Get S3 secret key
*/}}
{{- define "sam.s3.secretKey" -}}
{{- if eq .Values.deploymentMode "standalone" }}
  {{- if .Values.persistence.existingSecrets.s3 }}
    {{- $secret := (lookup "v1" "Secret" .Release.Namespace .Values.persistence.existingSecrets.s3) }}
    {{- if not $secret }}{{- fail (printf "S3 secret '%s' not found" .Values.persistence.existingSecrets.s3) }}{{- end }}
    {{- index $secret.data "AWS_SECRET_ACCESS_KEY" | b64dec }}
  {{- else }}
    {{- .Values.persistence.s3.secretKey }}
  {{- end }}
{{- else }}
  {{- $secretName := include "sam.s3.secretName" . }}
  {{- $secret := (lookup "v1" "Secret" .Release.Namespace $secretName) }}
  {{- if not $secret }}{{- fail (printf "S3 secret '%s' not found" $secretName) }}{{- end }}
  {{- $secretKey := index $secret.data "S3_SECRET_KEY" }}
  {{- if not $secretKey }}
    {{- .Values.global.persistence.namespaceId }}
  {{- else }}
    {{- $secretKey | b64dec }}
  {{- end }}
{{- end }}
{{- end }}
{{/*
Database configuration helpers - generates agent database settings based on namespaceId
*/}}

{{/*
Qualify username with Supabase tenant ID if configured (for Supabase connection pooler)
Reads SUPABASE_TENANT_ID from the discovered PostgreSQL secret
*/}}
{{- define "sam.database.qualifyUsername" -}}
{{- $secretName := include "sam.postgresql.secretName" .context }}
{{- $pgSecret := (lookup "v1" "Secret" .context.Release.Namespace $secretName) }}
{{- $supabaseTenantId := "" }}
{{- if $pgSecret }}
{{- $supabaseTenantId = index $pgSecret.data "SUPABASE_TENANT_ID" | default "" | b64dec }}
{{- end }}
{{- if $supabaseTenantId }}
{{- printf "%s.%s" .username $supabaseTenantId }}
{{- else }}
{{- .username }}
{{- end }}
{{- end }}

{{/*
Get component ID with backward compatibility
Uses 'id' if set, falls back to 'agentId' for backward compatibility
*/}}
{{- define "sam.componentId" -}}
{{- if .Values.id }}
{{- .Values.id }}
{{- else if .Values.agentId }}
{{- .Values.agentId }}
{{- end }}
{{- end }}

{{/*
Get component configuration YAML with backward compatibility
Uses 'config.yaml' if set, falls back to 'config.agentYaml' for backward compatibility
*/}}
{{- define "sam.configYaml" -}}
{{- if .Values.config.yaml }}
{{- .Values.config.yaml }}
{{- else if .Values.config.agentYaml }}
{{- .Values.config.agentYaml }}
{{- end }}
{{- end }}

{{/*
Get component database name (namespaceId_id_component)
*/}}
{{- define "sam.database.agentName" -}}
{{- printf "%s_%s_%s" .Values.global.persistence.namespaceId (include "sam.componentId" .) .Values.component }}
{{- end }}

{{/*
Get component database user (namespaceId_id_component)
*/}}
{{- define "sam.database.agentUser" -}}
{{- printf "%s_%s_%s" .Values.global.persistence.namespaceId (include "sam.componentId" .) .Values.component }}
{{- end }}

{{/*
Get component database password
- External mode: uses applicationPassword discovered from parent chart's secret
- Embedded mode: uses legacy pattern (namespaceId_id_component)
*/}}
{{- define "sam.database.agentPassword" -}}
{{- $secretName := include "sam.postgresql.secretName" . }}
{{- $pgSecret := (lookup "v1" "Secret" .Release.Namespace $secretName) }}
{{- if $pgSecret }}
{{- $applicationPassword := index $pgSecret.data "APPLICATION_PASSWORD" | default "" | b64dec }}
{{- if $applicationPassword }}
{{- $applicationPassword }}
{{- else }}
{{- printf "%s_%s_%s" .Values.global.persistence.namespaceId (include "sam.componentId" .) .Values.component }}
{{- end }}
{{- else }}
{{- printf "%s_%s_%s" .Values.global.persistence.namespaceId (include "sam.componentId" .) .Values.component }}
{{- end }}
{{- end }}

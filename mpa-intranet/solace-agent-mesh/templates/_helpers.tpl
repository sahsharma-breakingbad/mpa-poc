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
Validate that applicationPassword is provided when using external persistence
*/}}
{{- define "sam.validateApplicationPassword" -}}
{{- if and (not .Values.global.persistence.enabled) (not .Values.dataStores.database.applicationPassword) }}
{{- fail "dataStores.database.applicationPassword is required when using external persistence (global.persistence.enabled=false)" }}
{{- end }}
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
{{- end }}

{{/*
Inject extra environment populated by secrets, if populated
*/}}
{{- define "sam.extraSecretEnvironmentVars" -}}
{{- if .extraSecretEnvironmentVars -}}
{{- range .extraSecretEnvironmentVars }}
- name: {{ .envName }}
  valueFrom:
   secretKeyRef:
     name: {{ .secretName }}
     key: {{ .secretKey }}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "sam.serviceSelectorLabels" -}}
app.kubernetes.io/name: {{ include "sam.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: core
{{- end }}

{{- define "sam.podAnnotations" -}}
{{- if .Values.samDeployment.podAnnotations }}
{{- .Values.samDeployment.podAnnotations | toYaml }}
{{- end }}
{{- end }}

{{- define "sam.podLabels" -}}
{{- if .Values.samDeployment.podLabels }}
{{- .Values.samDeployment.podLabels | toYaml }}
{{- end }}
{{- end }}

{{- define "sam.annotations" -}}
{{- if .Values.samDeployment.annotations }}
annotations:
  {{- .Values.samDeployment.annotations | toYaml | nindent 2 }}
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

{{- define "sam.hostname" -}}
{{- if .Values.sam.dnsName }}
{{- printf "%s:%d" .Values.sam.dnsName }}
{{- else }}
{{- fail "No valid SAM endpoint defined. Please set sam.dnsName in values.yaml." }}
{{- end }}
{{- end }}

{{- define "sam.webUiPort" -}}
{{- if .Values.sam.webUiPort }}
{{- printf "%s:%d" .Values.sam.webUiPort }}
{{- else }}
{{- fail "No valid SAM webUiPort port defined. Please set sam.webUiPort in values.yaml." }}
{{- end }}
{{- end }}

{{/*
S3 configuration helpers - generates consistent S3 settings based on namespaceId
*/}}

{{/*
Get S3 bucket name (same as namespaceId)
*/}}
{{- define "sam.s3.bucketName" -}}
{{- if .Values.global.persistence.enabled }}
{{- printf "%s" .Values.global.persistence.namespaceId }}
{{- else -}}
{{- printf "%s" .Values.dataStores.s3.bucketName }}
{{- end }}
{{- end }}

{{/*
Get S3 access key (same as namespaceId)
*/}}
{{- define "sam.s3.accessKey" -}}
{{- if .Values.global.persistence.enabled }}
{{- printf "%s" .Values.global.persistence.namespaceId }}
{{- else -}}
{{- printf "%s" .Values.dataStores.s3.accessKey }}
{{- end }}
{{- end }}

{{/*
Get S3 secret key (same as namespaceId)
*/}}
{{- define "sam.s3.secretKey" -}}
{{- if .Values.global.persistence.enabled }}
{{- printf "%s" .Values.global.persistence.namespaceId }}
{{- else -}}
{{- printf "%s" .Values.dataStores.s3.secretKey }}
{{- end }}
{{- end }}


{{- define "sam.s3.endpointUrl" -}}
{{- if .Values.global.persistence.enabled }}
{{- include "seaweedfs.s3url" (index .Subcharts "persistence-layer") }}
{{- else -}}
{{- printf "%s" .Values.dataStores.s3.endpointUrl }}
{{- end }}
{{- end }}

{{/*
Get S3 connector specs bucket name
*/}}
{{- define "sam.s3.connectorSpecBucketName" -}}
{{- if .Values.global.persistence.enabled }}
{{- printf "%s-connector-specs" .Values.global.persistence.namespaceId }}
{{- else -}}
{{- printf "%s" .Values.dataStores.s3.connectorSpecBucketName }}
{{- end }}
{{- end }}

{{/*
Get effective object storage type
Bundled persistence always uses S3 (SeaweedFS). Otherwise read from values.
*/}}
{{- define "sam.objectStorage.type" -}}
{{- if .Values.global.persistence.enabled -}}s3{{- else -}}{{ .Values.dataStores.objectStorage.type | default "s3" }}{{- end -}}
{{- end -}}

{{/*
Get Azure container name
*/}}
{{- define "sam.azure.containerName" -}}
{{- .Values.dataStores.azure.containerName }}
{{- end -}}

{{/*
Get Azure connector spec container name
*/}}
{{- define "sam.azure.connectorSpecContainerName" -}}
{{- .Values.dataStores.azure.connectorSpecContainerName }}
{{- end -}}

{{/*
Get GCS bucket name
*/}}
{{- define "sam.gcs.bucketName" -}}
{{- .Values.dataStores.gcs.bucketName }}
{{- end -}}

{{/*
Get GCS connector spec bucket name
*/}}
{{- define "sam.gcs.connectorSpecBucketName" -}}
{{- .Values.dataStores.gcs.connectorSpecBucketName }}
{{- end -}}

{{/*
Database configuration helpers - generates consistent database settings based on namespaceId
*/}}

{{/*
Qualify username with Supabase tenant ID if configured (for Supabase connection pooler)
Usage: include "sam.database.qualifyUsername" (dict "username" "myuser" "context" $)
*/}}
{{- define "sam.database.qualifyUsername" -}}
{{- if and .context.Values.dataStores.database.supabaseTenantId (not .context.Values.global.persistence.enabled) }}
{{- printf "%s.%s" .username .context.Values.dataStores.database.supabaseTenantId }}
{{- else }}
{{- .username }}
{{- end }}
{{- end }}

{{/*
Get WebUI database name (namespaceId_webui)
*/}}
{{- define "sam.database.webuiName" -}}
{{- printf "%s_webui" .Values.global.persistence.namespaceId }}
{{- end }}

{{/*
Get WebUI database user (namespaceId_webui)
*/}}
{{- define "sam.database.webuiUser" -}}
{{- printf "%s_webui" .Values.global.persistence.namespaceId }}
{{- end }}

{{/*
Get WebUI database password
- External mode: uses applicationPassword from values
- Embedded mode: uses legacy pattern (namespaceId_webui)
*/}}
{{- define "sam.database.webuiPassword" -}}
{{- if .Values.global.persistence.enabled }}
{{- printf "%s_webui" .Values.global.persistence.namespaceId }}
{{- else }}
{{- required "dataStores.database.applicationPassword is required for external persistence" .Values.dataStores.database.applicationPassword }}
{{- end }}
{{- end }}

{{/*
Get Orchestrator database name (namespaceId_orchestrator)
*/}}
{{- define "sam.database.orchestratorName" -}}
{{- printf "%s_orchestrator" .Values.global.persistence.namespaceId }}
{{- end }}

{{/*
Get Orchestrator database user (namespaceId_orchestrator)
*/}}
{{- define "sam.database.orchestratorUser" -}}
{{- printf "%s_orchestrator" .Values.global.persistence.namespaceId }}
{{- end }}

{{/*
Get Orchestrator database password
- External mode: uses applicationPassword from values
- Embedded mode: uses legacy pattern (namespaceId_orchestrator)
*/}}
{{- define "sam.database.orchestratorPassword" -}}
{{- if .Values.global.persistence.enabled }}
{{- printf "%s_orchestrator" .Values.global.persistence.namespaceId }}
{{- else }}
{{- required "dataStores.database.applicationPassword is required for external persistence" .Values.dataStores.database.applicationPassword }}
{{- end }}
{{- end }}

{{/*
Get Platform database name (namespaceId_platform)
*/}}
{{- define "sam.database.platformName" -}}
{{- printf "%s_platform" .Values.global.persistence.namespaceId }}
{{- end }}

{{/*
Get Platform database user (namespaceId_platform)
*/}}
{{- define "sam.database.platformUser" -}}
{{- printf "%s_platform" .Values.global.persistence.namespaceId }}
{{- end }}

{{/*
Get Platform database password
- External mode: uses applicationPassword from values
- Embedded mode: uses legacy pattern (namespaceId_platform)
*/}}
{{- define "sam.database.platformPassword" -}}
{{- if .Values.global.persistence.enabled }}
{{- printf "%s_platform" .Values.global.persistence.namespaceId }}
{{- else }}
{{- required "dataStores.database.applicationPassword is required for external persistence" .Values.dataStores.database.applicationPassword }}
{{- end }}
{{- end }}

{{/*
Health check script for liveness and readiness probes.
Checks both WebUI and Platform service ports are listening.
*/}}
{{- define "sam.healthCheckScript" -}}
import socket
try:
    {{- if .Values.service.tls.enabled }}
    sock_webui = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock_webui.settimeout(5)
    result_webui = sock_webui.connect_ex(('localhost', 8443))
    sock_webui.close()

    sock_platform = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock_platform.settimeout(5)
    result_platform = sock_platform.connect_ex(('localhost', 4443))
    sock_platform.close()

    if result_webui == 0 and result_platform == 0:
        exit(0)
    else:
        print(f"Port 8443: {result_webui}, Port 4443: {result_platform}")
        exit(1)
    {{- else }}
    sock_webui = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock_webui.settimeout(5)
    result_webui = sock_webui.connect_ex(('localhost', 8000))
    sock_webui.close()

    sock_platform = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock_platform.settimeout(5)
    result_platform = sock_platform.connect_ex(('localhost', 8001))
    sock_platform.close()

    if result_webui == 0 and result_platform == 0:
        exit(0)
    else:
        print(f"Port 8000: {result_webui}, Port 8001: {result_platform}")
        exit(1)
    {{- end }}
except Exception as e:
    print(f"Health check failed: {e}")
    exit(1)
{{- end }}

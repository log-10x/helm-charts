# Log10x Streamer Helm Chart

Official Helm chart for deploying SQS-based Log10x pipeline streaming clusters on Kubernetes.

## Overview

This chart deploys one or more **cluster deployments** with specific roles for processing tasks. Each cluster can handle one or more roles:
- **Index**: Process indexing requests from SQS
- **Query**: Process query requests and generate sub-queries
- **Stream**: Execute stream tasks from SQS and forward results to configured destinations

Stream workers automatically include a **fluent-bit sidecar** for log forwarding to destinations like S3, CloudWatch, Elasticsearch, Splunk, or Datadog.

## Prerequisites

- Kubernetes 1.19+
- Helm 3.0+
- AWS SQS queues (recommended: use [terraform-aws-tenx-streamer-infra](https://registry.terraform.io/modules/log-10x/tenx-streamer-infra/aws))
- Log10x API key
- AWS credentials configured (via IRSA or service account annotations)

## Quick Start

### Basic Installation (Single All-in-One Cluster)

```bash
helm install my-streamer log10x/streamer-10x \
  --set log10xApiKey="your-api-key" \
  --set indexQueueUrl="https://sqs.us-west-2.amazonaws.com/.../index-queue" \
  --set queryQueueUrl="https://sqs.us-west-2.amazonaws.com/.../query-queue" \
  --set subQueryQueueUrl="https://sqs.us-west-2.amazonaws.com/.../subquery-queue" \
  --set streamQueueUrl="https://sqs.us-west-2.amazonaws.com/.../stream-queue"
```

### Production Installation (Multiple Clusters)

Create a `values.yaml`:

```yaml
log10xApiKey: "your-api-key"

# Global queue URLs
indexQueueUrl: "https://sqs.us-west-2.amazonaws.com/.../index-queue"
queryQueueUrl: "https://sqs.us-west-2.amazonaws.com/.../query-queue"
subQueryQueueUrl: "https://sqs.us-west-2.amazonaws.com/.../subquery-queue"
streamQueueUrl: "https://sqs.us-west-2.amazonaws.com/.../stream-queue"

# S3 bucket configuration
inputBucket: "my-bucket"
indexBucket: "my-bucket/indexed/"

# Service account for AWS IRSA
serviceAccount:
  create: true
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT:role/tenx-streamer-role

clusters:
  # Dedicated indexing cluster
  - name: indexer
    roles: ["index"]
    replicaCount: 2
    maxParallelRequests: 5
    resources:
      requests:
        cpu: 2000m
        memory: 4Gi
    autoscaling:
      enabled: true
      minReplicas: 2
      maxReplicas: 10

  # Query processing cluster
  - name: query-handler
    roles: ["query"]
    replicaCount: 5
    maxParallelRequests: 20
    resources:
      requests:
        cpu: 1000m
        memory: 2Gi

  # Stream execution cluster with fluent-bit sidecar
  - name: stream-worker
    roles: ["stream"]
    replicaCount: 10
    maxParallelRequests: 15
    resources:
      requests:
        cpu: 1000m
        memory: 2Gi

# Fluent-bit configuration for stream workers
fluentBit:
  output:
    type: s3  # Options: stdout, s3, cloudwatch, elasticsearch, splunk, datadog
    config:
      s3:
        bucket: my-logs-bucket
        region: us-west-2
```

Install:

```bash
helm install my-streamer log10x/streamer-10x -f values.yaml
```

## Key Configuration

### Global Settings

| Parameter | Description | Required |
|-----------|-------------|----------|
| `log10xApiKey` | Log10x API key | Yes |
| `indexQueueUrl` | SQS queue URL for index operations | For index role |
| `queryQueueUrl` | SQS queue URL for query operations | For query role |
| `subQueryQueueUrl` | SQS queue URL for sub-query operations | For query role |
| `streamQueueUrl` | SQS queue URL for stream operations | For stream role |
| `inputBucket` | S3 bucket for input data | Recommended |
| `indexBucket` | S3 bucket path for indexed results | Recommended |

### Cluster Settings

| Parameter | Description | Default |
|-----------|-------------|---------|
| `clusters[].name` | Cluster name | Required |
| `clusters[].roles` | Array: `["index"]`, `["query"]`, `["stream"]`, or combinations | Required |
| `clusters[].replicaCount` | Number of pod replicas | `1` |
| `clusters[].maxParallelRequests` | Max concurrent tasks per pod | `10` |
| `clusters[].extraEnv` | Additional environment variables for this cluster | `[]` |
| `clusters[].extraVolumes` | Additional volumes to mount (PVC, ConfigMap, Secret, etc.) | `[]` |
| `clusters[].extraVolumeMounts` | Mount paths for extraVolumes | `[]` |
| `clusters[].resources` | CPU/Memory requests and limits | `{}` |
| `clusters[].autoscaling.enabled` | Enable HPA | `false` |

### Fluent-bit Configuration (Stream Workers Only)

Stream workers automatically deploy a fluent-bit sidecar for log forwarding.

| Parameter | Description | Default |
|-----------|-------------|---------|
| `fluentBit.output.type` | Output destination: `stdout`, `s3`, `cloudwatch`, `elasticsearch`, `splunk`, `datadog` | `stdout` |
| `fluentBit.output.config.s3.bucket` | S3 bucket name (for S3 output) | `""` |
| `fluentBit.output.config.cloudwatch.logGroupName` | CloudWatch log group (for CloudWatch output) | `""` |
| `fluentBit.output.config.elasticsearch.host` | Elasticsearch host (for ES output) | `""` |
| `fluentBit.output.config.splunk.host` | Splunk HEC endpoint (for Splunk output) | `""` |
| `fluentBit.output.config.datadog.apiKey` | Datadog API key (for Datadog output) | `""` |
| `fluentBit.bufferStorageSize` | Max buffer disk space | `1Gi` |

**Authentication:**
- **S3/CloudWatch**: Uses IRSA (configure via `serviceAccount.annotations`)
- **Elasticsearch/Splunk/Datadog**: Uses Kubernetes secrets (provide credentials via `--set-string`)

Example with CloudWatch:

```yaml
fluentBit:
  output:
    type: cloudwatch
    config:
      cloudwatch:
        region: us-west-2
        logGroupName: /aws/eks/my-streamer-logs
        logStreamPrefix: stream-
```

### Scheduled Queries

The chart supports running scheduled queries as Kubernetes CronJobs. Each CronJob sends predefined query messages to the query SQS queue on a specified schedule.

**Use cases:**
- Recurring error reports (hourly, daily)
- Scheduled monitoring checks
- Automated data exports
- Periodic audit queries

**Configuration:**

```yaml
# Enable scheduled queries (default: true)
scheduledQueries:
  enabled: true  # Set to false to disable all scheduled queries
  jobs:
    - name: hourly-errors
      schedule: "0 * * * *"  # Every hour at minute 0 (UTC)
      queries:
        - name: "error-logs"
          from: 'now("-1h")'
          to: 'now()'
          search: 'severity_level=="ERROR"'
          # Optional fields (10x config provides defaults):
          # processingTime: 'parseDuration("5m")'
          # resultSize: 'parseBytes("100MB")'

    - name: daily-summary
      schedule: "0 0 * * *"  # Daily at midnight UTC
      suspend: false  # Can be set to true to temporarily disable this specific job
      queries:
        - name: "daily-errors"
          from: 'now("-24h")'
          to: 'now()'
          search: 'severity_level=="ERROR"'
        - name: "daily-warnings"
          from: 'now("-24h")'
          to: 'now()'
          search: 'severity_level=="WARN"'
```

**Disabling scheduled queries:**

```yaml
# Option 1: Disable all scheduled queries with enabled flag
scheduledQueries:
  enabled: false

# Option 2: Enable but provide no jobs
scheduledQueries:
  enabled: true
  jobs: []
```

**Expression Syntax:**

Queries use Log10x YAML-style configuration expressions that are parsed by the query server:

- **Time**: `now()` - current time, `now("-1h")` - 1 hour ago, `now("-24h")` - 24 hours ago, `now("-7d")` - 7 days ago
- **Duration**: `parseDuration("5m")` - 5 minutes, supports: `ms`, `s`, `m`, `h`
- **Bytes**: `parseBytes("100MB")` - size in bytes, supports: `B`, `KB`, `MB`, `GB`

**Default Values:**

The Log10x query server automatically applies defaults from your pipeline configuration for any fields not explicitly specified in the query. This means you only need to specify `from`, `to`, and optionally `search` or other query-specific fields.

**Important Notes:**
- **Timezone**: All cron schedules run in UTC
- **Multiple queries per job**: Each job can define multiple queries that are sent sequentially
- **IAM permissions**: CronJobs use the same service account as streamer pods. The IRSA role that grants `sqs:ReceiveMessage` for query workers automatically provides `sqs:SendMessage` permission needed by CronJobs
- **Required fields per query**: Only `from` and `to` are required - the query server applies configured defaults for all other fields

**Monitoring scheduled queries:**

```bash
# List all CronJobs
kubectl get cronjobs -l component=scheduled-query

# View recent job executions
kubectl get jobs -l component=scheduled-query

# Check logs for a specific job
kubectl logs job/<job-name>

# Manually trigger a scheduled query (replace <job-name> with the name from scheduledQueries.jobs[].name)
kubectl create job --from=cronjob/<release>-streamer-10x-<job-name> manual-run
```

## AWS IAM Configuration

Configure IRSA for AWS service access:

```yaml
serviceAccount:
  create: true
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT:role/tenx-streamer-role
```

**Required IAM permissions:**
- SQS: `ReceiveMessage`, `DeleteMessage`, `SendMessage`, `GetQueueAttributes`
- S3 source bucket: `GetObject`
- S3 results bucket: `GetObject`, `PutObject`, `DeleteObject`, `ListBucket`
- CloudWatch Logs (if using): `CreateLogGroup`, `CreateLogStream`, `PutLogEvents`

For detailed IAM policy examples, see the [terraform-aws-tenx-streamer-infra](https://registry.terraform.io/modules/log-10x/tenx-streamer-infra/aws) module.

## Advanced Configuration

### Persistent Storage for Heap Dumps

For debugging memory issues, you can configure persistent storage for Java heap dumps that occur on OutOfMemoryError:

1. **Create a PersistentVolumeClaim:**

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: indexer-heap-dumps
  namespace: my-namespace
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
  storageClassName: gp3
```

2. **Configure the cluster to use the volume:**

```yaml
clusters:
  - name: indexer
    roles: ["index"]
    extraEnv:
      - name: JAVA_OPTS_APPEND
        value: "-XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/heap-dumps/heapdump.hprof -Dquarkus.http.host=0.0.0.0 -Djava.util.logging.manager=org.jboss.logmanager.LogManager -Djdk.httpclient.allowRestrictedHeaders=host -Dfile.encoding=UTF-8"
    extraVolumes:
      - name: heap-dumps
        persistentVolumeClaim:
          claimName: indexer-heap-dumps
    extraVolumeMounts:
      - name: heap-dumps
        mountPath: /heap-dumps
```

3. **Retrieve heap dumps after an OOM:**

```bash
# List heap dumps
kubectl exec -n my-namespace <indexer-pod-name> -- ls -lh /heap-dumps/

# Copy heap dump to local machine for analysis
kubectl cp my-namespace/<indexer-pod-name>:/heap-dumps/heapdump.hprof ./heapdump.hprof
```

**Note:** When overriding `JAVA_OPTS_APPEND`, you must include all required Quarkus options (shown in the example above) to ensure the application runs correctly.

### Custom Configuration with ConfigMaps

You can mount additional configuration files using extraVolumes:

```yaml
clusters:
  - name: indexer
    extraVolumes:
      - name: custom-config
        configMap:
          name: my-custom-config
    extraVolumeMounts:
      - name: custom-config
        mountPath: /etc/custom-config
        readOnly: true
```

## Monitoring

Check deployment status:

```bash
# View all deployments
kubectl get deployments -l app=streamer-10x

# View logs
kubectl logs -l cluster=stream-worker --tail=100 -f

# Check fluent-bit sidecar logs
kubectl logs -l cluster=stream-worker -c fluent-bit --tail=50

# Check pod health
kubectl get pods -l app=streamer-10x
```

## Documentation

For comprehensive installation guides, architecture details, and advanced configuration, visit the [Log10x documentation](https://doc.log10x.com).

## License

Copyright © 2025 Log10x

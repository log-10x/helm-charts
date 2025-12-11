# Log10x Streamer Helm Chart

Official Helm chart for deploying SQS-based Log10x pipeline streaming clusters on Kubernetes.

## Overview

This chart deploys one or more **cluster deployments** with specific roles for processing pipeline tasks. Each cluster can handle one or more roles:
- **Index**: Process indexing requests from SQS
- **Query**: Process query requests from SQS
- **Pipeline**: Execute pipeline tasks from SQS

Unlike REST-based deployments, these clusters are role-based and consume work from SQS queues, making them ideal for asynchronous, scalable processing.

## Prerequisites

- Kubernetes 1.19+
- Helm 3.0+
- AWS SQS queues created (recommended: use [terraform-aws-tenx-streamer-infra](https://registry.terraform.io/modules/log-10x/tenx-streamer-infra/aws))
- Log10x API key
- AWS credentials configured (via IAM roles or service account annotations)

## Installation

### Basic Installation (Single Cluster)

```bash
helm install my-streamer log-10x/streamer-10x \
  --set log10xApiKey="your-api-key" \
  --set clusters[0].index.queueUrl="https://sqs.us-west-2.amazonaws.com/123456789012/index-queue" \
  --set clusters[0].query.queueUrl="https://sqs.us-west-2.amazonaws.com/123456789012/query-queue" \
  --set clusters[0].pipeline.queueUrl="https://sqs.us-west-2.amazonaws.com/123456789012/pipeline-queue"
```

### Production Installation (Multiple Clusters)

Create a `values.yaml`:

```yaml
log10xApiKey: "your-api-key"

clusters:
  # Dedicated indexing cluster (resource-intensive)
  - name: indexer
    index:
      queueUrl: "https://sqs.us-west-2.amazonaws.com/.../index-queue"
      writeContainer: "my-bucket/indexed/"
    replicaCount: 2
    maxParallelRequests: 5
    resources:
      requests:
        cpu: 2000m
        memory: 4Gi
      limits:
        cpu: 4000m
        memory: 8Gi
    autoscaling:
      enabled: true
      minReplicas: 2
      maxReplicas: 10
      targetCPUUtilizationPercentage: 70

  # Query processing cluster
  - name: query-handler
    query:
      queueUrl: "https://sqs.us-west-2.amazonaws.com/.../query-queue"
      pipelineUrl: "https://sqs.us-west-2.amazonaws.com/.../pipeline-queue"
    replicaCount: 5
    maxParallelRequests: 20
    resources:
      requests:
        cpu: 1000m
        memory: 2Gi
    autoscaling:
      enabled: true
      minReplicas: 5
      maxReplicas: 20

  # Pipeline execution cluster
  - name: pipeline-worker
    pipeline:
      queueUrl: "https://sqs.us-west-2.amazonaws.com/.../pipeline-queue"
    replicaCount: 10
    maxParallelRequests: 15
    resources:
      requests:
        cpu: 1000m
        memory: 2Gi
    autoscaling:
      enabled: true
      minReplicas: 10
      maxReplicas: 50
```

Then install:

```bash
helm install my-streamer log-10x/streamer-10x -f values.yaml
```

## Configuration

### Cluster Configuration

Each cluster in the `clusters` array supports:

| Parameter | Description | Default |
|-----------|-------------|---------|
| `name` | Cluster name (used in deployment naming) | Required |
| `index.queueUrl` | SQS queue URL for index requests | `""` (disabled) |
| `index.writeContainer` | S3 path for indexing results | `""` (optional) |
| `query.queueUrl` | SQS queue URL for query requests | `""` (disabled) |
| `query.pipelineUrl` | SQS queue URL for invoking pipelines | Uses `pipeline.queueUrl` if available |
| `pipeline.queueUrl` | SQS queue URL for pipeline execution | `""` (disabled) |
| `replicaCount` | Number of pod replicas | `1` |
| `maxParallelRequests` | Max concurrent pipelines per pod | `10` |
| `maxQueuedRequests` | Max queued requests per pod | `1000` |
| `readinessThresholdPercent` | Load threshold for readiness | `90` |
| `extraEnv` | Additional environment variables | `[]` |
| `resources` | CPU/Memory requests and limits | `{}` |
| `autoscaling.enabled` | Enable HPA | `false` |
| `autoscaling.minReplicas` | Minimum replicas | `1` |
| `autoscaling.maxReplicas` | Maximum replicas | `5` |
| `nodeSelector` | Node selection constraints | `{}` |
| `tolerations` | Pod tolerations | `[]` |
| `affinity` | Pod affinity rules | `{}` |

### Global Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `log10xApiKey` | Log10x API key (required) | `""` |
| `image.repository` | Container image repository | `ghcr.io/log-10x/quarkus-10x` |
| `image.tag` | Container image tag | Chart appVersion |
| `serviceAccount.create` | Create service account | `true` |
| `serviceAccount.annotations` | Service account annotations (for IAM roles) | `{}` |
| `github.config.repo` | GitHub repo for config | `""` |
| `github.symbols.repo` | GitHub repo for symbols | `""` |

## Integrating with Terraform

This chart works seamlessly with the [terraform-aws-tenx-streamer-infra](https://registry.terraform.io/modules/log-10x/tenx-streamer-infra/aws) module:

```hcl
# Terraform
module "tenx_streamer_infra" {
  source  = "log-10x/tenx-streamer-infra/aws"
  version = "~> 0.1"

  tenx_streamer_index_queue_name = "my-index-queue"
  tenx_streamer_query_queue_name = "my-query-queue"
  tenx_streamer_pipeline_queue_name = "my-pipeline-queue"
}

output "helm_values" {
  value = {
    index_queue_url = module.tenx_streamer_infra.index_queue_url
    query_queue_url = module.tenx_streamer_infra.query_queue_url
    pipeline_queue_url = module.tenx_streamer_infra.pipeline_queue_url
    index_write_container = module.tenx_streamer_infra.index_write_container
  }
}
```

Then use the outputs:

```bash
helm install my-streamer log-10x/streamer-10x \
  --set log10xApiKey="your-api-key" \
  --set clusters[0].index.queueUrl="$(terraform output -raw helm_values | jq -r '.index_queue_url')" \
  --set clusters[0].query.queueUrl="$(terraform output -raw helm_values | jq -r '.query_queue_url')" \
  --set clusters[0].pipeline.queueUrl="$(terraform output -raw helm_values | jq -r '.pipeline_queue_url')" \
  --set clusters[0].index.writeContainer="$(terraform output -raw helm_values | jq -r '.index_write_container')"
```

## AWS IAM Configuration

The pods need IAM permissions to access SQS queues. Configure via service account annotations:

```yaml
serviceAccount:
  create: true
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT:role/tenx-streamer-role
```

Required IAM permissions:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage",
        "sqs:SendMessage",
        "sqs:GetQueueAttributes"
      ],
      "Resource": "arn:aws:sqs:*:*:*"
    }
  ]
}
```

## Health Checks

The chart uses Quarkus health endpoints:
- `/q/health/live` - Liveness probe
- `/q/health/ready` - Readiness probe
- `/q/health/started` - Startup probe

## Monitoring

Check cluster status:

```bash
# View all deployments
kubectl get deployments -l app=streamer-10x

# View specific cluster
kubectl get deployment my-streamer-indexer

# View logs
kubectl logs -l cluster=indexer --tail=100 -f

# Check pod health
kubectl get pods -l app=streamer-10x
```

## Troubleshooting

### Pods not processing messages

1. Check SQS queue URLs are correct
2. Verify IAM permissions for SQS access
3. Check pod logs: `kubectl logs <pod-name>`
4. Verify queue has messages: `aws sqs get-queue-attributes --queue-url <url> --attribute-names ApproximateNumberOfMessages`

### Pods failing health checks

1. Check startup logs: `kubectl logs <pod-name>`
2. Verify API key is correct
3. Check resource limits aren't too restrictive
4. Increase `startupProbe.failureThreshold` if startup is slow

## License

Copyright © 2025 Log10x

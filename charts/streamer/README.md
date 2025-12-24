# Log10x Streamer Helm Chart

Official Helm chart for deploying SQS-based Log10x pipeline streaming clusters on Kubernetes.

## Overview

This chart deploys one or more **cluster deployments** with specific roles for processing tasks. Each cluster can handle one or more roles:
- **Index**: Process indexing requests from SQS
- **Query**: Process query requests and generate sub-queries
- **Stream**: Execute stream tasks from SQS

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
  --set indexQueueUrl="https://sqs.us-west-2.amazonaws.com/123456789012/index-queue" \
  --set queryQueueUrl="https://sqs.us-west-2.amazonaws.com/123456789012/query-queue" \
  --set subQueryQueueUrl="https://sqs.us-west-2.amazonaws.com/123456789012/subquery-queue" \
  --set streamQueueUrl="https://sqs.us-west-2.amazonaws.com/123456789012/stream-queue"
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

clusters:
  # Dedicated indexing cluster (resource-intensive)
  - name: indexer
    roles: ["index"]
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
    roles: ["query"]
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

  # Stream execution cluster
  - name: stream-worker
    roles: ["stream"]
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

### Global Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `log10xApiKey` | Log10x API key (required) | `""` |
| `indexQueueUrl` | SQS queue URL for index operations | `""` |
| `queryQueueUrl` | SQS queue URL for query operations | `""` |
| `subQueryQueueUrl` | SQS queue URL for sub-query operations | `""` |
| `streamQueueUrl` | SQS queue URL for stream operations | `""` |
| `inputBucket` | S3 bucket for input data | `""` |
| `indexBucket` | S3 bucket path for indexed results | `""` |
| `image.repository` | Container image repository | `ghcr.io/log-10x/quarkus-10x` |
| `image.tag` | Container image tag | Chart appVersion |
| `serviceAccount.create` | Create service account | `true` |
| `serviceAccount.annotations` | Service account annotations (for IAM roles) | `{}` |
| `github.config.repo` | GitHub repo for config | `""` |
| `github.symbols.repo` | GitHub repo for symbols | `""` |

### Cluster Configuration

Each cluster in the `clusters` array supports:

| Parameter | Description | Default |
|-----------|-------------|---------|
| `name` | Cluster name (used in deployment naming) | Required |
| `roles` | Array of roles: `["index"]`, `["query"]`, `["stream"]`, or combinations | Required |
| `replicaCount` | Number of pod replicas | `1` |
| `maxParallelRequests` | Max concurrent tasks per pod | `10` |
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

## Integrating with Terraform

This chart works seamlessly with the [terraform-aws-tenx-streamer-infra](https://registry.terraform.io/modules/log-10x/tenx-streamer-infra/aws) module:

```hcl
# Terraform
module "tenx_streamer_infra" {
  source  = "log-10x/tenx-streamer-infra/aws"
  version = "~> 0.3"

  tenx_streamer_index_queue_name    = "my-index-queue"
  tenx_streamer_query_queue_name    = "my-query-queue"
  tenx_streamer_subquery_queue_name = "my-subquery-queue"
  tenx_streamer_stream_queue_name   = "my-stream-queue"

  tenx_streamer_index_source_bucket_name  = "my-source-bucket"
  tenx_streamer_index_results_bucket_name = "my-results-bucket"
}

output "helm_values" {
  value = {
    index_queue_url    = module.tenx_streamer_infra.index_queue_url
    query_queue_url    = module.tenx_streamer_infra.query_queue_url
    subquery_queue_url = module.tenx_streamer_infra.subquery_queue_url
    stream_queue_url   = module.tenx_streamer_infra.stream_queue_url
    input_bucket       = module.tenx_streamer_infra.index_source_bucket_name
    index_bucket       = module.tenx_streamer_infra.index_write_container
  }
}
```

Then use the outputs:

```bash
helm install my-streamer log-10x/streamer-10x \
  --set log10xApiKey="your-api-key" \
  --set indexQueueUrl="$(terraform output -raw helm_values | jq -r '.index_queue_url')" \
  --set queryQueueUrl="$(terraform output -raw helm_values | jq -r '.query_queue_url')" \
  --set subQueryQueueUrl="$(terraform output -raw helm_values | jq -r '.subquery_queue_url')" \
  --set streamQueueUrl="$(terraform output -raw helm_values | jq -r '.stream_queue_url')" \
  --set inputBucket="$(terraform output -raw helm_values | jq -r '.input_bucket')" \
  --set indexBucket="$(terraform output -raw helm_values | jq -r '.index_bucket')"
```

## AWS IAM Configuration

The pods need IAM permissions to access SQS queues and S3 buckets. Configure via service account annotations:

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
      "Sid": "SQSAccess",
      "Effect": "Allow",
      "Action": [
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage",
        "sqs:SendMessage",
        "sqs:GetQueueAttributes"
      ],
      "Resource": "arn:aws:sqs:*:*:*"
    },
    {
      "Sid": "S3SourceBucketRead",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject"
      ],
      "Resource": [
        "arn:aws:s3:::your-source-bucket/*"
      ]
    },
    {
      "Sid": "S3ResultsBucketReadWrite",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject"
      ],
      "Resource": [
        "arn:aws:s3:::your-results-bucket/*"
      ]
    },
    {
      "Sid": "S3ResultsBucketList",
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::your-results-bucket"
      ]
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

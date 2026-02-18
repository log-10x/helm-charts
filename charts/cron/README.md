# 🔟❎ Log10x Cron Helm chart

[Log10x](https://doc.log10x.com) is an observability runtime that executes in edge/cloud environments to optimize and reduce the cost of analyzing and storing log/trace data.

This chart sets up scheduled jobs to periodically executes a [Log10x pipeline](https://doc.log10x.com/architecture/pipeline/) inside k8.

Use this chart to set up periodic [Compile pipeline](https://doc.log10x.com/compile) or [Log10x Cloud Reporter](https://doc.log10x.com/apps/cloud/reporter/)

## How to deploy

Deployment instructions for Compile are found [Here](https://doc.log10x.com/apps/compiler/deploy/)

Deployment instructions for Cloud Reporter are found [Here](https://doc.log10x.com/apps/cloud/reporter/deploy/)

## Installation

To add the `log10x` helm repo, run:

```sh
helm repo add log10x https://log-10x.github.io/helm-charts
```

To install a release named `my-log10x-cron`, run:

```sh
helm install my-log10x-cron log10x/cron-10x
```

## Chart values

```sh
helm show values log10x/cron-10x
```

## Quick start

A minimal yaml setting up a periodic job is:

```yaml
log10xApiKey: "YOUR-LOG10X-API-KEY"

jobs:
    # Job name
  - name: my-job

    # Cron schedule https://en.wikipedia.org/wiki/Cron
    schedule: "*/10 * * * *"

    # Log10x pipeline args
    args:
      - "run"
```

For full chart options check out [values.yaml](values.yaml), or the [examples](https://github.com/log-10x/helm-charts/tree/main/charts/cron/examples) directory for complete sample configurations.

## Configuration

### Secrets management

#### Log10x API key

The chart requires a Log10x API key for authentication. By default, the chart creates a Kubernetes secret from the `log10xApiKey` value:

```yaml
log10xApiKey: "your-actual-api-key"

# API key secret configuration
apiKeySecret:
  create: true              # Create a new secret (default)
  existingSecret: ""        # Use an existing secret instead
  secretKey: "api-key"      # Key name within the secret
```

**Using an existing secret:**

```yaml
log10xApiKey: ""  # Leave empty when using existing secret

apiKeySecret:
  create: false
  existingSecret: "my-existing-secret"
  secretKey: "log10x-key"
```

**Security validation:** The chart will fail to deploy if `log10xApiKey` is empty when `apiKeySecret.create` is true.

#### GitHub access token

If your jobs need to fetch configuration or symbols from private GitHub repositories, provide a GitHub token:

```yaml
githubToken: "ghp_your_github_token"

jobs:
  - name: pipeline-with-config
    schedule: "0 * * * *"
    args: ["run"]

    github:
      config:
        repo: "owner/config-repo"
        branch: "main"  # Optional, uses default branch if omitted

      symbols:
        repo: "owner/symbols-repo"
        branch: "main"  # Optional
        path: "compiled/symbols"  # Optional, uses entire repo if omitted
```

The chart automatically:
- Creates a Kubernetes secret for the token
- Injects it securely via environment variable (not visible in pod specs)
- Only validates the token is present if jobs actually use GitHub integration

**Security note:** Tokens are stored in Kubernetes secrets and injected via the `GITHUB_TOKEN` environment variable, never exposed in command arguments or pod specifications.

### Volumes and storage

Jobs can mount volumes for accessing data or sharing state:

```yaml
jobs:
  - name: job-with-volumes
    schedule: "0 * * * *"
    args: ["run"]

    # Volume mounts for the main container
    volumeMounts:
      - name: data-volume
        mountPath: /data
      - name: config-volume
        mountPath: /config
        readOnly: true

    # Volume definitions
    volumes:
      - name: data-volume
        persistentVolumeClaim:
          claimName: my-pvc
      - name: config-volume
        configMap:
          name: my-config
```

### S3 integration with init containers

Pre-load files from S3 (or other sources) using init containers:

```yaml
jobs:
  - name: job-with-s3-data
    schedule: "0 * * * *"
    args: ["run"]

    # Custom init containers run before the main job
    initContainers:
      - name: s3-downloader
        image: amazon/aws-cli:latest
        command:
          - sh
          - -c
          - |
            aws s3 sync s3://my-bucket/data /data
        volumeMounts:
          - name: data-volume
            mountPath: /data
        env:
          - name: AWS_ACCESS_KEY_ID
            valueFrom:
              secretKeyRef:
                name: aws-credentials
                key: access-key-id
          - name: AWS_SECRET_ACCESS_KEY
            valueFrom:
              secretKeyRef:
                name: aws-credentials
                key: secret-access-key

    volumeMounts:
      - name: data-volume
        mountPath: /data

    volumes:
      - name: data-volume
        emptyDir: {}
```

### Resource management

Set resource requests and limits for your jobs. The default is empty (`{}`) to work in all environments including minikube/dev:

```yaml
jobs:
  - name: my-job
    schedule: "0 * * * *"
    args: ["run"]

    # Based on the default JVM heap of 2GB (-Xmx2048M)
    resources:
      limits:
        cpu: 1000m
        memory: 2560Mi
      requests:
        cpu: 500m
        memory: 2048Mi
```

**Note:** The Log10x pipeline runs with a JVM heap cap of 2GB (`-Xmx2048M`). Memory limits should account for JVM overhead (recommended: 2560Mi limit).

### Security contexts

Configure security settings at both pod and container levels:

```yaml
jobs:
  - name: secure-job
    schedule: "0 * * * *"
    args: ["run"]

    # Pod-level security context (affects all containers and volume permissions)
    podSecurityContext:
      runAsUser: 1000
      runAsGroup: 3000
      fsGroup: 2000
      runAsNonRoot: true

    # Container-level security context (capabilities and privileges)
    containerSecurityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: false
      capabilities:
        drop:
          - ALL
```

**Key differences:**
- **Pod security context:** Sets user/group IDs for all containers, controls volume ownership via `fsGroup`
- **Container security context:** Controls capabilities, privilege escalation, and root filesystem access per container

### Environment variables

Pass custom environment variables to your jobs:

```yaml
jobs:
  - name: my-job
    schedule: "0 * * * *"
    args: ["run"]

    env:
      - name: LOG_LEVEL
        value: "debug"
      - name: DATABASE_URL
        valueFrom:
          secretKeyRef:
            name: db-credentials
            key: url
```

### Config files

Provide additional configuration files via ConfigMap:

```yaml
jobs:
  - name: my-job
    schedule: "0 * * * *"
    args: ["run"]

    configFiles:
      - name: pipeline-config.yaml
        content: |
          version: 1
          settings:
            timeout: 300
```

Config files are mounted at `/etc/tenx/config/` in the container.

## Migration guide

### Migrating from github.config.token to githubToken

**Old format (deprecated):**
```yaml
jobs:
  - name: my-job
    github:
      config:
        repo: "owner/config-repo"
        token: "ghp_token_here"  # ❌ Deprecated
```

**New format:**
```yaml
githubToken: "ghp_token_here"  # ✅ Root-level, shared by all jobs

jobs:
  - name: my-job
    github:
      config:
        repo: "owner/config-repo"
        # No token field needed - uses root githubToken
```

**Benefits of new format:**
- Single token shared across all jobs in the chart
- Stored in Kubernetes secret automatically
- Injected via environment variable (more secure)
- Simpler configuration

## Under the hood

The chart deploys a [CronJob](https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/) for each defined job, as well as a [ConfigMap](https://kubernetes.io/docs/concepts/configuration/configmap/), which is used to provide the executed Log10x pipeline with additional config files.

**Resources created:**
- **CronJobs**: One per job defined in `values.yaml`
- **Secrets**: API key secret, GitHub token secret (if needed)
- **ConfigMap**: Contains config files specified in job definitions
- **ServiceAccount**: (Optional) For additional access to cluster resources

The chart also supports the creation of a k8 [ServiceAccount](https://kubernetes.io/docs/concepts/security/service-accounts/) to provide additional access to various services that might be needed, such as [AWS access via IAM roles](https://docs.aws.amazon.com/eks/latest/userguide/associate-service-account-role.html)

### GitHub config fetcher

When jobs specify `github.config` or `github.symbols`, the chart automatically adds an init container using the `github-config-fetcher` image (`ghcr.io/log-10x/github-config-fetcher`). This init container:

- Clones specified GitHub repositories before the main job runs
- Supports authentication via the `githubToken` secret
- Places config files in `/data/config/`
- Places symbols in `/data/config/data/shared/symbols/`

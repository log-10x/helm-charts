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

#### Git access token

If your jobs need to fetch configuration or symbols from private Git repositories, provide a token via the root-level `gitToken` field. This works with any Git provider (GitHub, GitLab, Bitbucket, self-hosted).

```yaml
gitToken: "your-git-access-token"

jobs:
  - name: pipeline-with-config
    schedule: "0 * * * *"
    args: ["run"]

    config:
      git:
        enabled: true
        url: "https://github.com/owner/config-repo.git"
        # branch: "main"  # Optional, uses default branch if omitted
      volume:
        enabled: false
        claimName: ""

    symbols:
      git:
        enabled: true
        url: "https://github.com/owner/symbols-repo.git"
        # branch: "main"  # Optional
        # path: "compiled/symbols"  # Optional sub-path within the repo
      volume:
        enabled: false
        claimName: ""
```

Each of `config` and `symbols` supports two methods:
- **git**: An init container clones the repository before the main container starts.
- **volume**: Mounts an existing PersistentVolumeClaim (for air-gapped environments or config managed outside of Git).

The chart automatically:
- Creates a Kubernetes secret for the token (when `gitToken` is non-empty)
- Injects it via the `GIT_TOKEN` environment variable using a `secretKeyRef` (not visible in pod specs)
- Only mounts the token into pods that have git integration enabled

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

### Migrating from github to config.git / symbols.git

**Old format (deprecated):**
```yaml
githubToken: "ghp_token_here"

jobs:
  - name: my-job
    github:
      config:
        repo: "owner/config-repo"
        branch: "main"
      symbols:
        repo: "owner/symbols-repo"
```

**New format:**
```yaml
gitToken: "your-git-access-token"  # Root-level, shared by all jobs

jobs:
  - name: my-job
    config:
      git:
        enabled: true
        url: "https://github.com/owner/config-repo.git"
        # branch: "main"
    symbols:
      git:
        enabled: true
        url: "https://github.com/owner/symbols-repo.git"
```

**What changed:**
- `githubToken` renamed to `gitToken` (provider-agnostic)
- `github.config.repo` replaced by `config.git.url` (full HTTPS URL instead of `owner/repo` shorthand)
- `github.symbols` replaced by `symbols.git` (same URL format)
- Each section now also supports `volume` for PVC-based config loading
- `enabled: true` is required to activate git cloning

## Under the hood

The chart deploys a [CronJob](https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/) for each defined job, as well as a [ConfigMap](https://kubernetes.io/docs/concepts/configuration/configmap/), which is used to provide the executed Log10x pipeline with additional config files.

**Resources created:**
- **CronJobs**: One per job defined in `values.yaml`
- **Secrets**: API key secret, Git token secret (if needed)
- **ConfigMap**: Contains config files specified in job definitions
- **ServiceAccount**: (Optional) For additional access to cluster resources

The chart also supports the creation of a k8 [ServiceAccount](https://kubernetes.io/docs/concepts/security/service-accounts/) to provide additional access to various services that might be needed, such as [AWS access via IAM roles](https://docs.aws.amazon.com/eks/latest/userguide/associate-service-account-role.html)

### Git config fetcher

When jobs specify `config.git` or `symbols.git`, the chart automatically adds an init container using the `git-config-fetcher` image (`log10x/git-config-fetcher`). This init container:

- Clones specified Git repositories before the main job runs
- Works with any Git provider (GitHub, GitLab, Bitbucket, self-hosted)
- Supports authentication via the `gitToken` secret
- Places config files in `/data/config/`
- Places symbols in `/data/config/data/shared/symbols/`

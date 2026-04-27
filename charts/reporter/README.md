# 🔟❎ Log10x Reporter Helm chart

[Log10x](https://doc.log10x.com) is an observability runtime that executes in edge/cloud environments to optimize and reduce the cost of analyzing and storing log/trace data.

This chart deploys a non-invasive [Log10x Reporter](https://doc.log10x.com/apps/reporter/) as a parallel DaemonSet that tails container logs, ships them to a co-located Log10x engine sidecar, and reports analytics back to the Log10x SaaS backend without replacing your existing log forwarder.

Use this chart to add cost visibility and pattern analysis on top of your current logging stack with zero changes to applications or existing forwarders.

## How to deploy

Deployment instructions for the Reporter are found [Here](https://doc.log10x.com/apps/reporter/deploy/)

## Installation

To add the `log10x` helm repo, run:

```sh
helm repo add log10x https://log-10x.github.io/helm-charts
```

To install a release named `my-log10x-reporter`, run:

```sh
helm install my-log10x-reporter log10x/reporter-10x
```

## Chart values

```sh
helm show values log10x/reporter-10x
```

## Quick start

A minimal yaml setting up reporting is:

```yaml
log10xApiKey: "YOUR-LOG10X-API-KEY"
```

That's all — defaults collect logs from all namespaces and ship them to the 10x sidecar with a ~250 Mi / 150m CPU per-node footprint (under 3% of a typical node).

For full chart options check out [values.yaml](values.yaml), or the [examples](https://github.com/log-10x/helm-charts/tree/main/charts/reporter/examples) directory for complete sample configurations.

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

If your reporter pipeline needs to fetch configuration or symbols from private Git repositories, provide a token via the root-level `gitToken` field. This works with any Git provider (GitHub, GitLab, Bitbucket, self-hosted).

```yaml
gitToken: "your-git-access-token"

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

### Log filtering

Control which container logs the DaemonSet collects:

```yaml
# Namespace allowlist (only these namespaces collected; empty = all)
includeNamespaces:
  - default
  - my-app

# Namespace blocklist (these namespaces excluded)
excludeNamespaces:
  - kube-system
  - kube-public

# Grep-based content filters (Fluent Bit grep filter)
includePatterns:
  - key: log
    regex: "ERROR|WARN"

excludePatterns:
  - key: kubernetes.namespace_name
    regex: "kube-system"
```

Patterns use [Fluent Bit's grep filter](https://docs.fluentbit.io/manual/pipeline/filters/grep). Provide one of `include`/`exclude` per pattern.

### Resource management

Defaults are tuned for typical clusters (~250 Mi memory, 150m CPU per node):

```yaml
fluentbit:
  resources:
    requests:
      cpu: 50m
      memory: 64Mi
    limits:
      cpu: 100m
      memory: 128Mi

tenx:
  resources:
    requests:
      cpu: 100m
      memory: 192Mi
    limits:
      cpu: 300m
      memory: 384Mi
```

For high-volume environments (>1000 containers/node or sustained >10K events/sec), consider increasing the `tenx` sidecar to ~300 Mi request / 512 Mi limit and 200m CPU limit.

### DaemonSet placement

Standard pod-placement controls for restricting where the reporter runs:

```yaml
nodeSelector:
  workload: logging

tolerations:
  - key: dedicated
    operator: Equal
    value: logging
    effect: NoSchedule

affinity: {}

updateStrategy:
  type: RollingUpdate
  rollingUpdate:
    maxUnavailable: 1
```

### Service account

For mounting cloud credentials (e.g. IAM roles for service accounts on EKS):

```yaml
serviceAccount:
  create: true
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/log10x-reporter
  name: ""

rbac:
  create: true
```

### Environment variables

Pass extra env vars to either container independently:

```yaml
# Fluent Bit container
extraEnv:
  - name: FB_LOG_LEVEL
    value: "debug"

# 10x sidecar container
tenxExtraEnv:
  - name: TENX_DEBUG
    value: "true"
```

## Under the hood

The chart deploys a [DaemonSet](https://kubernetes.io/docs/concepts/workloads/controllers/daemonset/) with two containers per pod, one pod per node.

**Resources created:**
- **DaemonSet**: One pod per node, two containers each (Fluent Bit + 10x sidecar)
- **Service**: ClusterIP exposing the Fluent Bit metrics endpoint (port 2020)
- **Secrets**: API key secret, Git token secret (if needed)
- **ServiceAccount + RBAC**: For namespace and pod metadata access
- **ConfigMap**: Fluent Bit configuration

### Data flow

```
Container logs → Fluent Bit (tailer) → Unix socket (Forward protocol) → 10x sidecar → Log10x SaaS
```

1. **Fluent Bit** tails container log files from the host's `/var/log/containers` (read-only mount), enriches with Kubernetes metadata, applies the include/exclude filters, and forwards to the 10x sidecar via a Unix socket.
2. **10x sidecar** runs the `@apps/reporter` pipeline against the incoming events: classification, pattern detection, cost analysis, and ships results to the Log10x SaaS backend.

The two containers communicate via a shared `emptyDir` volume containing the Unix socket — no network port between them. The data path stays private to the pod with no listening tcp surface.

### Git config fetcher

When `config.git.enabled` or `symbols.git.enabled` is set, the chart adds an init container using the `git-config-fetcher` image (`log10x/git-config-fetcher`). This init container:

- Clones specified Git repositories before the main containers start
- Works with any Git provider (GitHub, GitLab, Bitbucket, self-hosted)
- Supports authentication via the `gitToken` secret
- Places config files in `/data/config/`
- Places symbols in `/data/config/data/shared/symbols/`

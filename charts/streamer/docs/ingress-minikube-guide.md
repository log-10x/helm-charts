# Ingress Setup Guide for Minikube

This guide walks you through enabling and testing the streamer chart's Ingress functionality on a local minikube cluster.

## Overview

The streamer Helm chart (v0.6.0+) supports Kubernetes Ingress for exposing REST endpoints. This allows you to manually invoke index and query operations via HTTP instead of (or in addition to) SQS queues.

**What you'll expose:**
- `POST /streamer/index` - Trigger index operations
- `POST /streamer/query` - Run queries
- `GET /metrics/load` - View cluster load metrics

**What's NOT exposed:**
- `POST /pipeline` - Internal debugging endpoint (not exposed via ingress for security)

## Prerequisites

- **minikube** installed (v1.30.0+)
- **kubectl** installed and configured
- **Helm** installed (v3.0.0+)
- **Docker Desktop** running (for minikube driver)

### Verify Prerequisites

```bash
# Check minikube
minikube version
# Expected: minikube version: v1.30.0 or higher

# Check kubectl
kubectl version --client
# Expected: Client Version: v1.28.0 or higher

# Check Helm
helm version
# Expected: version.BuildInfo{Version:"v3.x.x"...}
```

## Step 1: Start Minikube

Start a fresh minikube cluster:

```bash
minikube start
```

**Expected output:**
```
✓ minikube v1.36.0 on Microsoft Windows 11
✓ Automatically selected the docker driver
✓ Starting "minikube" primary control-plane node in "minikube" cluster
✓ Creating docker container (CPUs=2, Memory=7900MB) ...
✓ Preparing Kubernetes v1.33.1 on Docker 28.1.1 ...
✓ Done! kubectl is now configured to use "minikube" cluster
```

### Verify Cluster is Running

```bash
kubectl cluster-info
```

**Expected output:**
```
Kubernetes control plane is running at https://127.0.0.1:xxxxx
CoreDNS is running at https://127.0.0.1:xxxxx/api/v1/namespaces/...
```

## Step 2: Enable NGINX Ingress

Enable the NGINX ingress controller addon:

```bash
minikube addons enable ingress
```

**Expected output:**
```
✓ ingress is an addon maintained by Kubernetes
  - Using image registry.k8s.io/ingress-nginx/controller:v1.12.2
✓ Verifying ingress addon...
✓ The 'ingress' addon is enabled
```

### Wait for Ingress Controller to be Ready

The ingress controller needs a moment to start. Wait for it:

```bash
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s
```

**Expected output:**
```
pod/ingress-nginx-controller-xxxxx-xxxxx condition met
```

### Verify Ingress Controller

```bash
kubectl get pods -n ingress-nginx
```

**Expected output:**
```
NAME                                       READY   STATUS    RESTARTS   AGE
ingress-nginx-controller-xxxxx-xxxxx       1/1     Running   0          2m
```

## Step 3: Prepare Your Configuration

Create a `values.yaml` file with your specific configuration.

### Minimum Configuration (For Testing)

Create `test-values.yaml`:

```yaml
# Required: Your Log10x API key
log10xApiKey: "your-api-key-here"

# Required: AWS S3 buckets
inputBucket: "your-input-bucket"
indexBucket: "your-index-bucket/path/"

# Required: AWS SQS queue URLs
indexQueueUrl: "https://sqs.us-east-1.amazonaws.com/YOUR_ACCOUNT/index-queue"
queryQueueUrl: "https://sqs.us-east-1.amazonaws.com/YOUR_ACCOUNT/query-queue"
subQueryQueueUrl: "https://sqs.us-east-1.amazonaws.com/YOUR_ACCOUNT/subquery-queue"
streamQueueUrl: "https://sqs.us-east-1.amazonaws.com/YOUR_ACCOUNT/stream-queue"

# Ingress configuration
defaultIngress:
  enabled: true           # Enable ingress
  className: nginx        # Use NGINX ingress controller
  host: "streamer.local"  # Hostname for accessing endpoints
  tls:
    enabled: false        # Disable TLS for local testing

# Single cluster for testing
clusters:
  - name: test-cluster
    roles: ["index", "query"]  # Handle both index and query operations
    replicaCount: 1

    # AWS credentials (required for S3/SQS access)
    extraEnv:
      - name: AWS_ACCESS_KEY_ID
        value: "your-access-key"
      - name: AWS_SECRET_ACCESS_KEY
        value: "your-secret-key"
      - name: AWS_REGION
        value: "us-east-1"

    resources:
      requests:
        memory: 2Gi
        cpu: 1000m
      limits:
        memory: 2Gi
        cpu: 2000m
```

**Security Note**: For production, use IRSA (IAM Roles for Service Accounts) instead of embedding credentials. See the main values.yaml for `serviceAccount.annotations` configuration.

### Advanced Configuration (Multiple Clusters)

For production-like testing with separate index and query clusters:

```yaml
# ... (same required fields as above) ...

defaultIngress:
  enabled: true
  className: nginx
  annotations:
    # Example: Add rate limiting
    nginx.ingress.kubernetes.io/limit-rps: "100"

# Separate clusters by role
clusters:
  - name: indexer
    roles: ["index"]
    replicaCount: 1
    ingress:
      host: "indexer.streamer.local"  # Custom host for indexer
    extraEnv:
      - name: AWS_ACCESS_KEY_ID
        value: "your-key"
      # ... other env vars ...
    resources:
      requests:
        memory: 4Gi  # Index operations need more memory
        cpu: 2000m

  - name: query-handler
    roles: ["query"]
    replicaCount: 2
    ingress:
      host: "query.streamer.local"  # Custom host for queries
    extraEnv:
      - name: AWS_ACCESS_KEY_ID
        value: "your-key"
      # ... other env vars ...
    resources:
      requests:
        memory: 2Gi
        cpu: 1000m

  - name: stream-worker
    roles: ["stream"]
    replicaCount: 3
    # No ingress config - stream workers don't expose REST endpoints
    extraEnv:
      - name: AWS_ACCESS_KEY_ID
        value: "your-key"
      # ... other env vars ...
```

## Step 4: Install the Chart

Navigate to the chart directory and install:

```bash
# Navigate to chart directory
cd path/to/helm-charts/charts/streamer

# Install the chart
helm install my-streamer . -f test-values.yaml
```

**Expected output:**
```
NAME: my-streamer
LAST DEPLOYED: ...
NAMESPACE: default
STATUS: deployed
REVISION: 1
NOTES:
Thank you for installing streamer-10x!

Your release is named my-streamer.

The following clusters have been deployed:
  - test-cluster (1 replica)
    * Index: Enabled
    * Query: Enabled

Ingress Configuration:
  - Cluster: test-cluster
    Host: streamer.local
    TLS: Disabled (HTTP only - NOT recommended for production!)
    Exposed endpoints:
      * POST http://streamer.local/streamer/index - Index files
      * POST http://streamer.local/streamer/query - Run queries
      * GET http://streamer.local/metrics/load - View load metrics

⚠️  SECURITY WARNING: No authentication configured on ingress!
  [... authentication examples ...]
```

### Verify Installation

```bash
# Check pods are running
kubectl get pods -l app=streamer-10x

# Check services
kubectl get services -l app=streamer-10x

# Check ingress
kubectl get ingress -l app=streamer-10x
```

**Expected output:**
```
NAME                                    READY   STATUS    RESTARTS   AGE
my-streamer-streamer-10x-test-cluster   1/1     Running   0          30s

NAME                                    TYPE        CLUSTER-IP      PORT(S)   AGE
my-streamer-streamer-10x-test-cluster   ClusterIP   10.96.xxx.xxx   80/TCP    30s

NAME                                    CLASS   HOSTS            ADDRESS        PORTS   AGE
my-streamer-streamer-10x-test-cluster   nginx   streamer.local   192.168.49.2   80      30s
```

## Step 5: Access the Endpoints

There are two methods to access your endpoints in minikube:

### Method A: Port Forwarding (Recommended for Testing)

This method bypasses ingress and connects directly to the service. It's the most reliable for local testing:

```bash
# Forward local port 8080 to the service
kubectl port-forward svc/my-streamer-streamer-10x-test-cluster 8080:80
```

Keep this terminal open. In a new terminal, test the endpoints:

```bash
# Test the metrics endpoint
curl http://localhost:8080/metrics/load

# Expected response:
# {"activeTasks":0,"queuedTasks":0,"completedTasks":0,...}
```

### Method B: Minikube Tunnel (Tests Actual Ingress)

This method sets up networking to access the ingress controller. Requires admin privileges:

```bash
# Start tunnel (requires admin/sudo)
minikube tunnel
```

**Note**: On Windows, this will prompt for Administrator access. Leave this terminal open.

In a new terminal, you need to add `streamer.local` to your hosts file:

**Windows** (`C:\Windows\System32\drivers\etc\hosts`):
```
192.168.49.2  streamer.local
```

**macOS/Linux** (`/etc/hosts`):
```
192.168.49.2  streamer.local
```

Then test via ingress:

```bash
curl http://streamer.local/metrics/load
```

**Troubleshooting Tunnel Issues**:
- Port 80 conflicts: If you see connection timeout, port 80 might be occupied
- Use Method A (port-forward) as a reliable alternative
- Check minikube IP: `minikube ip` (should be 192.168.49.2)

## Step 6: Test the REST Endpoints

### Test 1: Load Metrics (GET)

```bash
# Via port-forward
curl http://localhost:8080/metrics/load

# Via ingress
curl http://streamer.local/metrics/load
```

**Expected response:**
```json
{
  "activeTasks": 0,
  "queuedTasks": 0,
  "completedTasks": 0,
  "maxAsync": 10,
  "maxQueued": 1000,
  "currentLoad": 0,
  "totalCapacity": 1010,
  "loadPercent": 0
}
```

### Test 2: Index Operation (POST)

Trigger an index operation:

```bash
curl -X POST http://localhost:8080/streamer/index \
  -H "Content-Type: application/json" \
  -d '{
    "readContainer": "your-bucket-name",
    "readObject": "path/to/logfile.log"
  }'
```

**Expected response:**
- HTTP 200: Successfully queued
- HTTP 400: Invalid request (missing required fields)

**Monitor the logs:**
```bash
kubectl logs -l cluster=test-cluster --tail=20 -f
```

Look for:
```
[INFO] PipelineLaunchTask - starting pipeline - {"tenx":"@/apps/cloud/streamer/index"...}
```

### Test 3: Query Operation (POST)

Run a query:

```bash
curl -X POST http://localhost:8080/streamer/query \
  -H "Content-Type: application/json" \
  -d '{
    "search": "(severity_level == \"ERROR\")",
    "from": "2024-01-01T00:00:00Z",
    "to": "2024-01-02T00:00:00Z"
  }'
```

**Expected response:**
- HTTP 200: Query started
- Check logs for pipeline execution

**Monitor progress:**
```bash
# Watch query pipelines start
kubectl logs -l cluster=test-cluster --tail=50 -f | grep "query"
```

### Test 4: Verify Ingress Path Filtering

The `/pipeline` endpoint should NOT be accessible via ingress (only via direct pod access for debugging):

```bash
# This should fail (404 or similar) when going through ingress
curl http://streamer.local/pipeline

# But works via port-forward (direct to pod)
curl http://localhost:8080/pipeline
```

## Step 7: Monitor and Debug

### View Application Logs

```bash
# Tail logs
kubectl logs -l cluster=test-cluster --tail=50 -f

# Search for errors
kubectl logs -l cluster=test-cluster | grep ERROR

# View recent pipeline invocations
kubectl logs -l cluster=test-cluster | grep PipelineLaunchTask
```

### Check Ingress Details

```bash
# View full ingress configuration
kubectl get ingress my-streamer-streamer-10x-test-cluster -o yaml

# Check ingress paths
kubectl get ingress my-streamer-streamer-10x-test-cluster \
  -o jsonpath='{.spec.rules[0].http.paths[*].path}' && echo
```

### Check Pod Status

```bash
# Detailed pod information
kubectl describe pod -l cluster=test-cluster

# Check readiness and liveness probes
kubectl get pods -l cluster=test-cluster -o wide
```

### NGINX Ingress Controller Logs

If having ingress issues:

```bash
# View ingress controller logs
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller --tail=50
```

## Common Issues and Solutions

### Issue 1: Pods Not Starting

**Symptoms:**
```
my-streamer-streamer-10x-test-cluster   0/1     Pending   0          5m
```

**Solutions:**
```bash
# Check events
kubectl describe pod -l cluster=test-cluster

# Common causes:
# - Insufficient resources: Increase minikube memory
minikube start --memory=8192 --cpus=4

# - Image pull issues: Check image pull policy in values.yaml
```

### Issue 2: Connection Timeout to Ingress

**Symptoms:**
```
curl: (28) Failed to connect to streamer.local port 80: Connection timed out
```

**Solutions:**
```bash
# 1. Check minikube tunnel is running
minikube tunnel  # In a separate terminal

# 2. Verify ingress IP
kubectl get ingress

# 3. Check hosts file has correct IP
cat /etc/hosts | grep streamer  # macOS/Linux
type C:\Windows\System32\drivers\etc\hosts | findstr streamer  # Windows

# 4. Use port-forward instead
kubectl port-forward svc/my-streamer-streamer-10x-test-cluster 8080:80
curl http://localhost:8080/metrics/load
```

### Issue 3: 404 Not Found

**Symptoms:**
```
HTTP 404: endpoint not found
```

**Solutions:**
```bash
# 1. Check ingress paths are correct
kubectl get ingress my-streamer-streamer-10x-test-cluster \
  -o jsonpath='{.spec.rules[0].http.paths[*].path}' && echo

# 2. Verify you're using the correct cluster role
kubectl get ingress my-streamer-streamer-10x-test-cluster -o yaml | grep -A 5 paths

# 3. Check service endpoints
kubectl get endpoints my-streamer-streamer-10x-test-cluster
```

### Issue 4: Helm Install Fails - Ingress Webhook

**Symptoms:**
```
Error: failed calling webhook "validate.nginx.ingress.kubernetes.io": connection refused
```

**Solution:**
Wait for NGINX ingress controller to be fully ready:

```bash
# Wait for controller
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s

# Then try helm install again
helm install my-streamer . -f test-values.yaml
```

### Issue 5: AWS Credentials Not Working

**Symptoms:**
```
AWSSecurityTokenServiceException: The security token included in the request is invalid
```

**Solutions:**
```bash
# 1. Verify credentials are set in extraEnv
kubectl get deployment -o yaml | grep -A 5 AWS_ACCESS_KEY

# 2. Test credentials from pod
kubectl exec -it <pod-name> -- env | grep AWS

# 3. For production, use IRSA instead:
# Add to values.yaml:
serviceAccount:
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT:role/ROLE_NAME
```

## Cleanup

When you're done testing:

```bash
# Uninstall the chart
helm uninstall my-streamer

# Stop minikube tunnel (if running)
# Ctrl+C in the tunnel terminal

# Stop minikube
minikube stop

# Delete minikube cluster (optional)
minikube delete
```

## Next Steps

### Add TLS (HTTPS)

For testing with TLS:

1. Create self-signed certificate:
```bash
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout tls.key -out tls.crt \
  -subj "/CN=streamer.local"

kubectl create secret tls streamer-tls-secret \
  --cert=tls.crt --key=tls.key
```

2. Update `test-values.yaml`:
```yaml
defaultIngress:
  tls:
    enabled: true
    source: "secret"
    secretName: "streamer-tls-secret"
```

3. Reinstall and access via HTTPS:
```bash
curl -k https://streamer.local/metrics/load  # -k ignores self-signed cert warning
```

### Add Authentication

Example: Basic Auth with NGINX

1. Create password file:
```bash
htpasswd -c auth admin
# Enter password when prompted

kubectl create secret generic streamer-basic-auth --from-file=auth
```

2. Update `test-values.yaml`:
```yaml
defaultIngress:
  annotations:
    nginx.ingress.kubernetes.io/auth-type: basic
    nginx.ingress.kubernetes.io/auth-secret: streamer-basic-auth
    nginx.ingress.kubernetes.io/auth-realm: "Authentication Required"
```

3. Test with credentials:
```bash
curl -u admin:password http://streamer.local/metrics/load
```

### Production Deployment

For deploying to a real Kubernetes cluster (EKS, GKE, AKS):

1. Use proper DNS instead of hosts file
2. Enable TLS with real certificates (Let's Encrypt via cert-manager)
3. Use IRSA/Workload Identity instead of embedded credentials
4. Configure authentication (OAuth, Cognito, etc.)
5. Set resource limits based on actual workload
6. Enable autoscaling for production traffic
7. Configure proper monitoring and alerting

See the main [values.yaml](../values.yaml) for all available configuration options.

## Additional Resources

- [Minikube Documentation](https://minikube.sigs.k8s.io/docs/)
- [NGINX Ingress Controller](https://kubernetes.github.io/ingress-nginx/)
- [Kubernetes Ingress Concepts](https://kubernetes.io/docs/concepts/services-networking/ingress/)
- [Helm Documentation](https://helm.sh/docs/)

## Support

For issues or questions:
- GitHub Issues: https://github.com/log-10x/helm-charts/issues
- Chart Version: Check `Chart.yaml` for current version

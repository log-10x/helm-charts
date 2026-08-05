# cron-10x

Runs the [10x Compiler](https://doc.log10x.com/compile/) on a schedule: a Kubernetes CronJob that pulls sources, scans them for log statements, links the result into a symbol library and pushes it back to a config repository.

## Install

```console
helm repo add log10x https://log-10x.github.io/helm-charts
helm repo update

helm install my-compiler log10x/cron-10x \
  --set-file tenx.licenseJwt=./license.jwt \
  -f my-compiler.yaml
```

Download the licence from [console.log10x.com](https://console.log10x.com). Prefer `--set-file` over `--set` so the JWT never lands in shell history. An install with no licence fails at render time rather than scheduling a CronJob whose every run exits non-zero.

Example values files are in [`examples/`](examples): `minimal.yaml`, `gitops.yaml`, `airgapped.yaml`.

## The image

The chart runs `log10x/compiler-10x`, tag defaulting to the chart `appVersion`.

The compiler's [pull stage](https://doc.log10x.com/compile/pull/) shells out to fetch source repositories, container images and charts, so the image has to carry that toolchain. Measured on `compiler-10x:1.1.45`:

| Tool | Path | Version |
|------|------|---------|
| `git` | `/usr/bin/git` | 2.43.7 |
| `docker` | `/usr/local/bin/docker` | symlink to `/usr/bin/podman` 4.9.4 |
| `helm` | `/usr/local/bin/helm` | v3.16.4 |

The docker CLI is podman, which matters in a good way: image pulls work inside the pod with no host docker socket mounted and no privileged container. `kubectl` is not present.

The lean `log10x/pipeline-10x` runtime image carries none of the three, which is why earlier versions of this chart could only ever scan what was already on disk.

## The licence

The engine reads the licence from `TENX_LICENSE_FILE` or `TENX_LICENSE_KEY`. Nothing reads `TENX_API_KEY`; it appears nowhere in the compiler image's config tree, where the compile bootstrap resolves

```yaml
licenseKey:  $=TenXEnv.get("TENX_LICENSE_KEY", "NO-LICENSE")
licenseFile: $=TenXEnv.get("TENX_LICENSE_FILE")
```

`tenx.licenseDelivery` picks between them. `file`, the default, projects the Secret to `/etc/tenx/license/<licenseSecretKey>` and points `TENX_LICENSE_FILE` at it, which keeps the token out of the process environment and lets a Secret rotation rotate the file in place. `env` injects `TENX_LICENSE_KEY` through a `secretKeyRef`.

`log10xApiKey`, `apiKeySecret.*` and `log10xLicense` are deprecated. When no `tenx.license*` value is set the chart reads them as the licence JWT, so an existing install starts working instead of silently continuing to do nothing.

## Values

| Key | Default | Description |
|-----|---------|-------------|
| `image.repository` | `log10x/compiler-10x` | Compiler image |
| `image.tag` | `""` | Defaults to `.Chart.AppVersion` |
| `configFetcherImage.tag` | `1.0.0` | Git config fetcher init container |
| `tenx.licenseJwt` | `""` | Licence JWT; the chart creates the Secret |
| `tenx.licenseSecret` | `""` | Existing Secret holding the JWT; takes precedence |
| `tenx.licenseSecretKey` | `license-jwt` | Key inside the Secret |
| `tenx.licenseDelivery` | `file` | `file` or `env` |
| `tenx.airgapped` | `false` | Sets `TENX_AIRGAPPED`, no calls to the vendor gateway |
| `gitToken` | `""` | Token for private config and symbol repositories |
| `jobs` | one `compiler-job` | List of scheduled compiles |
| `podSecurityContext` | `runAsNonRoot: true` | Applied to every job that does not override it |
| `containerSecurityContext` | drops all capabilities | Applied to every job that does not override it |
| `serviceAccount.create` | `true` | |

### Per job

| Key | Default | Description |
|-----|---------|-------------|
| `name` | | Required. Becomes part of the CronJob name |
| `schedule` | | Required, cron syntax |
| `args` | | Required, normally `["@apps/compiler"]` |
| `timeZone` | unset | IANA zone, needs Kubernetes 1.27 or later |
| `suspend` | unset | Pause the schedule without uninstalling |
| `concurrencyPolicy` | `Forbid` | Two compiles writing one symbol library is not a default worth having |
| `activeDeadlineSeconds` | `3600` in the shipped job | Unset means a stuck run blocks every following one under `Forbid` |
| `backoffLimit` | `0` in the shipped job | The next tick is the retry |
| `startingDeadlineSeconds` | unset | |
| `restartPolicy` | `Never` | `Never` or `OnFailure` only |
| `runtimeName` | | Sets `TENX_RUNTIME_NAME` |
| `config.git` / `config.volume` | disabled | Config tree from a repository or a PVC |
| `symbols.git` / `symbols.volume` | disabled | Symbol files from a repository or a PVC |
| `extraEnv`, `initContainers`, `volumes`, `volumeMounts`, `configFiles` | empty | |
| `resources` | `{}` | A compile is CPU-bound while scanning and holds the symbol set in memory while linking |
| `nodeSelector`, `tolerations`, `affinity` | empty | Pod fields |

## Verify

Nothing runs until the schedule fires. To force a run:

```console
kubectl create job --from=cronjob/my-compiler-cron-10x-compiler-job compile-now
kubectl logs -l job-name=compile-now --tail=100
```

A successful run ends with a JSON report naming the `Scan` and `Link` phases and `"success": true`.

## Upgrading from 1.0.6

1.0.6 rendered `log10x/pipeline-10x` and set `TENX_API_KEY`. Both are corrected here, so an upgrade changes the image and the environment. Set `tenx.licenseJwt` or `tenx.licenseSecret`; if you leave `log10xApiKey` in place it is read as the licence.

1.0.6 also rendered `nodeSelector`, `tolerations` and `affinity` inside the container, and the API server rejects that outright:

```
strict decoding error: unknown field
"spec.jobTemplate.spec.template.spec.containers[0].nodeSelector"
```

so no values file that set one of them could be installed at all. They are pod fields again.

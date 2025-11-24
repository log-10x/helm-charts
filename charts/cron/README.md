# 🔟❎ Log10x Cron Helm chart

[Log10x](http://doc.log10x.com) is an observability runtime that executes in edge/cloud environments to optimize and reduce the cost of analyzing and storing log/trace data.

This chart sets up scheduled jobs to periodically executes a [Log10x pipeline](http://doc.log10x.com/concepts/pipeline) inside k8.

Use this chart to set up periodic [Compile pipeline](http://doc.log10x.com/compile) or [Log10x Cloud Reporter](http://doc.log10x.com/run/apps/cloud/reporter)

## How to deploy

Deployment instructions for Compile are found [Here](http://doc.log10x.com/deploy/compile)

Deployment instructions for Cloud Reporter are found [Here](http://doc.log10x.com/deploy/apps/cloud/reporter)

## Installation

To add the `log10x` helm repo, run:

```sh
helm repo add log10x https://log-10x.github.io/helm-charts
```

To install a release named `my-log10x-cron`, run:

```sh
helm install my-log10x-cron log10x/log10x-cron
```

## Chart values

```sh
helm show values log10x/log10x-cron
```

## Example usage

A minimal yaml setting up a periodic job is:

```yaml
log10xApiKey: "YOUR-API-KEY"

jobs:
    # Job name
  - name: my-job

    # Cron schedule https://en.wikipedia.org/wiki/Cron
    schedule: "*/10 * * * *"

    # Log10x pipeline args
    args:
      - "run"
```

For full chart options check out [values.yaml](values.yaml), or a complete [Cloud Reporter sample](https://github.com/log-10x/helm-charts/blob/main/samples/log10x-cloud-reporter.yaml)


## Under the hood

The chart deploys a [CronJob](https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/) for each defined job, as well as a [ConfigMap](https://kubernetes.io/docs/concepts/configuration/configmap/), which is used to provide the executed Log10x pipeline with additional config files.

The chart also supports the creation of a k8 [ServiceAccount](https://kubernetes.io/docs/concepts/security/service-accounts/) to provide additional access to various services that might be needed, such as [AWS access via IAM roles](https://docs.aws.amazon.com/eks/latest/userguide/associate-service-account-role.html)

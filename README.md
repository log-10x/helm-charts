# 🔟❎ Helm Charts

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![Release Status](https://github.com/log-10x/helm-charts/actions/workflows/release.yaml/badge.svg?branch=main)](https://github.com/log-10x/helm-charts/actions)

Helm charts for deploying Log10x pipelines

[Log10x](http://doc.log10x.com) is an observability runtime that executes in edge/cloud environments to optimize and reduce the cost of analyzing and storing log/trace data.

## Log10x Quarkus

The [Log10x Quarkus](https://github.com/log-10x/helm-charts/tree/main/charts/log10x-quarkus) chart facilitates deploying of a long living cluster of [Quarkus-backed](https://quarkus.io/) Log10x servers with an exposed api endpoint for invoking Log10x pipelines on demand.

For more details on the deployed images, see - https://github.com/log-10x/docker-images/tree/main/quarkus

## Log10x Cron

The [Log10x Cron](https://github.com/log-10x/helm-charts/tree/main/charts/log10x-cron) chart sets up periodic cron jobs for running pre-defined Log10x pipelines based on a schedule

For more details on the deployed images, see - https://github.com/log-10x/docker-images/tree/main/pipeline

## Usage

[Helm](https://helm.sh) must be installed to use the charts.
Please refer to Helm's [documentation](https://helm.sh/docs/) to get started.

Once Helm is set up properly, add the repo as follows:

```sh
helm repo add log10x https://log-10x.github.io/helm-charts
```

You can then run `helm search repo Log10x` to see the charts.

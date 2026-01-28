# 🔟❎ Helm Charts

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![Release Status](https://github.com/log-10x/helm-charts/actions/workflows/release.yaml/badge.svg?branch=main)](https://github.com/log-10x/helm-charts/actions)

Helm charts for deploying Log10x pipelines

[Log10x](https://doc.log10x.com) is an observability runtime that executes in edge/cloud environments to optimize and reduce the cost of analyzing and storing log/trace data.

## Log10x Streamer

The [Log10x Streamer](https://github.com/log-10x/helm-charts/tree/main/charts/streamer) chart deploys long-living SQS-based streaming clusters for indexing, querying, and streaming log data on demand, with fluent-bit sidecars for output delivery.

For more details on the deployed images, see - https://github.com/log-10x/docker-images/tree/main/quarkus

## Log10x Cron

The [Log10x Cron](https://github.com/log-10x/helm-charts/tree/main/charts/cron) chart sets up periodic cron jobs for running pre-defined Log10x pipelines based on a schedule.

For more details on the deployed images, see - https://github.com/log-10x/docker-images/tree/main/pipeline

## Usage

[Helm](https://helm.sh) must be installed to use the charts.
Please refer to Helm's [documentation](https://helm.sh/docs/) to get started.

Once Helm is set up properly, add the repo as follows:

```sh
helm repo add log10x https://log-10x.github.io/helm-charts
```

You can then run `helm search repo Log10x` to see the charts.

## License

This repository is licensed under the [Apache License 2.0](LICENSE).

### Important: Log10x Product License Required

This repository contains deployment tooling for Log10x. While the tooling
itself is open source, **using Log10x requires a commercial license**.

| Component | License |
|-----------|---------|
| This repository (Helm charts) | Apache 2.0 (open source) |
| Log10x engine and runtime | Commercial license required |

**What this means:**
- You can freely use, modify, and distribute these Helm charts
- The Log10x software that these charts deploy requires a paid subscription
- A valid Log10x API key is required to run the deployed software

**Get Started:**
- [Log10x Pricing](https://log10x.com/pricing)
- [Documentation](https://doc.log10x.com)
- [Contact Sales](mailto:sales@log10x.com)

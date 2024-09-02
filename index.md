# Log10x Helm Charts

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![Release Status](https://github.com/log-10x/helm-charts/actions/workflows/release.yaml/badge.svg?branch=main)](https://github.com/log-10x/helm-charts/actions)

## Add the Log10x pipeline Helm repository

```sh
helm repo add log10x https://log-10x.github.io/helm-charts
```

## Install Log10x Quarkus

```sh
helm upgrade -i log10x-quarkus log10x/log10x-quarkus
```

For more details on installing Log10x Quarkus please see the [chart's README](https://github.com/log-10x/helm-charts/tree/main/charts/log10x-quarkus).

## Install Log10x Jobs

```sh
helm upgrade -i log10x-jobs log10x/log10x-jobs
```

For more details on installing Log10x Jobs please see the [chart's README](https://github.com/log-10x/helm-charts/tree/main/charts/log10x-jobs).

## License

[Apache 2.0 License](https://www.apache.org/licenses/LICENSE-2.0)

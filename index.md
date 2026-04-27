# 🔟❎ Log10x Helm Charts

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![Release Status](https://github.com/log-10x/helm-charts/actions/workflows/release.yaml/badge.svg?branch=main)](https://github.com/log-10x/helm-charts/actions)

## Add the Log10x Helm repository

```sh
helm repo add log10x https://log-10x.github.io/helm-charts
```

## Install the Log10x Reporter

```sh
helm upgrade -i log10x-reporter log10x/reporter-10x
```

For deployment details, see the [Log10x Reporter documentation](https://doc.log10x.com/apps/reporter/).

## Install the Log10x Retriever

```sh
helm upgrade -i log10x-retriever log10x/retriever-10x
```

For deployment details, see the [Log10x Retriever documentation](https://doc.log10x.com/apps/retriever/).

## License

[Apache 2.0 License](https://www.apache.org/licenses/LICENSE-2.0)

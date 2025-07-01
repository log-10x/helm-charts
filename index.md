# 10x Helm Charts

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![Release Status](https://github.com/log-10x/helm-charts/actions/workflows/release.yaml/badge.svg?branch=main)](https://github.com/log-10x/helm-charts/actions)

## Add the 10x Helm repository

```sh
helm repo add log10x https://log-10x.github.io/helm-charts
```

## Install 10x Quarkus

```sh
helm upgrade -i quarkus-10x log10x/quarkus-10x
```

For more details on deploying the Quarkus 10x server please see the [documentation](http://doc.log10x.com/apps/cloud/streamer/deploy).

## Install 10x Cron Jobs

```sh
helm upgrade -i log10x-jobs log10x/cron-10x
```

For more details on installing 10x Cron Jobs please see the [documentation](http://doc.log10x.com/apps/cloud/reporter/deploy).

## License

[Apache 2.0 License](https://www.apache.org/licenses/LICENSE-2.0)

# 🔟❎ Log10x Quarkus Helm chart

[Log10x](http://doc.log10x.com) is an observability runtime that executes in edge/cloud environments to optimize and reduce the cost of analyzing and storing log/trace data.

This chart sets up a cluster of Quarkus servers exposing a RestAPI endpoint which executes an [Log10x pipeline](http://doc.log10x.com/concepts/pipeline).

Use this chart to set up [Query cluster](http://doc.log10x.com/run/apps/cloud/stream/#query) for the [Log10x Storage Stream](http://doc.log10x.com/run/apps/cloud/stream)

## How to deploy

Deployment instructions for the Query cluster are found [Here](http://doc.log10x.com/deploy/apps/cloud/stream)

## Installation

To add the `log10x` helm repo, run:

```sh
helm repo add log10x https://log-10x.github.io/helm-charts
```

To install a release named `my-log10x-cluster`, run:

```sh
helm install my-log10x-cluster log10x/log10x-quarkus
```

## Chart values

```sh
helm show values log10x/log10x-quarkus
```

## Example usage

A minimal yaml setting up a cluster is:

```yaml
log10xApiKey: "YOUR-API-KEY"

# Sample cluster, exposing directly with LoadBalancer and no ingress, single replica, no autoscale
#
replicaCount: 1
service:
  type: LoadBalancer

# Sets up enough cpu resources to handle multiple requests in parallel
#
resources:
  requests:
    cpu: "8"
  limits:
    cpu: "8"
```

For full chart options check out [values.yaml](values.yaml), or a complete [Object Storage Query sample](https://github.com/log-10x/helm-charts/blob/main/samples/log10x-query.yaml)


## Under the hood

The chart deploys a "main" [Deployment](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/) of Quarkus servers exposed via a [Service](https://kubernetes.io/docs/concepts/services-networking/service/) and scalable via a [HorizontalPodAutoscaler](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/) for responding to RestAPI calls and invoking Log10x pipelines.

Additionally, a similar "worker" deploymet+service+hpa is deployed, allowing the main deployment to invoke sub-pipelines if needed, for example when executing an [Object Storage Query](http://doc.log10x.com/run/input/objectStorage/query/#__tabbed_1_2)

The chart also supports:
- Creation of a k8 [Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/) to expose the main deployment, for example when woriking with [AWS application load balancer](https://docs.aws.amazon.com/eks/latest/userguide/alb-ingress.html)
- Creation of a k8 [ServiceAccount](https://kubernetes.io/docs/concepts/security/service-accounts/) to provide additional access to various services that might be needed, such as [AWS access via IAM roles](https://docs.aws.amazon.com/eks/latest/userguide/associate-service-account-role.html)

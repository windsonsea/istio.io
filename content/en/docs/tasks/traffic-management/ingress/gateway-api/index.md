---
title: Kubernetes Gateway API
description: Describes how to configure the Kubernetes Gateway API with Istio.
weight: 50
aliases:
    - /docs/tasks/traffic-management/ingress/service-apis/
    - /latest/docs/tasks/traffic-management/ingress/service-apis/
keywords: [traffic-management,ingress, gateway-api]
owner: istio/wg-networking-maintainers
test: yes
---

In addition to its own traffic management API,
{{< boilerplate gateway-api-future >}}
This document describes the differences between the Istio and Kubernetes APIs and provides a simple example
that shows you how to configure Istio to expose a service outside the service mesh cluster using the Gateway API.
Note that these APIs are an actively developed evolution of the Kubernetes [Service](https://kubernetes.io/docs/concepts/services-networking/service/)
and [Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/) APIs.

{{< tip >}}
Many of the Istio traffic management documents include instructions for using either the Istio or Kubernetes API
(see the [control ingress traffic task](/docs/tasks/traffic-management/ingress/ingress-control), for example).
You can use the Gateway API, right from the start, by following the [getting started instructions](/docs/setup/getting-started/).
{{< /tip >}}

## Setup

1. The Gateway APIs do not come installed by default on most Kubernetes clusters. Install the Gateway API CRDs if they are not present:

    {{< text bash >}}
    $ kubectl get crd gateways.gateway.networking.k8s.io &> /dev/null || \
      { kubectl kustomize "github.com/kubernetes-sigs/gateway-api/config/crd?ref={{< k8s_gateway_api_version >}}" | kubectl apply -f -; }
    {{< /text >}}

1. Install Istio using the `minimal` profile:

    {{< text bash >}}
    $ istioctl install --set profile=minimal -y
    {{< /text >}}

## Differences from Istio APIs

The Gateway APIs share a lot of similarities to the Istio APIs such as Gateway and VirtualService.
The main resource shares the same name, `Gateway`, and the resources serve similar goals.

The new Gateway APIs aim to take the learnings from various Kubernetes ingress implementations, including Istio,
to build a standardized vendor neutral API. These APIs generally serve the same purposes as Istio Gateway and VirtualService,
with a few key differences:

* In Istio APIs, a `Gateway` *configures* an existing gateway Deployment/Service that has [been deployed](/docs/setup/additional-setup/gateway/).
  In the Gateway APIs, the `Gateway` resource both *configures and deploys* a gateway.
  See [Deployment Methods](#deployment-methods) for more information.
* In the Istio `VirtualService`, all protocols are configured within a single resource.
  In the Gateway APIs, each protocol type has its own resource, such as `HTTPRoute` and `TCPRoute`.
* While the Gateway APIs offer a lot of rich routing functionality, it does not yet cover 100% of Istio's feature set.
  Work is ongoing to extend the API to cover these use cases, as well as utilizing the APIs [extensibility](https://gateway-api.sigs.k8s.io/#gateway-api-concepts)
  to better expose Istio functionality.

## Configuring a Gateway

See the [Gateway API](https://gateway-api.sigs.k8s.io/) documentation for information about the APIs.

In this example, we will deploy a simple application and expose it externally using a `Gateway`.

1. First, deploy the `httpbin` test application:

    {{< text bash >}}
    $ kubectl apply -f @samples/httpbin/httpbin.yaml@
    {{< /text >}}

1. Deploy the Gateway API configuration including a single exposed route (i.e., `/get`):

    {{< text bash >}}
    $ kubectl create namespace istio-ingress
    $ kubectl apply -f - <<EOF
    apiVersion: gateway.networking.k8s.io/v1
    kind: Gateway
    metadata:
      name: gateway
      namespace: istio-ingress
    spec:
      gatewayClassName: istio
      listeners:
      - name: default
        hostname: "*.example.com"
        port: 80
        protocol: HTTP
        allowedRoutes:
          namespaces:
            from: All
    ---
    apiVersion: gateway.networking.k8s.io/v1
    kind: HTTPRoute
    metadata:
      name: http
      namespace: default
    spec:
      parentRefs:
      - name: gateway
        namespace: istio-ingress
      hostnames: ["httpbin.example.com"]
      rules:
      - matches:
        - path:
            type: PathPrefix
            value: /get
        backendRefs:
        - name: httpbin
          port: 8000
    EOF
    {{< /text >}}

1.  Set the Ingress Host environment variable:

    {{< text bash >}}
    $ kubectl wait -n istio-ingress --for=condition=programmed gateways.gateway.networking.k8s.io gateway
    $ export INGRESS_HOST=$(kubectl get gateways.gateway.networking.k8s.io gateway -n istio-ingress -ojsonpath='{.status.addresses[0].value}')
    {{< /text >}}

1.  Access the `httpbin` service using _curl_:

    {{< text bash >}}
    $ curl -s -I -HHost:httpbin.example.com "http://$INGRESS_HOST/get"
    ...
    HTTP/1.1 200 OK
    ...
    server: istio-envoy
    ...
    {{< /text >}}

    Note the use of the `-H` flag to set the _Host_ HTTP header to
    "httpbin.example.com". This is needed because the `HTTPRoute` is configured to handle "httpbin.example.com",
    but in your test environment you have no DNS binding for that host and are simply sending your request to the ingress IP.

1.  Access any other URL that has not been explicitly exposed. You should see an HTTP 404 error:

    {{< text bash >}}
    $ curl -s -I -HHost:httpbin.example.com "http://$INGRESS_HOST/headers"
    HTTP/1.1 404 Not Found
    ...
    {{< /text >}}

1.  Update the route rule to also expose `/headers` and to add a header to the request:

    {{< text bash >}}
    $ kubectl apply -f - <<EOF
    apiVersion: gateway.networking.k8s.io/v1
    kind: HTTPRoute
    metadata:
      name: http
      namespace: default
    spec:
      parentRefs:
      - name: gateway
        namespace: istio-ingress
      hostnames: ["httpbin.example.com"]
      rules:
      - matches:
        - path:
            type: PathPrefix
            value: /get
        - path:
            type: PathPrefix
            value: /headers
        filters:
        - type: RequestHeaderModifier
          requestHeaderModifier:
            add:
            - name: my-added-header
              value: added-value
        backendRefs:
        - name: httpbin
          port: 8000
    EOF
    {{< /text >}}

1.  Access `/headers` again and notice header `My-Added-Header` has been added to the request:

    {{< text bash >}}
    $ curl -s -HHost:httpbin.example.com "http://$INGRESS_HOST/headers" | jq '.headers["My-Added-Header"][0]'
    ...
    "added-value"
    ...
    {{< /text >}}

## Deployment methods

In the example above, you did not need to install an ingress gateway `Deployment` prior to configuring a Gateway.
In the default configuration, a gateway `Deployment` and `Service` is automatically provisioned based on the `Gateway` configuration.
For advanced use cases, manual deployment is still allowed.

### Automated deployment

By default, each `Gateway` will automatically provision a `Service` and `Deployment`.
These will be named `<Gateway name>-<GatewayClass name>` (with the exception of the `istio-waypoint` `GatewayClass`, which does not append a suffix).
These configurations will be updated automatically if the `Gateway` changes (for example, if a new port is added).

These resources can be customized by using the `infrastructure` field:

{{< text yaml >}}
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: gateway
spec:
  infrastructure:
    annotations:
      some-key: some-value
    labels:
      key: value
    parametersRef:
      group: ""
      kind: ConfigMap
      name: gw-options
  gatewayClassName: istio
{{< /text >}}

Key-value pairs under `labels` and `annotations` will be copied onto the generated resources.
The `parametersRef` can be used to fully customize the generated resources.
This must reference a `ConfigMap` in the same namespace as the `Gateway`.

An example configuration:

{{< text yaml >}}
apiVersion: v1
kind: ConfigMap
metadata:
  name: gw-options
data:
  horizontalPodAutoscaler: |
    spec:
      minReplicas: 2
      maxReplicas: 2

  deployment: |
    metadata:
      annotations:
        additional-annotation: some-value
    spec:
      replicas: 4
      template:
        spec:
          containers:
          - name: istio-proxy
            resources:
              requests:
                cpu: 1234m

  service: |
    spec:
      ports:
      - "\$patch": delete
        port: 15021
{{< /text >}}

These configurations will be overlaid on top of the generated resources using a [Strategic Merge Patch](https://github.com/kubernetes/community/blob/master/contributors/devel/sig-api-machinery/strategic-merge-patch.md) strategy.
The following keys are valid:
* `service`
* `deployment`
* `serviceAccount`
* `horizontalPodAutoscaler`
* `podDisruptionBudget`

{{< tip >}}
A `HorizontalPodAutoscaler` and `PodDisruptionBudget` are not created by default.
However, if the corresponding field is present in the customization, they will be created.
{{< /tip >}}

#### GatewayClass defaults

Defaults for all `Gateway`s can be configured for each `GatewayClass`.
This is done by a `ConfigMap` with the label `gateway.istio.io/defaults-for-class: <gateway class name>`.
This `ConfigMap` must be in the [root namespace](/docs/reference/config/istio.mesh.v1alpha1/#MeshConfig-root_namespace) (typically, `istio-system`).
Only one `ConfigMap` per `GatewayClass` is allowed.
This `ConfigMap` takes the same format as the `ConfigMap` for a `Gateway`.

Customization may be present on both a `GatewayClass` and a `Gateway`.
If both are present, the `Gateway` customization applies after the `GatewayClass` customization.

This `ConfigMap` can also be created at installation time. For example:

{{< text yaml >}}
kind: IstioOperator
spec:
  values:
    gatewayClasses:
      istio:
        deployment:
          spec:
            replicas: 2
{{< /text >}}

#### Resource attachment and scaling

Resources can be *attached* to a `Gateway` to customize it.
However, most Kubernetes resources do not currently support attaching directly to a `Gateway`, but they can be attached to the corresponding generated `Deployment` and `Service` instead.
This is easily done because [the resources are generated with well-known labels](https://gateway-api.sigs.k8s.io/geps/gep-1762/#resource-attachment) (`gateway.networking.k8s.io/gateway-name: <gateway name>`) and names:

* Gateway: `<gateway name>-<gateway class name>`
* Waypoint: `<gateway name>`

For example, to deploy a `Gateway` with a `HorizontalPodAutoscaler` and `PodDisruptionBudget`:

{{< text yaml >}}
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: gateway
spec:
  gatewayClassName: istio
  listeners:
  - name: default
    hostname: "*.example.com"
    port: 80
    protocol: HTTP
    allowedRoutes:
      namespaces:
        from: All
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: gateway
spec:
  # Match the generated Deployment by reference
  # Note: Do not use `kind: Gateway`.
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: gateway-istio
  minReplicas: 2
  maxReplicas: 5
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 50
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: gateway
spec:
  minAvailable: 1
  selector:
    # Match the generated Deployment by label
    matchLabels:
      gateway.networking.k8s.io/gateway-name: gateway
{{< /text >}}

### Manual deployment

If you do not want to have an automated deployment, a `Deployment` and `Service` can be [configured manually](/docs/setup/additional-setup/gateway/).

When this option is done, you will need to manually link the `Gateway` to the `Service`, as well as keep their port configuration in sync.

In order to support Policy Attachment, e.g. when you're using the [`targetRef`](/docs/reference/config/type/workload-selector/#PolicyTargetReference) field on an AuthorizationPolicy, you will also need to reference the name of your `Gateway` by adding the following label to your gateway pod: `gateway.networking.k8s.io/gateway-name: <gateway name>`.

To link a `Gateway` to a `Service`, configure the `addresses` field to point to a **single** `Hostname`.

{{< tip >}}
Istio's controller will not configure the `Service` if it is in a different namespace to the `Gateway`.
{{< /tip >}}

{{< text yaml >}}
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: gateway
spec:
  addresses:
  - value: ingress.istio-gateways.svc.cluster.local
    type: Hostname
...
{{< /text >}}

## Mesh Traffic

The Gateway API can also be used to configure mesh traffic.
This is done by configuring the `parentRef` to point to a service, instead of a gateway.

For example, to add a header on all calls to an in-cluster `Service` named `example`:

{{< text yaml >}}
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: mesh
spec:
  parentRefs:
  - group: ""
    kind: Service
    name: example
  rules:
  - filters:
    - type: RequestHeaderModifier
      requestHeaderModifier:
        add:
        - name: my-added-header
          value: added-value
    backendRefs:
    - name: example
      port: 80
{{< /text >}}

More details and examples can be found in other [traffic management tasks](/docs/tasks/traffic-management/).

## Cleanup

1. Remove the `httpbin` sample and gateway:

    {{< text bash >}}
    $ kubectl delete -f @samples/httpbin/httpbin.yaml@
    $ kubectl delete httproute http
    $ kubectl delete gateways.gateway.networking.k8s.io gateway -n istio-ingress
    $ kubectl delete ns istio-ingress
    {{< /text >}}

1. Uninstall Istio:

    {{< text bash >}}
    $ istioctl uninstall -y --purge
    $ kubectl delete ns istio-system
    {{< /text >}}

1. Remove the Gateway API CRDs if they are no longer needed:

    {{< text bash >}}
    $ kubectl kustomize "github.com/kubernetes-sigs/gateway-api/config/crd?ref={{< k8s_gateway_api_version >}}" | kubectl delete -f -
    {{< /text >}}

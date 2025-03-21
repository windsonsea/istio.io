---
title: Accessing External Services
description: Describes how to configure Istio to route traffic from services in the mesh to external services.
weight: 10
aliases:
    - /docs/tasks/egress.html
    - /docs/tasks/egress
keywords: [traffic-management,egress]
owner: istio/wg-networking-maintainers
test: yes
---

Because all outbound traffic from an Istio-enabled pod is redirected to its sidecar proxy by default,
accessibility of URLs outside of the cluster depends on the configuration of the proxy.
By default, Istio configures the Envoy proxy to pass through requests for unknown services.
Although this provides a convenient way to get started with Istio, configuring
stricter control is usually preferable.

This task shows you how to access external services in three different ways:

1. Allow the Envoy proxy to pass requests through to services that are not configured inside the mesh.
1. Configure [service entries](/docs/reference/config/networking/service-entry/) to provide controlled access to external services.
1. Completely bypass the Envoy proxy for a specific range of IPs.

## Before you begin

*   Set up Istio by following the instructions in the [Installation guide](/docs/setup/).
    Use the `demo` [configuration profile](/docs/setup/additional-setup/config-profiles/) or otherwise
    [enable Envoy’s access logging](/docs/tasks/observability/logs/access-log/#enable-envoy-s-access-logging).

*   Deploy the [curl]({{< github_tree >}}/samples/curl) sample app to use as a test source for sending requests.
    If you have
    [automatic sidecar injection](/docs/setup/additional-setup/sidecar-injection/#automatic-sidecar-injection)
    enabled, run the following command to deploy the sample app:

    {{< text bash >}}
    $ kubectl apply -f @samples/curl/curl.yaml@
    {{< /text >}}

    Otherwise, manually inject the sidecar before deploying the `curl` application with the following command:

    {{< text bash >}}
    $ kubectl apply -f <(istioctl kube-inject -f @samples/curl/curl.yaml@)
    {{< /text >}}

    {{< tip >}}
    You can use any pod with `curl` installed as a test source.
    {{< /tip >}}

*   Set the `SOURCE_POD` environment variable to the name of your source pod:

    {{< text bash >}}
    $ export SOURCE_POD=$(kubectl get pod -l app=curl -o jsonpath='{.items..metadata.name}')
    {{< /text >}}

## Envoy passthrough to external services

Istio has an [installation option](/docs/reference/config/istio.mesh.v1alpha1/#MeshConfig-OutboundTrafficPolicy-Mode),
`meshConfig.outboundTrafficPolicy.mode`, that configures the sidecar handling
of external services, that is, those services that are not defined in Istio's internal service registry.
If this option is set to `ALLOW_ANY`, the Istio proxy lets calls to unknown services pass through.
If the option is set to `REGISTRY_ONLY`, then the Istio proxy blocks any host without an HTTP service or
service entry defined within the mesh.
`ALLOW_ANY` is the default value, allowing you to start evaluating Istio quickly,
without controlling access to external services.
You can then decide to [configure access to external services](#controlled-access-to-external-services) later.

1.  To see this approach in action you need to ensure that your Istio installation is configured
    with the `meshConfig.outboundTrafficPolicy.mode` option set to `ALLOW_ANY`. Unless you explicitly
    set it to `REGISTRY_ONLY` mode when you installed Istio, it is probably enabled by default.

    If you are unsure, you can run the following command to display your mesh config:

    {{< text bash >}}
    $ kubectl get configmap istio -n istio-system -o yaml
    {{< /text >}}

    Unless you see an explicit setting of `meshConfig.outboundTrafficPolicy.mode` with value `REGISTRY_ONLY`,
    you can be sure the option is set to `ALLOW_ANY`, which is the only other possible value and the default.

    {{< tip >}}
    If you have explicitly configured `REGISTRY_ONLY` mode, you can change it
    by rerunning your original `istioctl install` command with the changed setting, for example:

    {{< text syntax=bash snip_id=none >}}
    $ istioctl install <flags-you-used-to-install-Istio> --set meshConfig.outboundTrafficPolicy.mode=ALLOW_ANY
    {{< /text >}}

    {{< /tip >}}

1.  Make a couple of requests to external HTTPS services from the `SOURCE_POD` to confirm
    successful `200` responses:

    {{< text bash >}}
    $ kubectl exec "$SOURCE_POD" -c curl -- curl -sSI https://www.google.com | grep  "HTTP/"; kubectl exec "$SOURCE_POD" -c curl -- curl -sI https://edition.cnn.com | grep "HTTP/"
    HTTP/2 200
    HTTP/2 200
    {{< /text >}}

Congratulations! You successfully sent egress traffic from your mesh.

This simple approach to access external services, has the drawback that you lose Istio monitoring and control
for traffic to external services. The next section shows you how to monitor and control your mesh's access to
external services.

## Controlled access to external services

Using Istio `ServiceEntry` configurations, you can access any publicly accessible service
from within your Istio cluster. This section shows you how to configure access to an external HTTP service,
[httpbin.org](http://httpbin.org), as well as an external HTTPS service,
[www.google.com](https://www.google.com) without losing Istio's traffic monitoring and control features.

### Change to the blocking-by-default policy

To demonstrate the controlled way of enabling access to external services, you need to change the
`meshConfig.outboundTrafficPolicy.mode` option from the `ALLOW_ANY` mode to the `REGISTRY_ONLY` mode.

{{< tip >}}
You can add controlled access to services that are already accessible in `ALLOW_ANY` mode.
This way, you can start using Istio features on some external services without blocking any others.
Once you've configured all of your services, you can then switch the mode to `REGISTRY_ONLY` to block
any other unintentional accesses.
{{< /tip >}}

1.  Change the `meshConfig.outboundTrafficPolicy.mode` option to `REGISTRY_ONLY`.

    If you used an `IstioOperator` configuration to install Istio, add the following field to your configuration:

    {{< text yaml >}}
    spec:
      meshConfig:
        outboundTrafficPolicy:
          mode: REGISTRY_ONLY
    {{< /text >}}

    Otherwise, add the equivalent setting to your original `istioctl install` command, for example:

    {{< text syntax=bash snip_id=none >}}
    $ istioctl install <flags-you-used-to-install-Istio> \
                       --set meshConfig.outboundTrafficPolicy.mode=REGISTRY_ONLY
    {{< /text >}}

1.  Make a couple of requests to external HTTPS services from `SOURCE_POD` to verify that they are now blocked:

    {{< text bash >}}
    $ kubectl exec "$SOURCE_POD" -c curl -- curl -sI https://www.google.com | grep  "HTTP/"; kubectl exec "$SOURCE_POD" -c curl -- curl -sI https://edition.cnn.com | grep "HTTP/"
    command terminated with exit code 35
    command terminated with exit code 35
    {{< /text >}}

    {{< warning >}}
    It may take a while for the configuration change to propagate, so you might still get successful connections.
    Wait for several seconds and then retry the last command.
    {{< /warning >}}

### Access an external HTTP service

1.  Create a `ServiceEntry` to allow access to an external HTTP service.

    {{< warning >}}
    `DNS` resolution is used in the service entry below as a security measure. Setting the resolution to `NONE`
    opens a possibility for attack. A malicious client could pretend that it's
    accessing `httpbin.org` by setting it in the `HOST` header, while really connecting to a different IP
    (that is not associated with `httpbin.org`). The Istio sidecar proxy will trust the HOST header, and incorrectly allow
    the traffic, even though it is being delivered to the IP address of a different host. That host can be a malicious
    site, or a legitimate site, prohibited by the mesh security policies.

    With `DNS` resolution, the sidecar proxy will ignore the original destination IP address and direct the traffic
    to `httpbin.org`, performing a DNS query to get an IP address of `httpbin.org`.
    {{< /warning >}}

    {{< text bash >}}
    $ kubectl apply -f - <<EOF
    apiVersion: networking.istio.io/v1
    kind: ServiceEntry
    metadata:
      name: httpbin-ext
    spec:
      hosts:
      - httpbin.org
      ports:
      - number: 80
        name: http
        protocol: HTTP
      resolution: DNS
      location: MESH_EXTERNAL
    EOF
    {{< /text >}}

1.  Make a request to the external HTTP service from `SOURCE_POD`:

    {{< text bash >}}
    $ kubectl exec "$SOURCE_POD" -c curl -- curl -sS http://httpbin.org/headers
    {
      "headers": {
        "Accept": "*/*",
        "Host": "httpbin.org",
        ...
        "X-Envoy-Decorator-Operation": "httpbin.org:80/*",
        ...
      }
    }
    {{< /text >}}

    Note the headers added by the Istio sidecar proxy: `X-Envoy-Decorator-Operation`.

1.  Check the log of the sidecar proxy of `SOURCE_POD`:

    {{< text bash >}}
    $ kubectl logs "$SOURCE_POD" -c istio-proxy | tail
    [2019-01-24T12:17:11.640Z] "GET /headers HTTP/1.1" 200 - 0 599 214 214 "-" "curl/7.60.0" "17fde8f7-fa62-9b39-8999-302324e6def2" "httpbin.org" "35.173.6.94:80" outbound|80||httpbin.org - 35.173.6.94:80 172.30.109.82:55314 -
    {{< /text >}}

    Note the entry related to your HTTP request to `httpbin.org/headers`.

### Access an external HTTPS service

1.  Create a `ServiceEntry` to allow access to an external HTTPS service.

    {{< text bash >}}
    $ kubectl apply -f - <<EOF
    apiVersion: networking.istio.io/v1
    kind: ServiceEntry
    metadata:
      name: google
    spec:
      hosts:
      - www.google.com
      ports:
      - number: 443
        name: https
        protocol: HTTPS
      resolution: DNS
      location: MESH_EXTERNAL
    EOF
    {{< /text >}}

1.  Make a request to the external HTTPS service from `SOURCE_POD`:

    {{< text bash >}}
    $ kubectl exec "$SOURCE_POD" -c curl -- curl -sSI https://www.google.com | grep  "HTTP/"
    HTTP/2 200
    {{< /text >}}

1.  Check the log of the sidecar proxy of `SOURCE_POD`:

    {{< text bash >}}
    $ kubectl logs "$SOURCE_POD" -c istio-proxy | tail
    [2019-01-24T12:48:54.977Z] "- - -" 0 - 601 17766 1289 - "-" "-" "-" "-" "172.217.161.36:443" outbound|443||www.google.com 172.30.109.82:59480 172.217.161.36:443 172.30.109.82:59478 www.google.com
    {{< /text >}}

    Note the entry related to your HTTPS request to `www.google.com`.

### Manage traffic to external services

Similar to inter-cluster requests, routing rules
can also be configured for external services that are accessed using `ServiceEntry` configurations.
In this example, you set a timeout rule on calls to the `httpbin.org` service.

{{< boilerplate gateway-api-support >}}

1)  From inside the pod being used as the test source, make a _curl_ request to the `/delay` endpoint of the
    httpbin.org external service:

    {{< text bash >}}
    $ kubectl exec "$SOURCE_POD" -c curl -- time curl -o /dev/null -sS -w "%{http_code}\n" http://httpbin.org/delay/5
    200
    real    0m5.024s
    user    0m0.003s
    sys     0m0.003s
    {{< /text >}}

    The request should return 200 (OK) in approximately 5 seconds.

2)  Use `kubectl` to set a 3s timeout on calls to the `httpbin.org` external service:

{{< tabset category-name="config-api" >}}

{{< tab name="Istio APIs" category-value="istio-apis" >}}

{{< text bash >}}
$ kubectl apply -f - <<EOF
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: httpbin-ext
spec:
  hosts:
  - httpbin.org
  http:
  - timeout: 3s
    route:
    - destination:
        host: httpbin.org
      weight: 100
EOF
{{< /text >}}

{{< /tab >}}

{{< tab name="Gateway API" category-value="gateway-api" >}}

{{< text bash >}}
$ kubectl apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: httpbin-ext
spec:
  parentRefs:
  - kind: ServiceEntry
    group: networking.istio.io
    name: httpbin-ext
  hostnames:
  - httpbin.org
  rules:
  - timeouts:
      request: 3s
    backendRefs:
    - kind: Hostname
      group: networking.istio.io
      name: httpbin.org
      port: 80
EOF
{{< /text >}}

{{< /tab >}}

{{< /tabset >}}

3)  Wait a few seconds, then make the _curl_ request again:

    {{< text bash >}}
    $ kubectl exec "$SOURCE_POD" -c curl -- time curl -o /dev/null -sS -w "%{http_code}\n" http://httpbin.org/delay/5
    504
    real    0m3.149s
    user    0m0.004s
    sys     0m0.004s
    {{< /text >}}

    This time a 504 (Gateway Timeout) appears after 3 seconds.
    Although httpbin.org was waiting 5 seconds, Istio cut off the request at 3 seconds.

### Cleanup the controlled access to external services

{{< tabset category-name="config-api" >}}

{{< tab name="Istio APIs" category-value="istio-apis" >}}

{{< text bash >}}
$ kubectl delete serviceentry httpbin-ext google
$ kubectl delete virtualservice httpbin-ext --ignore-not-found=true
{{< /text >}}

{{< /tab >}}

{{< tab name="Gateway API" category-value="gateway-api" >}}

{{< text bash >}}
$ kubectl delete serviceentry httpbin-ext
$ kubectl delete httproute httpbin-ext --ignore-not-found=true
{{< /text >}}

{{< /tab >}}

{{< /tabset >}}

## Direct access to external services

If you want to completely bypass Istio for a specific IP range,
you can configure the Envoy sidecars to prevent them from
[intercepting](/docs/concepts/traffic-management/)
external requests. To set up the bypass, change either the `global.proxy.includeIPRanges`
or the `global.proxy.excludeIPRanges` [configuration option](https://archive.istio.io/v1.4/docs/reference/config/installation-options/) and
update the `istio-sidecar-injector` configuration map using the `kubectl apply` command. This can also
be configured on a pod by setting corresponding [annotations](/docs/reference/config/annotations/) such as
`traffic.sidecar.istio.io/includeOutboundIPRanges`.
After updating the `istio-sidecar-injector` configuration, it affects all
future application pod deployments.

{{< warning >}}
Unlike [Envoy passthrough to external services](/docs/tasks/traffic-management/egress/egress-control/#envoy-passthrough-to-external-services),
which uses the `ALLOW_ANY` traffic policy to instruct the Istio sidecar proxy to
passthrough calls to unknown services,
this approach completely bypasses the sidecar, essentially disabling all of Istio's features
for the specified IPs. You cannot incrementally add service entries for specific
destinations, as you can with the `ALLOW_ANY` approach.
Therefore, this configuration approach is only recommended as a last resort
when, for performance or other reasons, external access cannot be configured using the sidecar.
{{< /warning >}}

A simple way to exclude all external IPs from being redirected to the sidecar proxy is
to set the `global.proxy.includeIPRanges` configuration option to the IP range or ranges
used for internal cluster services.
These IP range values depend on the platform where your cluster runs.

### Determine the internal IP ranges for your platform

Set the value of `values.global.proxy.includeIPRanges` according to your cluster provider.

#### IBM Cloud Private

1.  Get your `service_cluster_ip_range` from IBM Cloud Private configuration file under `cluster/config.yaml`:

    {{< text bash >}}
    $ grep service_cluster_ip_range cluster/config.yaml
    {{< /text >}}

    The following is a sample output:

    {{< text plain >}}
    service_cluster_ip_range: 10.0.0.1/24
    {{< /text >}}

1.  Use `--set values.global.proxy.includeIPRanges="10.0.0.1/24"`

#### IBM Cloud Kubernetes Service

To see which CIDR is used in the cluster use `ibmcloud ks cluster get -c <CLUSTER-NAME>` and look for the `Service Subnet`:

{{< text bash >}}
$ ibmcloud ks cluster get -c my-cluster | grep "Service Subnet"
Service Subnet:                 172.21.0.0/16
{{< /text >}}

Then use `--set values.global.proxy.includeIPRanges="172.21.0.0/16"`

{{< warning >}}
On very old clusters, this may not work so you can use `--set values.global.proxy.includeIPRanges="172.30.0.0/16,172.21.0.0/16,10.10.10.0/24"` or use `kubectl get svc -o wide -A` to further narrow down the CIDR value for the setting.
{{< /warning >}}

#### Google Kubernetes Engine (GKE)

The ranges are not fixed, so you will need to run the `gcloud container clusters describe` command to determine the
ranges to use. For example:

{{< text bash >}}
$ gcloud container clusters describe XXXXXXX --zone=XXXXXX | grep -e clusterIpv4Cidr -e servicesIpv4Cidr
clusterIpv4Cidr: 10.4.0.0/14
servicesIpv4Cidr: 10.7.240.0/20
{{< /text >}}

Use `--set values.global.proxy.includeIPRanges="10.4.0.0/14\,10.7.240.0/20"`

#### Azure Kubernetes Service (AKS)

##### Kubenet

To see which service CIDR and pod CIDR are used in the cluster, use `az aks show` and look for the `serviceCidr`:

{{< text bash >}}
$ az aks show --resource-group "${RESOURCE_GROUP}" --name "${CLUSTER}" | grep Cidr
    "podCidr": "10.244.0.0/16",
    "podCidrs": [
    "serviceCidr": "10.0.0.0/16",
    "serviceCidrs": [
{{< /text >}}

Then use `--set values.global.proxy.includeIPRanges="10.244.0.0/16\,10.0.0.0/16"`

##### Azure CNI

Follow these steps if you are using Azure CNI with a non-overlay networking mode. If using Azure CNI with overlay networking, please follow the [Kubenet instructions](#kubenet). For more information, see the [Azure CNI Overlay documentation](https://learn.microsoft.com/en-us/azure/aks/azure-cni-overlay).

To see which service CIDR is used in the cluster, use `az aks show` and look for the `serviceCidr`:

{{< text bash >}}
$ az aks show --resource-group "${RESOURCE_GROUP}" --name "${CLUSTER}" | grep serviceCidr
    "serviceCidr": "10.0.0.0/16",
    "serviceCidrs": [
{{< /text >}}

To see which pod CIDR is used in the cluster, use `az` CLI to inspect the `vnet`:

{{< text bash >}}
$ az aks show --resource-group "${RESOURCE_GROUP}" --name "${CLUSTER}" | grep nodeResourceGroup
  "nodeResourceGroup": "MC_user-rg_user-cluster_region",
  "nodeResourceGroupProfile": null,
$ az network vnet list -g MC_user-rg_user-cluster_region | grep name
    "name": "aks-vnet-74242220",
        "name": "aks-subnet",
$ az network vnet show -g MC_user-rg_user-cluster_region -n aks-vnet-74242220 | grep addressPrefix
    "addressPrefixes": [
      "addressPrefix": "10.224.0.0/16",
{{< /text >}}

Then use `--set values.global.proxy.includeIPRanges="10.244.0.0/16\,10.0.0.0/16"`

#### Minikube, Docker For Desktop, Bare Metal

The default value is `10.96.0.0/12`, but it's not fixed. Use the following command to determine your actual value:

{{< text bash >}}
$ kubectl describe pod kube-apiserver -n kube-system | grep 'service-cluster-ip-range'
      --service-cluster-ip-range=10.96.0.0/12
{{< /text >}}

Use `--set values.global.proxy.includeIPRanges="10.96.0.0/12"`

### Configuring the proxy bypass

{{< warning >}}
Remove the service entry and virtual service previously deployed in this guide.
{{< /warning >}}

Update your `istio-sidecar-injector` configuration map using the IP ranges specific to your platform.
For example, if the range is 10.0.0.1&#47;24, use the following command:

{{< text syntax=bash snip_id=none >}}
$ istioctl install <flags-you-used-to-install-Istio> --set values.global.proxy.includeIPRanges="10.0.0.1/24"
{{< /text >}}

Use the same command that you used to [install Istio](/docs/setup/install/istioctl) and
add `--set values.global.proxy.includeIPRanges="10.0.0.1/24"`.

### Access the external services

Because the bypass configuration only affects new deployments, you need to terminate and then redeploy the `curl`
application as described in the [Before you begin](#before-you-begin) section.

After updating the `istio-sidecar-injector` configmap and redeploying the `curl` application,
the Istio sidecar will only intercept and manage internal requests
within the cluster. Any external request bypasses the sidecar and goes straight to its intended destination.
For example:

{{< text bash >}}
$ kubectl exec "$SOURCE_POD" -c curl -- curl -sS http://httpbin.org/headers
{
  "headers": {
    "Accept": "*/*",
    "Host": "httpbin.org",
    ...
  }
}
{{< /text >}}

Unlike accessing external services through HTTP or HTTPS, you don't see any headers related to the Istio sidecar and the
requests sent to external services do not appear in the log of the sidecar. Bypassing the Istio sidecars means you can
no longer monitor the access to external services.

### Cleanup the direct access to external services

Update the configuration to stop bypassing sidecar proxies for a range of IPs:

{{< text syntax=bash snip_id=none >}}
$ istioctl install <flags-you-used-to-install-Istio>
{{< /text >}}

## Understanding what happened

In this task you looked at three ways to call external services from an Istio mesh:

1. Configuring Envoy to allow access to any external service.

1. Use a service entry to register an accessible external service inside the mesh. This is the
   recommended approach.

1. Configuring the Istio sidecar to exclude external IPs from its remapped IP table.

The first approach directs traffic through the Istio sidecar proxy, including calls to services
that are unknown inside the mesh. When using this approach,
you can't monitor access to external services or take advantage of Istio's traffic control features for them.
To easily switch to the second approach for specific services, simply create service entries for those external services.
This process allows you to initially access any external service and then later
decide whether or not to control access, enable traffic monitoring, and use traffic control features as needed.

The second approach lets you use all of the same Istio service mesh features for calls to services inside or
outside of the cluster. In this task, you learned how to monitor access to external services and set a timeout
rule for calls to an external service.

The third approach bypasses the Istio sidecar proxy, giving your services direct access to any external server.
However, configuring the proxy this way does require cluster-provider specific knowledge and configuration.
Similar to the first approach, you also lose monitoring of access to external services and you can't apply
Istio features on traffic to external services.

## Security note

{{< warning >}}
Note that configuration examples in this task **do not enable secure egress traffic control** in Istio.
A malicious application can bypass the Istio sidecar proxy and access any external service without Istio control.
{{< /warning >}}

To implement egress traffic control in a more secure way, you must
[direct egress traffic through an egress gateway](/docs/tasks/traffic-management/egress/egress-gateway/)
and review the security concerns described in the
[additional security considerations](/docs/tasks/traffic-management/egress/egress-gateway/#additional-security-considerations)
section.

## Cleanup

Shutdown the [curl]({{< github_tree >}}/samples/curl) service:

{{< text bash >}}
$ kubectl delete -f @samples/curl/curl.yaml@
{{< /text >}}

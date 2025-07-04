#!/usr/bin/env bash
# shellcheck disable=SC2155,SC2030,SC2031

# Copyright Istio Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# _set_kube_vars initializes the following variables based on the value of KUBECONFIG:
#
# KUBECONFIG_FILES: an array containing the individual files in the order specified.
# KUBE_CONTEXTS: the names of the kube contexts, in the order of the KUBECONFIG files specified.
function _set_kube_vars()
{
  # Split out the kube config files and then get the current context in
  # each. We do this because the contexts are stored in a map, which
  # means that order of the context returned by
  # `kubectl config get-contexts` is not guaranteed. By pulling out
  # the context on a per-file basis, we maintain the order of the
  # files in the KUBECONFIG variable.
  KUBE_CONTEXTS=()
  IFS=':' read -r -a KUBECONFIG_FILES <<< "${KUBECONFIG}"
  for KUBECONFIG_FILE in "${KUBECONFIG_FILES[@]}"; do
    CTX="$(export KUBECONFIG=$KUBECONFIG_FILE; kubectl config current-context)"
    if [[ -z "${CTX}" ]]; then
      echo "${KUBECONFIG_FILE} contains no current context"
      exit 1
    fi
    KUBE_CONTEXTS+=("${CTX}")
  done

  export KUBECONFIG_FILES
  export KUBE_CONTEXTS

  echo "KUBECONFIG=${KUBECONFIG}"
  echo "KUBECONFIG_FILES=${KUBECONFIG_FILES[*]}"
  echo "KUBE_CONTEXTS=${KUBE_CONTEXTS[*]}"
}

# Set the INGRESS_HOST, INGRESS_PORT, SECURE_INGRESS_PORT, and TCP_INGRESS_PORT environment variables
_set_ingress_environment_variables() {
    # check for external load balancer
    local extlb=$(kubectl get svc istio-ingressgateway -n istio-system)
    if [[ "$extlb" != *"<none>"* && "$extlb" != *"<pending>"* ]]; then
        # external load balancer
        export INGRESS_HOST=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
        export INGRESS_PORT=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="http2")].port}')
        export SECURE_INGRESS_PORT=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="https")].port}')
        export TCP_INGRESS_PORT=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="tcp")].port}')
    else
        # node port
        export INGRESS_HOST=$(kubectl get po -l istio=ingressgateway -n istio-system -o jsonpath='{.items[0].status.hostIP}')
        export INGRESS_PORT=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="http2")].nodePort}')
        export SECURE_INGRESS_PORT=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="https")].nodePort}')
        export TCP_INGRESS_PORT=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="tcp")].nodePort}')
    fi
}

# TODO: should we have functions for these?
#   kubectl wait --for=condition=available deployment --all --timeout=60s
#   kubectl wait --for=condition=Ready pod --all --timeout=60s

# Wait for rollout of named deployment
# usage: _wait_for_deployment <namespace> <deployment name> <optional: context>
_wait_for_deployment() {
    local namespace="$1"
    local name="$2"
    local context="${3:-}"
    if ! kubectl --context="$context" -n "$namespace" rollout status deployment "$name" --timeout 5m; then
        echo "Failed rollout of deployment $name in namespace $namespace"
        exit 1
    fi
}

# Wait for rollout of named daemonset
# usage: _wait_for_daemonset <namespace> <daemonset name> <optional: context>
_wait_for_daemonset() {
    local namespace="$1"
    local name="$2"
    local context="${3:-}"
    if ! kubectl --context="$context" -n "$namespace" rollout status daemonset "$name" --timeout 5m; then
        echo "Failed rollout of daemonset $name in namespace $namespace"
        exit 1
    fi
}

# Wait for rollout of named statefulset
# usage: _wait_for_statefulset <namespace> <statefulset name> <optional: context>
_wait_for_statefulset() {
    local namespace="$1"
    local name="$2"
    local context="${3:-}"
    if ! kubectl --context="$context" -n "$namespace" rollout status statefulset "$name" --timeout 5m; then
        echo "Failed rollout of statefulset $name in namespace $namespace"
        exit 1
    fi
}

# Wait for resource to be created
# usage: _wait_for_resource <kind> <namespace> <name>
_wait_for_resource() {
    local kind="$1"
    local namespace="$2"
    local name="$3"
    local start_time=$(date +%s)
    if ! kubectl wait --for=create -n "$namespace" "$kind/$name" --timeout 30s; then
        local end_time=$(date +%s)
        echo "Timed out waiting for $kind $name in namespace $namespace to be created."
        echo "Duration: $(( end_time - start_time )) seconds"
        return 1
    fi
    sleep 2s
}

# Wait for named Gateway API gateway to be ready
# usage: _wait_for_gateway <namespace> <gateway name> <optional: context>
_wait_for_gateway() {
    local namespace="$1"
    local name="$2"
    local context="${3:-}"
    if ! kubectl --context="$context" -n "$namespace" wait --for=condition=programmed gtw "$name" --timeout=2m; then
        echo "Failed to deploy gateway $name in namespace $namespace"
        exit 1
    fi
}

# Encode the string to a URL
_urlencode() {
    python3 -c "import urllib.parse; print(urllib.parse.quote('''$1'''))"
}

# Invokes bash make to rewrite a snippet to avoid installing from a real helm repository, and instead uses
# local files
# usage: _rewrite_helm_repo <commands>
# shellcheck disable=SC2001
_rewrite_helm_repo() {
  # get function definition: https://stackoverflow.com/a/6916952/374797
  cmd="$(type "${1:?snip}" | sed '1,3d;$d')"
  cmd="$(echo "${cmd}" | sed 's|istio/base|manifests/charts/base|')"
  cmd="$(echo "${cmd}" | sed 's|istio/istiod|manifests/charts/istio-control/istio-discovery|')"
  cmd="$(echo "${cmd}" | sed 's|istio/cni|manifests/charts/istio-cni|')"
  cmd="$(echo "${cmd}" | sed 's|istio/ztunnel|manifests/charts/ztunnel|')"
  cmd="$(echo "${cmd}" | sed 's|istio/gateway|manifests/charts/gateway|')"
  cmd="$(echo "${cmd}" | sed 's|istio/ambient|manifests/sample-charts/ambient|')"
  cmd="$(echo "${cmd}" | sed -E "s|(helm[[:space:]]+[^[:space:]]+)|\1 --set global.tag=${ISTIO_IMAGE_VERSION=SHOULD_BE_SET}.${ISTIO_LONG_SHA=latest}|g")"
  # Since we are using local charts here, we may need to manually rebundle the updates
  # This is not required if installing directly from a real Helm repo
  if [[ $cmd =~ "manifests/sample-charts/ambient" ]]; then
    pushd manifests/sample-charts/ambient && helm dep update
    popd || exit
  fi

  eval "${cmd}"
}

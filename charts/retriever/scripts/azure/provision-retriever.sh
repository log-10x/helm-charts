#!/usr/bin/env bash
#
# Copyright (c) 2025-2026 Log10x, Inc.
# SPDX-License-Identifier: Apache-2.0
#
# Provision the Azure resources the Log10x retriever needs, and emit the helm
# values file that installs against them.
#
# What it creates, in order:
#   resource group
#   StorageV2 account, flat namespace, TLS 1.2 minimum
#   two blob containers, one for source logs and one for the index
#   four Storage Queues, index / query / subquery / stream
#   user-assigned managed identity
#   Storage Blob Data Contributor and Storage Queue Data Contributor on the
#     account, granted to that identity
#   Event Grid system topic on the account, and a BlobCreated subscription that
#     delivers to the index queue, filtered to the input container
#   AKS with the OIDC issuer and workload identity enabled, or verification that
#     an existing cluster has both
#   federated credential binding the identity to the release service account
#
# Re-running against an existing resource group converges. Every step checks for
# what it is about to create and skips it when it is already there.
#
# No credential is written to the values file and none is printed. Pods
# authenticate through workload identity, which carries no secret.

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"

###############################################################################
# defaults
###############################################################################

RESOURCE_GROUP=""
LOCATION=""
ACCOUNT=""
AKS_NAME=""
CREATE_AKS="false"
NAMESPACE=""
RELEASE=""
VALUES_OUT=""
INPUT_CONTAINER="logs"
INDEX_CONTAINER="tenx-index"
INDEX_PATH="tenx"
QUEUE_PREFIX="tenx"
IMAGE_TAG=""
DESTROY="false"

# AKS node pool for a cluster this script creates. Two nodes carry the
# all-in-one retriever and leave headroom for the workload identity webhook.
# AKS_NODE_SIZE is empty by default so the cluster takes the CLI's own default
# size. Subscriptions differ in which sizes they allow, and a hard coded size
# that the subscription refuses fails the whole run.
AKS_NODE_COUNT="${AKS_NODE_COUNT:-2}"
AKS_NODE_SIZE="${AKS_NODE_SIZE:-}"

# Name of the federated credential on the managed identity.
FEDERATED_CREDENTIAL_NAME="retriever-sa"

###############################################################################
# output
###############################################################################

log()  { printf '%s\n' "==> $*" >&2; }
step() { printf '%s\n' "    $*" >&2; }
die()  { printf '%s\n' "$SCRIPT_NAME: $*" >&2; exit 1; }

usage() {
  cat >&2 <<USAGE
usage:
  $SCRIPT_NAME --resource-group RG --location LOC --account NAME
               [--create-aks NAME | --aks NAME]
               --namespace NS --release NAME --values-out FILE
               [--input-container logs] [--index-container tenx-index]
               [--index-path tenx] [--queue-prefix tenx] [--image-tag TAG]

  $SCRIPT_NAME --destroy --resource-group RG

options:
  --resource-group RG     resource group to create or converge
  --location LOC          Azure region, for example eastus
  --account NAME          storage account name, 3 to 24 lower case letters and digits
  --create-aks NAME       create an AKS cluster with workload identity enabled
  --aks NAME              use an existing AKS cluster, verified to have OIDC
                          issuer and workload identity enabled
  --namespace NS          Kubernetes namespace the release installs into
  --release NAME          helm release name, also the fullnameOverride and the
                          service account name the federated credential binds to
  --values-out FILE       path to write the helm values file to
  --input-container NAME  blob container holding source logs, default logs
  --index-container NAME  blob container holding the index, default tenx-index
  --index-path PATH       prefix inside the index container, default tenx
  --queue-prefix PREFIX   Storage Queue name prefix, default tenx
  --image-tag TAG         pin image.tag in the values file
  --destroy               delete the resource group and everything in it
  -h, --help              this message

environment:
  AKS_NODE_COUNT          node count for a created cluster, default 2
  AKS_NODE_SIZE           node size for a created cluster, default is whatever
                          the Azure CLI picks. Set it when the subscription
                          refuses that size.
USAGE
}

###############################################################################
# argument parsing
###############################################################################

while [ $# -gt 0 ]; do
  case "$1" in
    --resource-group)  RESOURCE_GROUP="${2:-}"; shift 2 ;;
    --location)        LOCATION="${2:-}"; shift 2 ;;
    --account)         ACCOUNT="${2:-}"; shift 2 ;;
    --create-aks)      AKS_NAME="${2:-}"; CREATE_AKS="true"; shift 2 ;;
    --aks)             AKS_NAME="${2:-}"; CREATE_AKS="false"; shift 2 ;;
    --namespace)       NAMESPACE="${2:-}"; shift 2 ;;
    --release)         RELEASE="${2:-}"; shift 2 ;;
    --values-out)      VALUES_OUT="${2:-}"; shift 2 ;;
    --input-container) INPUT_CONTAINER="${2:-}"; shift 2 ;;
    --index-container) INDEX_CONTAINER="${2:-}"; shift 2 ;;
    --index-path)      INDEX_PATH="${2:-}"; shift 2 ;;
    --queue-prefix)    QUEUE_PREFIX="${2:-}"; shift 2 ;;
    --image-tag)       IMAGE_TAG="${2:-}"; shift 2 ;;
    --destroy)         DESTROY="true"; shift ;;
    -h|--help)         usage; exit 0 ;;
    *)                 usage; die "unknown argument '$1'" ;;
  esac
done

###############################################################################
# preflight
###############################################################################

require_tool() {
  command -v "$1" >/dev/null 2>&1 || die "$1 is not on PATH. $2"
}

require_tool az "Install the Azure CLI: https://learn.microsoft.com/cli/azure/install-azure-cli"
az account show -o none 2>/dev/null || die "the Azure CLI is not signed in. Run 'az login' and 'az account set --subscription <id>'."

if [ "$DESTROY" = "true" ]; then
  [ -n "$RESOURCE_GROUP" ] || { usage; die "--destroy needs --resource-group"; }
  if ! az group show -n "$RESOURCE_GROUP" -o none 2>/dev/null; then
    log "resource group $RESOURCE_GROUP does not exist, nothing to destroy"
    exit 0
  fi
  log "deleting resource group $RESOURCE_GROUP and everything in it"
  az group delete -n "$RESOURCE_GROUP" --yes -o none
  log "resource group $RESOURCE_GROUP deleted"
  exit 0
fi

require_tool kubectl "Install kubectl: https://kubernetes.io/docs/tasks/tools/"
require_tool helm "Install helm: https://helm.sh/docs/intro/install/"

[ -n "$RESOURCE_GROUP" ] || { usage; die "--resource-group is required"; }
[ -n "$LOCATION" ]       || { usage; die "--location is required"; }
[ -n "$ACCOUNT" ]        || { usage; die "--account is required"; }
[ -n "$AKS_NAME" ]       || { usage; die "one of --create-aks or --aks is required"; }
[ -n "$NAMESPACE" ]      || { usage; die "--namespace is required"; }
[ -n "$RELEASE" ]        || { usage; die "--release is required"; }
[ -n "$VALUES_OUT" ]     || { usage; die "--values-out is required"; }

case "$ACCOUNT" in
  *[!a-z0-9]*) die "--account '$ACCOUNT' is not a valid storage account name. Use 3 to 24 lower case letters and digits." ;;
esac
if [ "${#ACCOUNT}" -lt 3 ] || [ "${#ACCOUNT}" -gt 24 ]; then
  die "--account '$ACCOUNT' is ${#ACCOUNT} characters. Use 3 to 24."
fi

VALUES_DIR="$(cd "$(dirname "$VALUES_OUT")" 2>/dev/null && pwd)" \
  || die "the directory for --values-out '$VALUES_OUT' does not exist"
VALUES_OUT="$VALUES_DIR/$(basename "$VALUES_OUT")"

QUEUE_INDEX="${QUEUE_PREFIX}-index"
QUEUE_QUERY="${QUEUE_PREFIX}-query"
QUEUE_SUBQUERY="${QUEUE_PREFIX}-subquery"
QUEUE_STREAM="${QUEUE_PREFIX}-stream"

IDENTITY_NAME="${RELEASE}-identity"
SYSTEM_TOPIC="${ACCOUNT}-blob"
EVENT_SUBSCRIPTION="blob-created-to-index"
KUBECONFIG_OUT="${VALUES_DIR}/${AKS_NAME}.kubeconfig"

###############################################################################
# helpers
###############################################################################

# Wait for a command to succeed, for the cases where Azure returns before the
# object it just created is readable everywhere. Entra propagation of a new
# managed identity principal is the one that bites.
retry() {
  local attempts="$1" delay="$2"; shift 2
  local n=1
  until "$@"; do
    if [ "$n" -ge "$attempts" ]; then
      return 1
    fi
    n=$((n + 1))
    sleep "$delay"
  done
  return 0
}

ensure_role_assignment() {
  local role="$1" principal="$2" scope="$3" existing

  existing="$(az role assignment list \
    --assignee-object-id "$principal" \
    --scope "$scope" \
    --role "$role" \
    --query "length(@)" -o tsv 2>/dev/null || echo 0)"

  if [ "${existing:-0}" != "0" ]; then
    step "role '$role' already assigned"
    return 0
  fi

  step "granting '$role' on the storage account"
  retry 12 10 az role assignment create \
    --assignee-object-id "$principal" \
    --assignee-principal-type ServicePrincipal \
    --role "$role" \
    --scope "$scope" \
    -o none \
    || die "could not assign '$role'. The signed in identity needs Owner or User Access Administrator on $scope."
}

###############################################################################
# subscription and providers
###############################################################################

SUBSCRIPTION_ID="$(az account show --query id -o tsv)"
TENANT_ID="$(az account show --query tenantId -o tsv)"
log "subscription $SUBSCRIPTION_ID"

for provider in Microsoft.Storage Microsoft.EventGrid Microsoft.ManagedIdentity Microsoft.ContainerService; do
  state="$(az provider show -n "$provider" --query registrationState -o tsv 2>/dev/null || echo "NotRegistered")"
  if [ "$state" != "Registered" ]; then
    log "registering resource provider $provider"
    az provider register -n "$provider" --wait -o none
  fi
done

###############################################################################
# resource group
###############################################################################

if az group show -n "$RESOURCE_GROUP" -o none 2>/dev/null; then
  log "resource group $RESOURCE_GROUP is already there"
else
  log "creating resource group $RESOURCE_GROUP in $LOCATION"
  az group create -n "$RESOURCE_GROUP" -l "$LOCATION" -o none
fi

###############################################################################
# storage account
###############################################################################

if az storage account show -n "$ACCOUNT" -g "$RESOURCE_GROUP" -o none 2>/dev/null; then
  log "storage account $ACCOUNT is already there"
else
  log "creating storage account $ACCOUNT"
  az storage account create \
    -n "$ACCOUNT" \
    -g "$RESOURCE_GROUP" \
    -l "$LOCATION" \
    --sku Standard_LRS \
    --kind StorageV2 \
    --hns false \
    --min-tls-version TLS1_2 \
    --allow-blob-public-access false \
    -o none
fi

# A hierarchical namespace account reorders listings, and the engine refuses one
# at construction. Fail here rather than at the first query.
HNS_ENABLED="$(az storage account show -n "$ACCOUNT" -g "$RESOURCE_GROUP" \
  --query "isHnsEnabled" -o tsv)"
if [ "$HNS_ENABLED" = "true" ]; then
  die "storage account $ACCOUNT has a hierarchical namespace. The retriever needs a flat namespace account."
fi

ACCOUNT_ID="$(az storage account show -n "$ACCOUNT" -g "$RESOURCE_GROUP" --query id -o tsv)"

# The Event Grid system topic has to sit in the account's region, which is not
# necessarily the --location given when the account already existed.
ACCOUNT_LOCATION="$(az storage account show -n "$ACCOUNT" -g "$RESOURCE_GROUP" \
  --query location -o tsv)"

# The data plane calls below run with the account key rather than the signed in
# user, so the script does not depend on the operator holding Storage Blob Data
# Contributor, and does not wait on RBAC propagation. The key is held in a
# variable, never written to a file and never printed.
ACCOUNT_KEY="$(az storage account keys list -n "$ACCOUNT" -g "$RESOURCE_GROUP" \
  --query "[0].value" -o tsv)"

for container in "$INPUT_CONTAINER" "$INDEX_CONTAINER"; do
  exists="$(az storage container exists \
    --account-name "$ACCOUNT" --account-key "$ACCOUNT_KEY" \
    -n "$container" --query exists -o tsv)"
  if [ "$exists" = "true" ]; then
    step "container $container is already there"
  else
    step "creating container $container"
    az storage container create \
      --account-name "$ACCOUNT" --account-key "$ACCOUNT_KEY" \
      -n "$container" -o none
  fi
done

for queue in "$QUEUE_INDEX" "$QUEUE_QUERY" "$QUEUE_SUBQUERY" "$QUEUE_STREAM"; do
  exists="$(az storage queue exists \
    --account-name "$ACCOUNT" --account-key "$ACCOUNT_KEY" \
    -n "$queue" --query exists -o tsv)"
  if [ "$exists" = "true" ]; then
    step "queue $queue is already there"
  else
    step "creating queue $queue"
    az storage queue create \
      --account-name "$ACCOUNT" --account-key "$ACCOUNT_KEY" \
      -n "$queue" -o none
  fi
done

###############################################################################
# managed identity and roles
###############################################################################

if az identity show -n "$IDENTITY_NAME" -g "$RESOURCE_GROUP" -o none 2>/dev/null; then
  log "managed identity $IDENTITY_NAME is already there"
else
  log "creating managed identity $IDENTITY_NAME"
  az identity create -n "$IDENTITY_NAME" -g "$RESOURCE_GROUP" -l "$LOCATION" -o none
fi

IDENTITY_CLIENT_ID="$(az identity show -n "$IDENTITY_NAME" -g "$RESOURCE_GROUP" --query clientId -o tsv)"
IDENTITY_PRINCIPAL_ID="$(az identity show -n "$IDENTITY_NAME" -g "$RESOURCE_GROUP" --query principalId -o tsv)"

ensure_role_assignment "Storage Blob Data Contributor"  "$IDENTITY_PRINCIPAL_ID" "$ACCOUNT_ID"
ensure_role_assignment "Storage Queue Data Contributor" "$IDENTITY_PRINCIPAL_ID" "$ACCOUNT_ID"

###############################################################################
# Event Grid, blob created to the index queue
###############################################################################

if az eventgrid system-topic show -n "$SYSTEM_TOPIC" -g "$RESOURCE_GROUP" -o none 2>/dev/null; then
  log "Event Grid system topic $SYSTEM_TOPIC is already there"
else
  log "creating Event Grid system topic $SYSTEM_TOPIC"
  az eventgrid system-topic create \
    -n "$SYSTEM_TOPIC" \
    -g "$RESOURCE_GROUP" \
    -l "$ACCOUNT_LOCATION" \
    --source "$ACCOUNT_ID" \
    --topic-type Microsoft.Storage.StorageAccounts \
    -o none
fi

if az eventgrid system-topic event-subscription show \
     -n "$EVENT_SUBSCRIPTION" -g "$RESOURCE_GROUP" \
     --system-topic-name "$SYSTEM_TOPIC" -o none 2>/dev/null; then
  log "event subscription $EVENT_SUBSCRIPTION is already there"
else
  log "subscribing BlobCreated on $INPUT_CONTAINER to queue $QUEUE_INDEX"
  az eventgrid system-topic event-subscription create \
    -n "$EVENT_SUBSCRIPTION" \
    -g "$RESOURCE_GROUP" \
    --system-topic-name "$SYSTEM_TOPIC" \
    --endpoint-type storagequeue \
    --endpoint "${ACCOUNT_ID}/queueservices/default/queues/${QUEUE_INDEX}" \
    --included-event-types Microsoft.Storage.BlobCreated \
    --subject-begins-with "/blobServices/default/containers/${INPUT_CONTAINER}/" \
    -o none
fi

###############################################################################
# AKS
###############################################################################

if az aks show -n "$AKS_NAME" -g "$RESOURCE_GROUP" -o none 2>/dev/null; then
  log "AKS cluster $AKS_NAME is already there"
elif [ "$CREATE_AKS" = "true" ]; then
  log "creating AKS cluster $AKS_NAME, this takes several minutes"
  AKS_CREATE_ARGS=(
    -n "$AKS_NAME"
    -g "$RESOURCE_GROUP"
    -l "$LOCATION"
    --node-count "$AKS_NODE_COUNT"
    --enable-oidc-issuer
    --enable-workload-identity
    --no-ssh-key
    -o none
  )
  if [ -n "$AKS_NODE_SIZE" ]; then
    AKS_CREATE_ARGS+=(--node-vm-size "$AKS_NODE_SIZE")
  fi
  az aks create "${AKS_CREATE_ARGS[@]}"
else
  die "AKS cluster $AKS_NAME was not found in $RESOURCE_GROUP. Pass --create-aks $AKS_NAME to create it."
fi

OIDC_ENABLED="$(az aks show -n "$AKS_NAME" -g "$RESOURCE_GROUP" \
  --query "oidcIssuerProfile.enabled" -o tsv)"
WI_ENABLED="$(az aks show -n "$AKS_NAME" -g "$RESOURCE_GROUP" \
  --query "securityProfile.workloadIdentity.enabled" -o tsv 2>/dev/null || echo "")"

if [ "$OIDC_ENABLED" != "true" ] || [ "$WI_ENABLED" != "true" ]; then
  die "AKS cluster $AKS_NAME does not have both the OIDC issuer and workload identity enabled. Enable them with:
  az aks update -n $AKS_NAME -g $RESOURCE_GROUP --enable-oidc-issuer --enable-workload-identity"
fi

AKS_OIDC_ISSUER="$(az aks show -n "$AKS_NAME" -g "$RESOURCE_GROUP" \
  --query "oidcIssuerProfile.issuerURL" -o tsv)"

log "writing kubeconfig to $KUBECONFIG_OUT"
az aks get-credentials \
  -n "$AKS_NAME" -g "$RESOURCE_GROUP" \
  --file "$KUBECONFIG_OUT" \
  --overwrite-existing \
  -o none

if ! kubectl --kubeconfig "$KUBECONFIG_OUT" get nodes -o name >/dev/null 2>&1; then
  log "warning: kubectl could not reach $AKS_NAME with $KUBECONFIG_OUT yet. The cluster may still be settling."
fi

###############################################################################
# federated credential
###############################################################################

FEDERATED_SUBJECT="system:serviceaccount:${NAMESPACE}:${RELEASE}"

if az identity federated-credential show \
     -n "$FEDERATED_CREDENTIAL_NAME" \
     --identity-name "$IDENTITY_NAME" \
     -g "$RESOURCE_GROUP" -o none 2>/dev/null; then
  CURRENT_SUBJECT="$(az identity federated-credential show \
    -n "$FEDERATED_CREDENTIAL_NAME" \
    --identity-name "$IDENTITY_NAME" \
    -g "$RESOURCE_GROUP" --query subject -o tsv)"
  if [ "$CURRENT_SUBJECT" = "$FEDERATED_SUBJECT" ]; then
    log "federated credential $FEDERATED_CREDENTIAL_NAME already binds $FEDERATED_SUBJECT"
  else
    log "repointing federated credential $FEDERATED_CREDENTIAL_NAME at $FEDERATED_SUBJECT"
    az identity federated-credential update \
      -n "$FEDERATED_CREDENTIAL_NAME" \
      --identity-name "$IDENTITY_NAME" \
      -g "$RESOURCE_GROUP" \
      --issuer "$AKS_OIDC_ISSUER" \
      --subject "$FEDERATED_SUBJECT" \
      --audiences api://AzureADTokenExchange \
      -o none
  fi
else
  log "creating federated credential $FEDERATED_CREDENTIAL_NAME for $FEDERATED_SUBJECT"
  az identity federated-credential create \
    -n "$FEDERATED_CREDENTIAL_NAME" \
    --identity-name "$IDENTITY_NAME" \
    -g "$RESOURCE_GROUP" \
    --issuer "$AKS_OIDC_ISSUER" \
    --subject "$FEDERATED_SUBJECT" \
    --audiences api://AzureADTokenExchange \
    -o none
fi

###############################################################################
# values file
###############################################################################

log "writing $VALUES_OUT"

{
  cat <<VALUES
# Log10x retriever, Azure Blob Storage.
# Written by $SCRIPT_NAME. Edit freely, re-running the script rewrites it.
#
# resource group  $RESOURCE_GROUP
# storage account $ACCOUNT
# AKS cluster     $AKS_NAME
#
# The Log10x license key is deliberately absent. Pass it at install time:
#   --set-string log10xApiKey="\$LOG10X_API_KEY"

fullnameOverride: "$RELEASE"
VALUES

  if [ -n "$IMAGE_TAG" ]; then
    cat <<VALUES

image:
  tag: "$IMAGE_TAG"
VALUES
  fi

  cat <<VALUES

storage:
  provider: azure
  azure:
    account: "$ACCOUNT"
    indexContainer: "$ACCOUNT/$INDEX_CONTAINER/$INDEX_PATH"
    inputContainer: "$INPUT_CONTAINER"
    invoke: queue

    queues:
      index: "$QUEUE_INDEX"
      query: "$QUEUE_QUERY"
      subquery: "$QUEUE_SUBQUERY"
      stream: "$QUEUE_STREAM"

    auth:
      # Workload identity carries no secret. The webhook injects the token from
      # the federated credential bound to $FEDERATED_SUBJECT.
      method: workloadIdentity
      clientId: "$IDENTITY_CLIENT_ID"
      tenantId: "$TENANT_ID"

scheduledQueries:
  enabled: false
VALUES
} > "$VALUES_OUT"

###############################################################################
# what to run next
###############################################################################

QUERY_BODY='{"name":"first","from":"now(\"-1h\")","to":"now()","search":"severity_level==\"ERROR\"","writeResults":true}'

cat >&2 <<NEXT

Provisioned. Two commands follow.

1. Install the chart. Set LOG10X_API_KEY first, the key is not in the values file.

export KUBECONFIG=$KUBECONFIG_OUT
helm install $RELEASE log10x/retriever-10x \\
  --namespace $NAMESPACE \\
  --create-namespace \\
  -f $VALUES_OUT \\
  --set-string log10xApiKey="\$LOG10X_API_KEY"

2. Upload a log to the $INPUT_CONTAINER container, wait for the index to be
   written, then put a query on the $QUEUE_QUERY queue. Results land as JSONL
   under $INDEX_CONTAINER/$INDEX_PATH/<app>/qr/<queryId>/.

az storage message put \\
  --account-name $ACCOUNT \\
  --queue-name $QUEUE_QUERY \\
  --account-key "\$(az storage account keys list -n $ACCOUNT -g $RESOURCE_GROUP --query '[0].value' -o tsv)" \\
  --content '$QUERY_BODY' \\
  -o none

Tear everything down with:
  $SCRIPT_NAME --destroy --resource-group $RESOURCE_GROUP
NEXT

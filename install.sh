#!/bin/bash

# Optional: Set Git credentials for private repositories
REPO_USER=$GITHUB_USER
REPO_PASSWORD=$GITHUB_PAT
REPO_URL=$GITHUB_URL

SSO_CLIENT_SECRET=$GITHUB_CLIENT_SECRET

if [[ $# -eq 0 ]]; then
    echo 'Please provide an environment parameter (e.g., dev, stage, prod)'
    exit 1
fi

ENV=$1
GITHUB_ACCOUNT=${2:-"argo-universe"} # Set default value "main" if second argument is not provided

# Set environment variable
export ENV=$ENV

# Create Kubernetes namespaces for ArgoCD and Ingress
kubectl create ns argocd

# --------------------------------------------------------------------------------------------
# Install ArgoCD
# --------------------------------------------------------------------------------------------
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update argo
helm upgrade --install argocd argo/argo-cd -n argocd --version 5.34.5

# Wait for the Deployment to be ready
echo "Waiting for Deployment to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd

# To use private Git Repositories, add a Secret with the Git credentials
# and the `argocd.argoproj.io/secret-type` label.
if [[ ! -z "$REPO_USER" && ! -z "$REPO_PASSWORD" && ! -z "$REPO_URL" ]]; then
    kubectl create secret generic git-repo-creds -n argocd \
    --from-literal=password="$REPO_PASSWORD" \
    --from-literal=url="$REPO_URL" \
    --from-literal=username="$REPO_USER"

    kubectl label secret git-repo-creds -n argocd "argocd.argoproj.io/secret-type=repository"
fi

if [[ ! -z "$SSO_CLIENT_SECRET" ]]; then 
     kubectl create secret generic github-sso-client-secret \
     --from-literal="dex.github.clientSecret"=$GITHUB_CLIENT_SECRET \
     -n argocd

    kubectl label secret github-sso-client-secret -n argocd "app.kubernetes.io/part-of=argocd"

fi




# --------------------------------------------------------------------------------------------
# Install BigBang application using the Helm chart from the local repository
# --------------------------------------------------------------------------------------------
helm upgrade --install bigbang-app bigbang/bigbang-app -n argocd \
    --set env="$ENV" \
    --set gitHubAccount="$GITHUB_ACCOUNT"

# Echo Argocd admin password
ArgoCDAdminPassword=$(kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | base64 -d)
echo "ArgoCD admin password is $ArgoCDAdminPassword"

 if [ "$ENV" = "dev" ]; then
  echo "Port forwarding ArgoCD server..."
  kubectl port-forward svc/argocd-server -n argocd 8080:443 &
  # Replace `kubectl port-forward` command with the appropriate command for your environment
  # This assumes you have kubectl installed and configured properly
  
  echo "Port forwarding started. Access ArgoCD at https://localhost:8080"
else
  echo "ENV variable is not set to 'dev'. No port forwarding needed."
fi

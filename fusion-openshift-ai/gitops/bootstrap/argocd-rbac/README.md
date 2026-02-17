# ArgoCD RBAC Setup

This directory contains the necessary RBAC permissions for ArgoCD to manage cluster-scoped resources.

## Purpose

ArgoCD needs explicit permissions to create and manage:
- ServiceAccounts
- ClusterRoles
- ClusterRoleBindings

These permissions are required for the RHOAI installation to create the necessary RBAC resources for health check jobs and other cluster operations.

## Resources

- **argocd-rbac-permissions.yaml**: Grants ArgoCD application controller the ability to create and manage RBAC resources

## Deployment Order

This is deployed via the `argocd-rbac-setup-app` with sync-wave `-10`, ensuring it runs before the main RHOAI installation (sync-wave `1`).

## How It Works

1. The bootstrap parent app deploys `argocd-rbac-setup-app` first (wave -10)
2. This grants ArgoCD the necessary RBAC permissions
3. The `rhoai-install` app (wave 1) can then successfully create:
   - `patch-argocd-sa` ServiceAccount
   - `patch-argocd-clusterrole` ClusterRole
   - `patch-argocd-clusterrolebinding` ClusterRoleBinding
4. The patch job can execute with proper permissions to configure ArgoCD health checks
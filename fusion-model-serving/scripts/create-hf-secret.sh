#!/bin/bash

# ============================================================================
# HuggingFace Token Secret Creation Script
# ============================================================================
# This script creates a Kubernetes secret containing your HuggingFace token
# for accessing gated models like Meta Llama.
#
# Usage:
#   ./scripts/create-hf-secret.sh <namespace> <hf-token>
#
# Example:
#   ./scripts/create-hf-secret.sh model-serving hf_xxxxxxxxxxxxxxxxxxxxx
#
# Prerequisites:
# - oc CLI installed and authenticated
# - HuggingFace token from https://huggingface.co/settings/tokens
# - Model license accepted on HuggingFace (e.g., https://huggingface.co/meta-llama/Meta-Llama-3-70B)
# ============================================================================

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_header() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║     HuggingFace Token Secret Creation                      ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
}

# Check if required arguments are provided
if [ $# -lt 2 ]; then
    print_header
    print_error "Missing required arguments"
    echo ""
    echo "Usage: $0 <namespace> <hf-token>"
    echo ""
    echo "Arguments:"
    echo "  namespace  - Target namespace for the secret"
    echo "  hf-token   - Your HuggingFace token (starts with 'hf_')"
    echo ""
    echo "Example:"
    echo "  $0 model-serving hf_xxxxxxxxxxxxxxxxxxxxx"
    echo ""
    echo "Get your HuggingFace token from:"
    echo "  https://huggingface.co/settings/tokens"
    echo ""
    exit 1
fi

NAMESPACE=$1
HF_TOKEN=$2
SECRET_NAME="hf-token-secret"

print_header

# Validate HuggingFace token format
if [[ ! $HF_TOKEN =~ ^hf_ ]]; then
    print_warning "Token doesn't start with 'hf_' - this may not be a valid HuggingFace token"
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Operation cancelled"
        exit 0
    fi
fi

# Check if oc CLI is available
if ! command -v oc &> /dev/null; then
    print_error "oc CLI not found. Please install OpenShift CLI."
    exit 1
fi

# Check if logged in to OpenShift
if ! oc whoami &> /dev/null; then
    print_error "Not logged in to OpenShift. Please run 'oc login' first."
    exit 1
fi

print_info "Configuration:"
echo "  Namespace:   $NAMESPACE"
echo "  Secret Name: $SECRET_NAME"
echo "  Token:       ${HF_TOKEN:0:10}..." # Show only first 10 chars
echo ""

# Create namespace if it doesn't exist
if ! oc get namespace "$NAMESPACE" &> /dev/null; then
    print_info "Creating namespace: $NAMESPACE"
    oc create namespace "$NAMESPACE"
    print_success "Namespace created"
else
    print_info "Namespace already exists: $NAMESPACE"
fi

# Check if secret already exists
if oc get secret "$SECRET_NAME" -n "$NAMESPACE" &> /dev/null; then
    print_warning "Secret '$SECRET_NAME' already exists in namespace '$NAMESPACE'"
    read -p "Do you want to replace it? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_info "Deleting existing secret..."
        oc delete secret "$SECRET_NAME" -n "$NAMESPACE"
        print_success "Existing secret deleted"
    else
        print_info "Operation cancelled"
        exit 0
    fi
fi

# Create the secret
print_info "Creating HuggingFace token secret..."
oc create secret generic "$SECRET_NAME" \
    --from-literal=token="$HF_TOKEN" \
    -n "$NAMESPACE"

if [ $? -eq 0 ]; then
    print_success "Secret created successfully!"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Next Steps:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "1. Uncomment the HF_TOKEN environment variable in:"
    echo "   fusion-model-serving/gitops/models/kserve-model-serving.yaml"
    echo ""
    echo "2. Deploy your gated model using the Llama example:"
    echo "   oc apply -f fusion-model-serving/gitops/llama-model-serving-application.yaml"
    echo ""
    echo "3. Verify the secret:"
    echo "   oc get secret $SECRET_NAME -n $NAMESPACE"
    echo ""
    echo "4. Monitor deployment:"
    echo "   oc get inferenceservice -n $NAMESPACE -w"
    echo ""
else
    print_error "Failed to create secret"
    exit 1
fi

# Made with Bob

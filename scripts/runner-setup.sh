#!/bin/bash
# Runner Setup Script
# This script creates secrets for GitHub and GitLab runners
#
# Usage:
#   ./scripts/runner-setup.sh [github|gitlab|all]
#   GITHUB_TOKEN=<token> GITLAB_TOKEN=<token> GITLAB_URL=<url> ./scripts/runner-setup.sh all

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

ACTION="${1:-all}"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}GitHub & GitLab Runner Setup${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check kubectl
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}Error: kubectl is not installed or not in PATH${NC}"
    exit 1
fi

# Create namespaces
echo -e "${YELLOW}Creating namespaces...${NC}"
kubectl create namespace managed-cicd --dry-run=client -o yaml | kubectl apply -f - > /dev/null
kubectl create namespace actions-runner-system --dry-run=client -o yaml | kubectl apply -f - > /dev/null
echo -e "${GREEN}✓ Namespaces created${NC}"
echo ""

# Function: Create GitHub secret
create_github_secret() {
    echo -e "${YELLOW}=== GitHub Runner Setup ===${NC}"
    
    # Get token from env or prompt
    if [ -z "$GITHUB_TOKEN" ]; then
        echo "For organization-level runners, you need:"
        echo "  - GitHub Personal Access Token (PAT) with 'repo' scope, OR"
        echo "  - GitHub App credentials"
        echo ""
        read -p "Do you have a GitHub PAT? (y/n): " -n 1 -r
        echo
        
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            read -sp "Enter GitHub Personal Access Token: " GITHUB_TOKEN
            echo ""
            
            if [ -z "$GITHUB_TOKEN" ]; then
                echo -e "${RED}Error: Token cannot be empty${NC}"
                exit 1
            fi
        else
            echo -e "${YELLOW}Skipping GitHub secret creation${NC}"
            return 0
        fi
    fi
    
    # Check if secret exists
    if kubectl get secret actions-runner-controller -n actions-runner-system &>/dev/null; then
        echo -e "${YELLOW}Secret already exists. Deleting...${NC}"
        kubectl delete secret actions-runner-controller -n actions-runner-system
    fi
    
    kubectl create secret generic actions-runner-controller \
        --from-literal=github_token="$GITHUB_TOKEN" \
        -n actions-runner-system > /dev/null
    
    echo -e "${GREEN}✓ GitHub secret created${NC}"
    echo ""
}

# Function: Create GitLab secret
create_gitlab_secret() {
    echo -e "${YELLOW}=== GitLab Runner Setup ===${NC}"
    
    # Get URL and token from env or prompt
    if [ -z "$GITLAB_URL" ] || [ -z "$GITLAB_TOKEN" ]; then
        echo "For group-level runner (RaaS group), you need:"
        echo "  - GitLab instance URL"
        echo "  - Group runner registration token"
        echo ""
        read -p "Enter GitLab instance URL (e.g., https://gitlab.com): " GITLAB_URL
        read -sp "Enter GitLab Group Runner Registration Token: " GITLAB_TOKEN
        echo ""
        
        if [ -z "$GITLAB_TOKEN" ]; then
            echo -e "${RED}Error: GitLab token cannot be empty${NC}"
            exit 1
        fi
    fi
    
    # Check if secret exists
    if kubectl get secret gitlab-runner-secret -n managed-cicd &>/dev/null; then
        echo -e "${YELLOW}Secret already exists. Deleting...${NC}"
        kubectl delete secret gitlab-runner-secret -n managed-cicd
    fi
    
    kubectl create secret generic gitlab-runner-secret \
        --from-literal=runner-registration-token="$GITLAB_TOKEN" \
        -n managed-cicd > /dev/null
    
    echo -e "${GREEN}✓ GitLab secret created${NC}"
    echo ""
}

# Main execution
case "$ACTION" in
    github)
        create_github_secret
        ;;
    gitlab)
        create_gitlab_secret
        ;;
    all)
        create_github_secret
        create_gitlab_secret
        echo -e "${GREEN}========================================${NC}"
        echo -e "${GREEN}Setup Complete!${NC}"
        echo -e "${GREEN}========================================${NC}"
        echo ""
        echo "Next steps:"
        echo "1. Update github-runner/base/runnerdeployment.yaml with your GitHub organization"
        echo "2. Update gitlab-runner/base/gitlab-runner-helmchart.yaml with GitLab URL: ${GITLAB_URL:-<set in .env>}"
        echo "3. Commit and push changes"
        echo ""
        echo "To verify secrets:"
        echo "  kubectl get secret actions-runner-controller -n actions-runner-system"
        echo "  kubectl get secret gitlab-runner-secret -n managed-cicd"
        ;;
    *)
        echo "Usage: $0 [github|gitlab|all]"
        echo ""
        echo "  github  - Create GitHub runner secret only"
        echo "  gitlab  - Create GitLab runner secret only"
        echo "  all     - Create both secrets (default)"
        echo ""
        echo "Environment variables:"
        echo "  GITHUB_TOKEN  - GitHub Personal Access Token"
        echo "  GITLAB_TOKEN  - GitLab runner registration token"
        echo "  GITLAB_URL    - GitLab instance URL"
        exit 1
        ;;
esac

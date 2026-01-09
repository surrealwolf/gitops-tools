#!/bin/bash
# Harbor Setup Script
# This script sets up Harbor registry: secrets, robot account, and proxy cache
#
# Usage:
#   ./scripts/harbor-setup.sh [secrets|robot|proxy|all]
#   ./scripts/harbor-setup.sh all  # Run all setup steps

set -e

# Load .env file if it exists
if [ -f .env ]; then
    echo "Loading configuration from .env file..."
    export $(grep -v '^#' .env | xargs)
fi

# Configuration
HARBOR_URL="${HARBOR_REGISTRY_URL:-${HARBOR_URL:-harbor.dataknife.net}}"
HARBOR_ADMIN_USER="${HARBOR_ADMIN_USER:-admin}"
HARBOR_ADMIN_PASSWORD="${HARBOR_ADMIN_PASSWORD:-Harbor12345}"
NAMESPACE="${HARBOR_NAMESPACE:-${NAMESPACE:-managed-tools}}"
HARBOR_API="https://${HARBOR_URL}/api/v2.0"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

ACTION="${1:-all}"

# Check dependencies
if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error: jq is required but not installed. Install with: sudo apt install jq${NC}"
    exit 1
fi

# Function: Create Harbor secrets
create_secrets() {
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Creating Harbor Secrets${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    
    kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f - > /dev/null
    
    # Get database password from env or prompt
    if [ -z "${HARBOR_DATABASE_PASSWORD}" ]; then
        read -sp "Enter database password (default: root123): " DB_PASSWORD
        DB_PASSWORD="${DB_PASSWORD:-root123}"
        echo ""
    else
        DB_PASSWORD="${HARBOR_DATABASE_PASSWORD}"
        echo "Using database password from .env"
    fi
    
    # Get Redis password from env or prompt
    if [ -z "${HARBOR_REDIS_PASSWORD}" ]; then
        read -sp "Enter Redis password (optional, press Enter for empty): " REDIS_PASSWORD
        REDIS_PASSWORD="${REDIS_PASSWORD:-}"
        echo ""
    else
        REDIS_PASSWORD="${HARBOR_REDIS_PASSWORD}"
        echo "Using Redis password from .env"
    fi
    
    # Create the secret
    kubectl create secret generic harbor-credentials \
      --from-literal=databasePassword="${DB_PASSWORD}" \
      --from-literal=redisPassword="${REDIS_PASSWORD}" \
      -n "${NAMESPACE}" \
      --dry-run=client -o yaml | kubectl apply -f -
    
    echo -e "${GREEN}✓ Harbor credentials secret created/updated${NC}"
    echo ""
    echo "⚠️  Note: Harbor admin password is NOT managed via this secret"
    echo "   Default password is 'Harbor12345' - change via Harbor UI after first login"
    echo ""
}

# Function: Authenticate with Harbor
authenticate() {
    AUTH_TEST=$(curl -s -k -u "${HARBOR_ADMIN_USER}:${HARBOR_ADMIN_PASSWORD}" \
      "${HARBOR_API}/users/current" | jq -r '.username // empty')
    
    if [ -z "$AUTH_TEST" ] || [ "$AUTH_TEST" != "admin" ]; then
        echo -e "${RED}Error: Failed to authenticate. Check your Harbor admin credentials.${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ Authenticated${NC}"
}

# Function: Create robot account
create_robot_account() {
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Creating Harbor Robot Account${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    
    authenticate
    
    ROBOT_NAME="${HARBOR_ROBOT_ACCOUNT_NAME:-${ROBOT_NAME:-ci-builder}}"
    PROJECT="${HARBOR_PROJECT:-${PROJECT:-library}}"
    ROBOT_DESCRIPTION="${ROBOT_DESCRIPTION:-Robot account for CI/CD builds}"
    
    echo "Configuration:"
    echo "  Harbor URL: ${HARBOR_URL}"
    echo "  Project: ${PROJECT}"
    echo "  Robot Name: ${ROBOT_NAME}"
    echo ""
    
    # Check if project exists, create if not
    PROJECT_EXISTS=$(curl -s -k -u "${HARBOR_ADMIN_USER}:${HARBOR_ADMIN_PASSWORD}" \
      -X GET "${HARBOR_API}/projects?name=${PROJECT}" \
      | jq -r ".[] | select(.name == \"${PROJECT}\") | .name")
    
    if [ -z "$PROJECT_EXISTS" ]; then
        echo "Creating project '${PROJECT}'..."
        curl -s -k -u "${HARBOR_ADMIN_USER}:${HARBOR_ADMIN_PASSWORD}" \
          -X POST "${HARBOR_API}/projects" \
          -H "Content-Type: application/json" \
          -d "{
            \"project_name\": \"${PROJECT}\",
            \"public\": false,
            \"metadata\": {
              \"public\": \"false\"
            }
          }" > /dev/null
        echo -e "${GREEN}✓ Project '${PROJECT}' created${NC}"
    else
        echo -e "${GREEN}✓ Project '${PROJECT}' exists${NC}"
    fi
    echo ""
    
    # Create robot account
    echo "Creating robot account '${ROBOT_NAME}'..."
    ROBOT_RESPONSE=$(curl -s -k -u "${HARBOR_ADMIN_USER}:${HARBOR_ADMIN_PASSWORD}" \
      -X POST "${HARBOR_API}/robots" \
      -H "Content-Type: application/json" \
      -d "{
        \"name\": \"${ROBOT_NAME}\",
        \"description\": \"${ROBOT_DESCRIPTION}\",
        \"level\": \"project\",
        \"duration\": -1,
        \"disable\": false,
        \"permissions\": [
          {
            \"kind\": \"project\",
            \"namespace\": \"${PROJECT}\",
            \"access\": [
              {
                \"resource\": \"repository\",
                \"action\": \"push\"
              },
              {
                \"resource\": \"repository\",
                \"action\": \"pull\"
              },
              {
                \"resource\": \"artifact\",
                \"action\": \"read\"
              },
              {
                \"resource\": \"artifact\",
                \"action\": \"create\"
              }
            ]
          }
        ]
      }")
    
    ROBOT_SECRET=$(echo "$ROBOT_RESPONSE" | jq -r '.secret // empty')
    ROBOT_FULL_NAME=$(echo "$ROBOT_RESPONSE" | jq -r '.name // empty')
    
    if [ -z "$ROBOT_SECRET" ] || [ "$ROBOT_SECRET" = "null" ]; then
        echo -e "${RED}Error: Failed to create robot account${NC}"
        echo "Response: $ROBOT_RESPONSE"
        exit 1
    fi
    
    echo -e "${GREEN}✓ Robot account created successfully${NC}"
    echo ""
    echo "Robot Account Details:"
    echo "  Full Name: ${ROBOT_FULL_NAME}"
    echo "  Secret: ${ROBOT_SECRET}"
    echo ""
    echo "Add these to your .env file:"
    echo "  HARBOR_ROBOT_ACCOUNT_NAME=${ROBOT_NAME}"
    echo "  HARBOR_ROBOT_ACCOUNT_SECRET=${ROBOT_SECRET}"
    echo "  HARBOR_ROBOT_ACCOUNT_FULL_NAME=${ROBOT_FULL_NAME}"
    echo ""
    echo -e "${YELLOW}⚠️  Save the robot secret now - it cannot be retrieved later!${NC}"
    echo ""
}

# Function: Create proxy cache project
create_proxy_cache() {
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Creating Harbor Proxy Cache Project${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    
    authenticate
    
    PROJECT_NAME="${DOCKERHUB_PROJECT:-dockerhub}"
    REGISTRY_NAME="${DOCKERHUB_REGISTRY_NAME:-DockerHub}"
    
    echo "Configuration:"
    echo "  Harbor URL: ${HARBOR_URL}"
    echo "  Project Name: ${PROJECT_NAME}"
    echo "  Registry Name: ${REGISTRY_NAME}"
    echo ""
    
    # Check if registry endpoint exists
    echo "Checking registry endpoint '${REGISTRY_NAME}'..."
    REGISTRY_ID=$(curl -s -k -u "${HARBOR_ADMIN_USER}:${HARBOR_ADMIN_PASSWORD}" \
      -X GET "${HARBOR_API}/registries" \
      | jq -r ".[] | select(.name == \"${REGISTRY_NAME}\") | .id // empty")
    
    if [ -z "$REGISTRY_ID" ]; then
        echo -e "${RED}Error: Registry endpoint '${REGISTRY_NAME}' not found.${NC}"
        echo "Please create the registry endpoint first in Harbor UI:"
        echo "  Administration → Registries → New Endpoint"
        exit 1
    fi
    echo -e "${GREEN}✓ Registry endpoint found (ID: ${REGISTRY_ID})${NC}"
    echo ""
    
    # Check if project already exists
    EXISTING_PROJECT=$(curl -s -k -u "${HARBOR_ADMIN_USER}:${HARBOR_ADMIN_PASSWORD}" \
      -X GET "${HARBOR_API}/projects?name=${PROJECT_NAME}" \
      | jq -r ".[] | select(.name == \"${PROJECT_NAME}\") | .project_id // empty")
    
    if [ -n "$EXISTING_PROJECT" ]; then
        EXISTING_REGISTRY_ID=$(curl -s -k -u "${HARBOR_ADMIN_USER}:${HARBOR_ADMIN_PASSWORD}" \
          -X GET "${HARBOR_API}/projects/${EXISTING_PROJECT}" \
          | jq -r '.registry_id // "null"')
        
        if [ "$EXISTING_REGISTRY_ID" = "$REGISTRY_ID" ]; then
            echo -e "${GREEN}✓ Project '${PROJECT_NAME}' already exists with proxy cache enabled${NC}"
            return 0
        else
            echo -e "${YELLOW}⚠️  Project '${PROJECT_NAME}' exists but proxy cache is not configured correctly${NC}"
            echo "According to Harbor documentation, proxy cache can only be enabled when creating a project."
            read -p "Delete and recreate project '${PROJECT_NAME}'? (yes/no): " -r
            if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
                echo "Aborted."
                exit 1
            fi
            
            echo "Deleting existing project..."
            curl -s -k -u "${HARBOR_ADMIN_USER}:${HARBOR_ADMIN_PASSWORD}" \
              -X DELETE "${HARBOR_API}/projects/${EXISTING_PROJECT}" > /dev/null
            echo -e "${GREEN}✓ Project deleted${NC}"
            sleep 2
        fi
    fi
    
    # Create project with proxy cache enabled
    echo "Creating proxy cache project '${PROJECT_NAME}'..."
    PROJECT_RESPONSE=$(curl -s -k -u "${HARBOR_ADMIN_USER}:${HARBOR_ADMIN_PASSWORD}" \
      -X POST "${HARBOR_API}/projects" \
      -H "Content-Type: application/json" \
      -d "{
        \"project_name\": \"${PROJECT_NAME}\",
        \"public\": true,
        \"registry_id\": ${REGISTRY_ID},
        \"metadata\": {
          \"public\": \"true\",
          \"enable_content_trust\": \"false\",
          \"prevent_vulnerable_images_from_running\": \"false\",
          \"prevent_vulnerable_images_from_running_severity\": \"\",
          \"automatically_scan_images_on_push\": \"false\"
        }
      }")
    
    # Check for errors
    if echo "$PROJECT_RESPONSE" | jq -e '.errors' >/dev/null 2>&1; then
        echo -e "${RED}Error: Failed to create project '${PROJECT_NAME}'${NC}"
        echo "Response: $PROJECT_RESPONSE"
        exit 1
    fi
    
    # Verify proxy cache is enabled
    sleep 2
    CREATED_PROJECT=$(curl -s -k -u "${HARBOR_ADMIN_USER}:${HARBOR_ADMIN_PASSWORD}" \
      -X GET "${HARBOR_API}/projects?name=${PROJECT_NAME}" \
      | jq -r ".[] | select(.name == \"${PROJECT_NAME}\")")
    
    PROJECT_REGISTRY_ID=$(echo "$CREATED_PROJECT" | jq -r '.registry_id // "null"')
    
    if [ "$PROJECT_REGISTRY_ID" = "$REGISTRY_ID" ]; then
        echo -e "${GREEN}✓ Proxy cache project '${PROJECT_NAME}' created successfully${NC}"
    else
        echo -e "${YELLOW}⚠️  Project created but proxy cache may not be enabled correctly${NC}"
    fi
    echo ""
}

# Main execution
case "$ACTION" in
    secrets)
        create_secrets
        ;;
    robot)
        create_robot_account
        ;;
    proxy)
        create_proxy_cache
        ;;
    all)
        create_secrets
        echo ""
        create_robot_account
        echo ""
        create_proxy_cache
        echo ""
        echo -e "${GREEN}========================================${NC}"
        echo -e "${GREEN}Harbor Setup Complete!${NC}"
        echo -e "${GREEN}========================================${NC}"
        ;;
    *)
        echo "Usage: $0 [secrets|robot|proxy|all]"
        echo ""
        echo "  secrets  - Create Harbor credentials secret"
        echo "  robot    - Create robot account for CI/CD"
        echo "  proxy    - Create DockerHub proxy cache project"
        echo "  all      - Run all setup steps (default)"
        exit 1
        ;;
esac

#!/bin/bash
# Transfer repositories to DataKnifeAI organization
# Usage: ./scripts/transfer-repos-to-dataknifeai.sh [repo-name] [repo-name2] ...
# Or run without args to see available repos

set -e

GITHUB_TOKEN="${GITHUB_TOKEN:-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}"
ORG_NAME="DataKnifeAI"
SOURCE_USER="surrealwolf"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Repository Transfer to DataKnifeAI${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if org exists
echo -e "${YELLOW}Checking if DataKnifeAI organization exists...${NC}"
ORG_CHECK=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  "https://api.github.com/orgs/$ORG_NAME" 2>&1)

if echo "$ORG_CHECK" | grep -q '"login"'; then
    echo -e "${GREEN}✓ DataKnifeAI organization exists${NC}"
else
    echo -e "${RED}✗ DataKnifeAI organization not found${NC}"
    echo "Please create it first at: https://github.com/organizations/new"
    exit 1
fi
echo ""

# List available repos
echo -e "${YELLOW}Fetching repositories from $SOURCE_USER...${NC}"
REPOS=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  "https://api.github.com/users/$SOURCE_USER/repos?per_page=100" | \
  grep -o '"name":"[^"]*"' | sed 's/"name":"//;s/"//')

if [ -z "$REPOS" ]; then
    echo -e "${RED}No repositories found${NC}"
    exit 1
fi

echo -e "${GREEN}Available repositories:${NC}"
echo "$REPOS" | nl
echo ""

# If repos provided as arguments, transfer them
if [ $# -gt 0 ]; then
    for REPO in "$@"; do
        echo -e "${YELLOW}Transferring $SOURCE_USER/$REPO to $ORG_NAME/$REPO...${NC}"
        
        RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
          -H "Authorization: token $GITHUB_TOKEN" \
          -H "Accept: application/vnd.github.v3+json" \
          -d "{\"new_owner\":\"$ORG_NAME\"}" \
          "https://api.github.com/repos/$SOURCE_USER/$REPO/transfer" 2>&1)
        
        HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
        BODY=$(echo "$RESPONSE" | sed '$d')
        
        if [ "$HTTP_CODE" = "202" ]; then
            echo -e "${GREEN}✓ Successfully transferred $REPO${NC}"
            echo "  New URL: https://github.com/$ORG_NAME/$REPO"
        elif echo "$BODY" | grep -q "already exists"; then
            echo -e "${YELLOW}⚠ Repository $REPO already exists in $ORG_NAME${NC}"
        else
            echo -e "${RED}✗ Failed to transfer $REPO${NC}"
            echo "  Response: $BODY"
        fi
        echo ""
        sleep 1
    done
else
    echo -e "${YELLOW}No repositories specified.${NC}"
    echo ""
    echo "Usage:"
    echo "  $0 <repo-name> [repo-name2] ..."
    echo ""
    echo "Example:"
    echo "  $0 gitops-tools"
    echo "  $0 gitops-tools repo1 repo2"
    echo ""
    echo "Or transfer via GitHub web UI:"
    echo "  1. Go to: https://github.com/$SOURCE_USER/<repo>/settings"
    echo "  2. Scroll to 'Danger Zone'"
    echo "  3. Click 'Transfer ownership'"
    echo "  4. Enter: $ORG_NAME"
    echo "  5. Confirm transfer"
fi

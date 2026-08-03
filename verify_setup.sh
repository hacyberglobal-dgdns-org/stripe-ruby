#!/bin/bash

# Stripe Webhook Setup Verification Script
# Quickly verifies all components are configured and working

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

CHECKS_PASSED=0
CHECKS_FAILED=0
CHECKS_WARNING=0

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Stripe Webhook Setup Verification${NC}"
echo -e "${BLUE}========================================${NC}\n"

# Function to print check results
check_pass() {
    echo -e "${GREEN}✓ PASS${NC}: $1"
    ((CHECKS_PASSED++))
}

check_fail() {
    echo -e "${RED}✗ FAIL${NC}: $1"
    ((CHECKS_FAILED++))
}

check_warn() {
    echo -e "${YELLOW}⚠ WARN${NC}: $1"
    ((CHECKS_WARNING++))
}

# 1. Check environment variables
echo -e "${BLUE}[1/10] Checking Environment Variables...${NC}"
if [ -f .env ]; then
    if grep -q "STRIPE_API_KEY" .env && grep -q "WEBHOOK_SECRET" .env; then
        check_pass "Environment variables configured (.env exists)"
    else
        check_fail "Environment variables incomplete (missing STRIPE_API_KEY or WEBHOOK_SECRET)"
    fi
else
    check_fail ".env file not found"
fi
echo ""

# 2. Check Docker installation
echo -e "${BLUE}[2/10] Checking Docker Installation...${NC}"
if command -v docker &> /dev/null; then
    DOCKER_VERSION=$(docker --version | awk '{print $3}' | sed 's/,//')
    check_pass "Docker installed ($DOCKER_VERSION)"
else
    check_fail "Docker not installed"
fi
echo ""

# 3. Check Docker Compose installation
echo -e "${BLUE}[3/10] Checking Docker Compose Installation...${NC}"
if command -v docker-compose &> /dev/null; then
    DC_VERSION=$(docker-compose --version | awk '{print $3}' | sed 's/,//')
    check_pass "Docker Compose installed ($DC_VERSION)"
else
    check_fail "Docker Compose not installed"
fi
echo ""

# 4. Check SSL certificates
echo -e "${BLUE}[4/10] Checking SSL Certificates...${NC}"
if [ -f ssl/certs/fullchain.pem ] && [ -f ssl/keys/privkey.pem ]; then
    CERT_EXPIRY=$(openssl x509 -in ssl/certs/fullchain.pem -noout -enddate 2>/dev/null | cut -d= -f2)
    check_pass "SSL certificates found (expires: $CERT_EXPIRY)"
else
    check_fail "SSL certificates not found in ssl/certs/ and ssl/keys/"
fi
echo ""

# 5. Check Docker Compose configuration
echo -e "${BLUE}[5/10] Checking Docker Compose Configuration...${NC}"
if docker-compose config > /dev/null 2>&1; then
    check_pass "docker-compose.yml is valid"
else
    check_fail "docker-compose.yml has syntax errors"
fi
echo ""

# 6. Check Nginx configuration
echo -e "${BLUE}[6/10] Checking Nginx Configuration...${NC}"
if [ -f nginx.conf ]; then
    check_pass "nginx.conf found"
else
    check_fail "nginx.conf not found"
fi
echo ""

# 7. Check webhook handler
echo -e "${BLUE}[7/10] Checking Webhook Handler...${NC}"
if [ -f lib/stripe_webhook_handler.rb ]; then
    check_pass "Stripe webhook handler found"
else
    check_fail "Stripe webhook handler not found (lib/stripe_webhook_handler.rb)"
fi
echo ""

# 8. Check if services are running
echo -e "${BLUE}[8/10] Checking Running Services...${NC}"
if docker-compose ps 2>/dev/null | grep -q "stripe-webhook-app"; then
    if docker-compose ps | grep "stripe-webhook-app" | grep -q "Up"; then
        check_pass "Application container is running"
    else
        check_warn "Application container exists but not running"
    fi
else
    check_warn "Services not running (run 'docker-compose up -d' to start)"
fi
echo ""

# 9. Test webhook endpoint locally
echo -e "${BLUE}[9/10] Testing Webhook Endpoint...${NC}"
if docker-compose ps 2>/dev/null | grep "stripe-webhook-app" | grep -q "Up"; then
    if docker-compose exec -T app curl -s http://localhost:3000/api/webhook > /dev/null 2>&1; then
        check_pass "Webhook endpoint responding"
    else
        check_fail "Webhook endpoint not responding"
    fi
else
    check_warn "Cannot test endpoint - services not running"
fi
echo ""

# 10. Check Stripe API connectivity
echo -e "${BLUE}[10/10] Checking Stripe API Connectivity...${NC}"
STRIPE_API_KEY=$(grep "STRIPE_API_KEY" .env 2>/dev/null | cut -d= -f2)
if [ -n "$STRIPE_API_KEY" ] && [ "$STRIPE_API_KEY" != "sk_test_..." ]; then
    if docker-compose exec -T app curl -s https://api.stripe.com/v1/account \
        -H "Authorization: Bearer $STRIPE_API_KEY" > /dev/null 2>&1; then
        check_pass "Stripe API connection successful"
    else
        check_warn "Stripe API authentication failed (check API key validity)"
    fi
else
    check_warn "Stripe API key not configured"
fi
echo ""

# Summary
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Summary${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}Passed: $CHECKS_PASSED${NC}"
echo -e "${YELLOW}Warnings: $CHECKS_WARNING${NC}"
echo -e "${RED}Failed: $CHECKS_FAILED${NC}\n"

# Final recommendations
if [ $CHECKS_FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ All checks passed!${NC}\n"
    echo -e "Next steps:"
    echo -e "1. Start services: ${YELLOW}docker-compose up -d${NC}"
    echo -e "2. Verify deployment: ${YELLOW}curl -I https://hacyberglobal.dgdns.org/api/webhook${NC}"
    echo -e "3. Register webhook in Stripe Dashboard: ${YELLOW}https://dashboard.stripe.com/webhooks${NC}"
    echo -e "4. Send test event from Stripe Dashboard"
    echo -e "5. Check logs: ${YELLOW}docker-compose logs -f app${NC}\n"
else
    echo -e "${RED}✗ Some checks failed. Please review the errors above.${NC}\n"
    echo -e "Quick fixes:"
    echo -e "- Create SSL certs: ${YELLOW}sudo certbot certonly -d hacyberglobal.dgdns.org${NC}"
    echo -e "- Configure .env: ${YELLOW}cp .env.example .env && nano .env${NC}"
    echo -e "- Install Docker: ${YELLOW}https://docs.docker.com/install/${NC}"
fi

exit $CHECKS_FAILED

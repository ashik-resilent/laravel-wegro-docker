#!/bin/bash
# Diagnostic script for call-service container issues
# Run this on your production server to diagnose problems

set -e

echo "=========================================="
echo "Call-Service Container Diagnostic Script"
echo "=========================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if call-service container exists
echo "1. Checking if call-service container exists..."
if docker ps -a | grep -q "call-service"; then
    echo -e "   ${GREEN}✓${NC} call-service container found"
    CONTAINER_STATUS=$(docker ps -a | grep call-service | awk '{print $7}')
    echo "   Container status: $CONTAINER_STATUS"
else
    echo -e "   ${RED}✗${NC} call-service container not found"
    echo "   Please start the container first"
    exit 1
fi
echo ""

# Check if container is running
echo "2. Checking if call-service container is running..."
if docker ps | grep -q "call-service"; then
    echo -e "   ${GREEN}✓${NC} call-service container is running"
else
    echo -e "   ${RED}✗${NC} call-service container is not running"
    echo "   Attempting to start container..."
    docker start call-service || echo "   Failed to start container"
    sleep 3
fi
echo ""

# Check nginx status
echo "3. Checking nginx status..."
NGINX_STATUS=$(docker exec call-service service nginx status 2>&1 || echo "not running")
if echo "$NGINX_STATUS" | grep -q "running"; then
    echo -e "   ${GREEN}✓${NC} nginx is running"
else
    echo -e "   ${RED}✗${NC} nginx is not running"
    echo "   Attempting to start nginx..."
    docker exec call-service service nginx start 2>&1 || echo "   Failed to start nginx"
fi
echo ""

# Check php-fpm status
echo "4. Checking PHP-FPM status..."
PHP_FPM_PROCESSES=$(docker exec call-service ps aux | grep php-fpm | grep -v grep | wc -l)
if [ "$PHP_FPM_PROCESSES" -gt 0 ]; then
    echo -e "   ${GREEN}✓${NC} PHP-FPM is running ($PHP_FPM_PROCESSES processes)"
else
    echo -e "   ${RED}✗${NC} PHP-FPM is not running"
    echo "   Attempting to start PHP-FPM..."
    docker exec call-service service php8.2-fpm start 2>&1 || \
    docker exec call-service service php8.1-fpm start 2>&1 || \
    docker exec call-service service php-fpm start 2>&1 || \
    echo "   Failed to start PHP-FPM"
fi
echo ""

# Check supervisor status
echo "5. Checking supervisor status..."
SUPERVISOR_STATUS=$(docker exec call-service supervisorctl status 2>&1 || echo "error")
if echo "$SUPERVISOR_STATUS" | grep -q "RUNNING\|FATAL\|STOPPED"; then
    echo "   Supervisor processes:"
    docker exec call-service supervisorctl status 2>&1 | sed 's/^/   /'
else
    echo -e "   ${YELLOW}⚠${NC} Could not get supervisor status"
    echo "   Checking if supervisord is running..."
    if docker exec call-service ps aux | grep -q "[s]upervisord"; then
        echo -e "   ${GREEN}✓${NC} supervisord process is running"
    else
        echo -e "   ${RED}✗${NC} supervisord is not running"
    fi
fi
echo ""

# Check supervisor logs
echo "6. Checking supervisor logs (last 20 lines)..."
echo "   --- Supervisor Log ---"
docker exec call-service tail -20 /var/log/supervisor/supervisord.log 2>&1 | sed 's/^/   /' || echo "   Could not read supervisor log"
echo ""

# Check nginx error log
echo "7. Checking nginx error log (last 20 lines)..."
echo "   --- Nginx Error Log ---"
docker exec call-service tail -20 /var/log/nginx/error.log 2>&1 | sed 's/^/   /' || echo "   Could not read nginx error log"
echo ""

# Check Laravel logs
echo "8. Checking Laravel logs (last 10 lines)..."
echo "   --- Laravel Log ---"
docker exec call-service tail -10 /var/www/html/storage/logs/laravel.log 2>&1 | sed 's/^/   /' || \
docker exec call-service tail -10 /var/www/html/storage/logs/*.log 2>&1 | sed 's/^/   /' || \
echo "   Could not read Laravel logs"
echo ""

# Check network connectivity
echo "9. Checking network connectivity..."
if docker network ls | grep -q "wegro_development_network"; then
    echo -e "   ${GREEN}✓${NC} wegro_development_network exists"
    
    # Check if call-service is on the network
    if docker network inspect wegro_development_network 2>/dev/null | grep -q "call-service"; then
        echo -e "   ${GREEN}✓${NC} call-service is on wegro_development_network"
    else
        echo -e "   ${RED}✗${NC} call-service is NOT on wegro_development_network"
        echo "   This will prevent proxy-server from reaching call-service"
    fi
    
    # Check if proxy-server is on the network
    if docker network inspect wegro_development_network 2>/dev/null | grep -q "proxy-server"; then
        echo -e "   ${GREEN}✓${NC} proxy-server is on wegro_development_network"
    else
        echo -e "   ${YELLOW}⚠${NC} proxy-server is NOT on wegro_development_network"
    fi
else
    echo -e "   ${RED}✗${NC} wegro_development_network does not exist"
    echo "   This network is required for proxy-server to reach call-service"
fi
echo ""

# Check if call-service is listening on port 80
echo "10. Checking if call-service is listening on port 80..."
LISTENING=$(docker exec call-service netstat -tlnp 2>/dev/null | grep ":80 " || \
            docker exec call-service ss -tlnp 2>/dev/null | grep ":80 " || \
            echo "")
if [ -n "$LISTENING" ]; then
    echo -e "   ${GREEN}✓${NC} Port 80 is listening"
    echo "$LISTENING" | sed 's/^/   /'
else
    echo -e "   ${RED}✗${NC} Port 80 is NOT listening"
    echo "   This means nginx is not running or not configured correctly"
fi
echo ""

# Check environment variables
echo "11. Checking critical environment variables..."
ENV_CHECK=$(docker exec call-service env | grep -E "APP_ENV|APP_DEBUG|DB_|REDIS_" | head -10 || echo "")
if [ -n "$ENV_CHECK" ]; then
    echo "   Environment variables:"
    echo "$ENV_CHECK" | sed 's/^/   /'
else
    echo -e "   ${YELLOW}⚠${NC} Could not check environment variables"
fi
echo ""

# Test connectivity from proxy-server to call-service
echo "12. Testing connectivity from proxy-server to call-service..."
if docker ps | grep -q "proxy-server"; then
    if docker exec proxy-server ping -c 1 call-service 2>&1 | grep -q "1 received"; then
        echo -e "   ${GREEN}✓${NC} proxy-server can ping call-service"
    else
        echo -e "   ${RED}✗${NC} proxy-server cannot ping call-service"
        echo "   This indicates a network connectivity issue"
    fi
    
    # Test HTTP connectivity
    HTTP_TEST=$(docker exec proxy-server wget -qO- --timeout=2 http://call-service:80 2>&1 || echo "failed")
    if echo "$HTTP_TEST" | grep -q "html\|Laravel\|<!DOCTYPE"; then
        echo -e "   ${GREEN}✓${NC} proxy-server can reach call-service:80"
    else
        echo -e "   ${YELLOW}⚠${NC} proxy-server cannot reach call-service:80 (this is expected if nginx is down)"
    fi
else
    echo -e "   ${YELLOW}⚠${NC} proxy-server is not running, skipping connectivity test"
fi
echo ""

echo "=========================================="
echo "Diagnostic Complete"
echo "=========================================="
echo ""
echo "Next steps:"
echo "1. If nginx is not running, run: docker exec call-service service nginx start"
echo "2. If PHP-FPM is not running, run: docker exec call-service service php8.2-fpm start"
echo "3. If supervisor services are failing, check: docker exec call-service supervisorctl status"
echo "4. Review the logs above for specific error messages"
echo "5. Run FIX_CALL_SERVICE.sh to attempt automatic fixes"
echo ""

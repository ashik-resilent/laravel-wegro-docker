#!/bin/bash
# Fix script for call-service container issues
# This script attempts to fix common issues with nginx, php-fpm, and supervisor

set -e

echo "=========================================="
echo "Call-Service Container Fix Script"
echo "=========================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if call-service container exists and is running
echo "1. Ensuring call-service container is running..."
if ! docker ps | grep -q "call-service"; then
    if docker ps -a | grep -q "call-service"; then
        echo "   Starting call-service container..."
        docker start call-service
        sleep 3
    else
        echo -e "   ${RED}✗${NC} call-service container not found"
        echo "   Please create and start the container first"
        exit 1
    fi
fi
echo -e "   ${GREEN}✓${NC} call-service container is running"
echo ""

# Ensure container is on the correct network
echo "2. Ensuring call-service is on wegro_development_network..."
if docker network ls | grep -q "wegro_development_network"; then
    if ! docker network inspect wegro_development_network 2>/dev/null | grep -q "call-service"; then
        echo "   Connecting call-service to wegro_development_network..."
        docker network connect wegro_development_network call-service 2>/dev/null || \
        echo "   (Container may already be on network or network connection failed)"
    else
        echo -e "   ${GREEN}✓${NC} call-service is on wegro_development_network"
    fi
else
    echo -e "   ${YELLOW}⚠${NC} wegro_development_network does not exist"
    echo "   Creating network..."
    docker network create wegro_development_network 2>/dev/null || echo "   Network may already exist"
    docker network connect wegro_development_network call-service 2>/dev/null || echo "   Connection attempt made"
fi
echo ""

# Fix nginx
echo "3. Fixing nginx..."
echo "   Checking nginx configuration..."
docker exec call-service nginx -t 2>&1 | sed 's/^/   /' || {
    echo -e "   ${YELLOW}⚠${NC} nginx configuration test failed, but continuing..."
}

echo "   Starting nginx..."
docker exec call-service service nginx start 2>&1 | sed 's/^/   /' || {
    echo "   Attempting alternative nginx start method..."
    docker exec call-service /usr/sbin/nginx 2>&1 | sed 's/^/   /' || echo "   Nginx start failed"
}

sleep 2
if docker exec call-service service nginx status 2>&1 | grep -q "running"; then
    echo -e "   ${GREEN}✓${NC} nginx is now running"
else
    echo -e "   ${RED}✗${NC} nginx failed to start"
    echo "   Check nginx error log: docker exec call-service tail -50 /var/log/nginx/error.log"
fi
echo ""

# Fix PHP-FPM
echo "4. Fixing PHP-FPM..."
PHP_FPM_SERVICE=""
# Try to find the correct PHP-FPM service name
for service in php8.2-fpm php8.1-fpm php8.0-fpm php-fpm php7.4-fpm; do
    if docker exec call-service service $service status 2>&1 | grep -q "unrecognized\|not found"; then
        continue
    else
        PHP_FPM_SERVICE=$service
        break
    fi
done

if [ -z "$PHP_FPM_SERVICE" ]; then
    echo "   Searching for PHP-FPM binary..."
    PHP_FPM_BIN=$(docker exec call-service which php-fpm8.2 php-fpm8.1 php-fpm8.0 php-fpm 2>/dev/null | head -1 || echo "")
    if [ -n "$PHP_FPM_BIN" ]; then
        echo "   Found PHP-FPM at: $PHP_FPM_BIN"
        echo "   Starting PHP-FPM directly..."
        docker exec -d call-service $PHP_FPM_BIN --daemonize --fpm-config /etc/php/*/fpm/php-fpm.conf 2>&1 || \
        docker exec -d call-service $PHP_FPM_BIN 2>&1 || echo "   Failed to start PHP-FPM"
    else
        echo -e "   ${YELLOW}⚠${NC} Could not find PHP-FPM service or binary"
    fi
else
    echo "   Starting $PHP_FPM_SERVICE..."
    docker exec call-service service $PHP_FPM_SERVICE start 2>&1 | sed 's/^/   /' || echo "   Failed to start $PHP_FPM_SERVICE"
fi

sleep 2
PHP_FPM_COUNT=$(docker exec call-service ps aux | grep php-fpm | grep -v grep | wc -l)
if [ "$PHP_FPM_COUNT" -gt 0 ]; then
    echo -e "   ${GREEN}✓${NC} PHP-FPM is now running ($PHP_FPM_COUNT processes)"
else
    echo -e "   ${RED}✗${NC} PHP-FPM failed to start"
    echo "   Check PHP-FPM logs: docker exec call-service tail -50 /var/log/php*-fpm.log"
fi
echo ""

# Fix supervisor
echo "5. Fixing supervisor..."
if docker exec call-service ps aux | grep -q "[s]upervisord"; then
    echo -e "   ${GREEN}✓${NC} supervisord is running"
    
    # Restart supervisor services
    echo "   Restarting supervisor services..."
    docker exec call-service supervisorctl restart all 2>&1 | sed 's/^/   /' || echo "   Some services may have failed to restart"
    
    sleep 2
    echo "   Supervisor status:"
    docker exec call-service supervisorctl status 2>&1 | sed 's/^/   /' || echo "   Could not get status"
else
    echo "   Starting supervisord..."
    docker exec call-service service supervisor start 2>&1 | sed 's/^/   /' || {
        echo "   Attempting to start supervisord directly..."
        docker exec -d call-service /usr/bin/supervisord -c /etc/supervisor/supervisord.conf 2>&1 || echo "   Failed to start supervisord"
    }
    sleep 2
fi
echo ""

# Check Horizon specifically (common issue)
echo "6. Checking Horizon..."
HORIZON_STATUS=$(docker exec call-service supervisorctl status horizon 2>&1 || echo "not found")
if echo "$HORIZON_STATUS" | grep -q "FATAL\|EXITED"; then
    echo -e "   ${YELLOW}⚠${NC} Horizon is in FATAL or EXITED state"
    echo "   Checking Horizon logs..."
    docker exec call-service tail -20 /var/log/supervisor/horizon*.log 2>&1 | sed 's/^/   /' || echo "   Could not read Horizon logs"
    
    echo "   Attempting to restart Horizon..."
    docker exec call-service supervisorctl restart horizon 2>&1 | sed 's/^/   /' || echo "   Failed to restart Horizon"
    
    # If Horizon keeps failing, it might be a configuration issue
    echo "   If Horizon continues to fail, check:"
    echo "   - Laravel Horizon is installed: docker exec call-service composer show laravel/horizon"
    echo "   - Horizon config exists: docker exec call-service ls -la /var/www/html/config/horizon.php"
    echo "   - Redis connection: docker exec call-service php artisan horizon:status"
elif echo "$HORIZON_STATUS" | grep -q "RUNNING"; then
    echo -e "   ${GREEN}✓${NC} Horizon is running"
else
    echo "   Horizon status: $HORIZON_STATUS"
fi
echo ""

# Verify services are running
echo "7. Verifying all services..."
echo "   Nginx:"
if docker exec call-service service nginx status 2>&1 | grep -q "running"; then
    echo -e "      ${GREEN}✓${NC} Running"
else
    echo -e "      ${RED}✗${NC} Not running"
fi

echo "   PHP-FPM:"
PHP_FPM_COUNT=$(docker exec call-service ps aux | grep php-fpm | grep -v grep | wc -l)
if [ "$PHP_FPM_COUNT" -gt 0 ]; then
    echo -e "      ${GREEN}✓${NC} Running ($PHP_FPM_COUNT processes)"
else
    echo -e "      ${RED}✗${NC} Not running"
fi

echo "   Supervisor:"
if docker exec call-service ps aux | grep -q "[s]upervisord"; then
    echo -e "      ${GREEN}✓${NC} Running"
else
    echo -e "      ${RED}✗${NC} Not running"
fi

echo "   Port 80:"
LISTENING=$(docker exec call-service netstat -tlnp 2>/dev/null | grep ":80 " || \
            docker exec call-service ss -tlnp 2>/dev/null | grep ":80 " || \
            echo "")
if [ -n "$LISTENING" ]; then
    echo -e "      ${GREEN}✓${NC} Listening"
else
    echo -e "      ${RED}✗${NC} Not listening"
fi
echo ""

# Test connectivity
echo "8. Testing connectivity..."
if docker ps | grep -q "proxy-server"; then
    echo "   Testing from proxy-server to call-service:80..."
    HTTP_TEST=$(docker exec proxy-server wget -qO- --timeout=3 http://call-service:80 2>&1 || echo "failed")
    if echo "$HTTP_TEST" | grep -q "html\|Laravel\|<!DOCTYPE"; then
        echo -e "   ${GREEN}✓${NC} proxy-server can reach call-service"
    else
        echo -e "   ${YELLOW}⚠${NC} proxy-server cannot reach call-service (may need to wait a few seconds)"
    fi
else
    echo -e "   ${YELLOW}⚠${NC} proxy-server is not running, skipping connectivity test"
fi
echo ""

echo "=========================================="
echo "Fix Complete"
echo "=========================================="
echo ""
echo "If issues persist:"
echo "1. Check logs: docker exec call-service tail -50 /var/log/nginx/error.log"
echo "2. Check supervisor: docker exec call-service supervisorctl status"
echo "3. Check Laravel: docker exec call-service tail -50 /var/www/html/storage/logs/laravel.log"
echo "4. Restart container: docker restart call-service"
echo "5. Review DIAGNOSE_CALL_SERVICE.sh output for detailed diagnostics"
echo ""

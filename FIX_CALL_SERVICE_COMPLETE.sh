#!/bin/bash
# Complete fix script for call-service - addresses PHP-FPM and supervisor issues
# This is an improved version that handles the specific failures seen in production

set -e

echo "=========================================="
echo "Complete Call-Service Fix Script"
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
        sleep 5
    else
        echo -e "   ${RED}✗${NC} call-service container not found"
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
        docker network connect wegro_development_network call-service 2>/dev/null || true
    fi
    echo -e "   ${GREEN}✓${NC} call-service is on wegro_development_network"
else
    echo -e "   ${YELLOW}⚠${NC} wegro_development_network does not exist"
    docker network create wegro_development_network 2>/dev/null || true
    docker network connect wegro_development_network call-service 2>/dev/null || true
fi
echo ""

# Fix nginx (should already be running, but verify)
echo "3. Verifying nginx..."
if docker exec call-service service nginx status 2>&1 | grep -q "running"; then
    echo -e "   ${GREEN}✓${NC} nginx is running"
else
    echo "   Starting nginx..."
    docker exec call-service service nginx start 2>&1 || docker exec call-service /usr/sbin/nginx 2>&1 || true
    sleep 2
    if docker exec call-service service nginx status 2>&1 | grep -q "running"; then
        echo -e "   ${GREEN}✓${NC} nginx is now running"
    else
        echo -e "   ${RED}✗${NC} nginx failed to start"
    fi
fi
echo ""

# Fix PHP-FPM - Improved method
echo "4. Fixing PHP-FPM (improved method)..."
PHP_FPM_RUNNING=$(docker exec call-service ps aux | grep php-fpm | grep -v grep | wc -l)

if [ "$PHP_FPM_RUNNING" -gt 0 ]; then
    echo -e "   ${GREEN}✓${NC} PHP-FPM is already running ($PHP_FPM_RUNNING processes)"
else
    echo "   PHP-FPM is not running, attempting to start..."
    
    # First, check PHP-FPM logs for errors
    echo "   Checking PHP-FPM error logs..."
    PHP_FPM_LOG=$(docker exec call-service find /var/log -name "*php*fpm*.log" -type f 2>/dev/null | head -1 || echo "")
    if [ -n "$PHP_FPM_LOG" ]; then
        echo "   Last 10 lines of PHP-FPM log:"
        docker exec call-service tail -10 "$PHP_FPM_LOG" 2>&1 | sed 's/^/      /' || true
    fi
    
    # Try to find PHP-FPM config
    PHP_FPM_CONFIG=$(docker exec call-service find /etc/php -name "php-fpm.conf" -type f 2>/dev/null | head -1 || echo "")
    PHP_VERSION=$(docker exec call-service php -v 2>&1 | head -1 | grep -oE "PHP [0-9]+\.[0-9]+" | awk '{print $2}' || echo "")
    
    echo "   PHP version detected: $PHP_VERSION"
    echo "   PHP-FPM config: $PHP_FPM_CONFIG"
    
    # Try different startup methods
    echo "   Attempting method 1: Service start..."
    docker exec call-service service php8.2-fpm start 2>&1 || \
    docker exec call-service service php8.1-fpm start 2>&1 || \
    docker exec call-service service php-fpm start 2>&1 || true
    
    sleep 2
    PHP_FPM_RUNNING=$(docker exec call-service ps aux | grep php-fpm | grep -v grep | wc -l)
    
    if [ "$PHP_FPM_RUNNING" -eq 0 ]; then
        echo "   Method 1 failed, attempting method 2: Direct binary start..."
        
        # Find PHP-FPM binary
        PHP_FPM_BIN=$(docker exec call-service which php-fpm8.2 php-fpm8.1 php-fpm8.0 php-fpm 2>/dev/null | head -1 || echo "")
        
        if [ -n "$PHP_FPM_BIN" ]; then
            echo "   Found PHP-FPM binary: $PHP_FPM_BIN"
            
            # Try starting with config
            if [ -n "$PHP_FPM_CONFIG" ]; then
                echo "   Starting with config: $PHP_FPM_CONFIG"
                docker exec -d call-service $PHP_FPM_BIN --fpm-config "$PHP_FPM_CONFIG" 2>&1 || true
            else
                # Try common config paths
                for config_path in /etc/php/8.2/fpm/php-fpm.conf /etc/php/8.1/fpm/php-fpm.conf /etc/php/8.0/fpm/php-fpm.conf /etc/php-fpm.conf; do
                    if docker exec call-service test -f "$config_path" 2>/dev/null; then
                        echo "   Starting with config: $config_path"
                        docker exec -d call-service $PHP_FPM_BIN --fpm-config "$config_path" 2>&1 || true
                        break
                    fi
                done
            fi
            
            sleep 2
            PHP_FPM_RUNNING=$(docker exec call-service ps aux | grep php-fpm | grep -v grep | wc -l)
        fi
    fi
    
    if [ "$PHP_FPM_RUNNING" -gt 0 ]; then
        echo -e "   ${GREEN}✓${NC} PHP-FPM is now running ($PHP_FPM_RUNNING processes)"
    else
        echo -e "   ${RED}✗${NC} PHP-FPM failed to start"
        echo "   Manual troubleshooting steps:"
        echo "   1. Check PHP-FPM config: docker exec call-service php-fpm8.2 -t"
        echo "   2. Check logs: docker exec call-service tail -50 /var/log/php*-fpm.log"
        echo "   3. Check if socket directory exists: docker exec call-service ls -la /var/run/php/"
    fi
fi
echo ""

# Fix supervisor - Improved method
echo "5. Fixing supervisor..."
SUPERVISOR_RUNNING=$(docker exec call-service ps aux | grep "[s]upervisord" | wc -l)

if [ "$SUPERVISOR_RUNNING" -gt 0 ]; then
    echo -e "   ${GREEN}✓${NC} supervisord is running"
    
    # Check supervisor status
    echo "   Checking supervisor services..."
    docker exec call-service supervisorctl status 2>&1 | sed 's/^/      /' || echo "      Could not get status"
    
    # Restart all services
    echo "   Restarting all supervisor services..."
    docker exec call-service supervisorctl restart all 2>&1 | sed 's/^/      /' || true
    sleep 3
    
    echo "   Final supervisor status:"
    docker exec call-service supervisorctl status 2>&1 | sed 's/^/      /' || echo "      Could not get status"
else
    echo "   supervisord is not running, attempting to start..."
    
    # Check supervisor config
    echo "   Checking supervisor configuration..."
    if docker exec call-service test -f /etc/supervisor/supervisord.conf 2>/dev/null; then
        echo -e "      ${GREEN}✓${NC} supervisord.conf exists"
    else
        echo -e "      ${RED}✗${NC} supervisord.conf not found"
    fi
    
    # Try to start supervisor
    echo "   Attempting to start supervisor..."
    docker exec call-service service supervisor start 2>&1 | sed 's/^/      /' || {
        echo "   Service start failed, trying direct start..."
        docker exec -d call-service /usr/bin/supervisord -c /etc/supervisor/supervisord.conf 2>&1 || {
            echo "   Direct start failed, trying alternative path..."
            docker exec -d call-service supervisord -c /etc/supervisor/supervisord.conf 2>&1 || true
        }
    }
    
    sleep 3
    SUPERVISOR_RUNNING=$(docker exec call-service ps aux | grep "[s]upervisord" | wc -l)
    
    if [ "$SUPERVISOR_RUNNING" -gt 0 ]; then
        echo -e "   ${GREEN}✓${NC} supervisord is now running"
        sleep 2
        echo "   Supervisor services status:"
        docker exec call-service supervisorctl status 2>&1 | sed 's/^/      /' || echo "      Could not get status"
    else
        echo -e "   ${RED}✗${NC} supervisord failed to start"
        echo "   Check supervisor logs: docker exec call-service tail -50 /var/log/supervisor/supervisord.log"
    fi
fi
echo ""

# Check Horizon specifically
echo "6. Checking Horizon..."
HORIZON_STATUS=$(docker exec call-service supervisorctl status horizon 2>&1 2>/dev/null || echo "not found")
if echo "$HORIZON_STATUS" | grep -q "FATAL\|EXITED\|STOPPED"; then
    echo -e "   ${YELLOW}⚠${NC} Horizon is not running"
    echo "   Checking Horizon logs..."
    docker exec call-service tail -20 /var/log/supervisor/horizon*.log 2>&1 | sed 's/^/      /' || echo "      Could not read logs"
    
    # Try to start Horizon
    if echo "$HORIZON_STATUS" | grep -q "STOPPED"; then
        echo "   Attempting to start Horizon..."
        docker exec call-service supervisorctl start horizon 2>&1 | sed 's/^/      /' || true
    else
        echo "   Attempting to restart Horizon..."
        docker exec call-service supervisorctl restart horizon 2>&1 | sed 's/^/      /' || true
    fi
elif echo "$HORIZON_STATUS" | grep -q "RUNNING"; then
    echo -e "   ${GREEN}✓${NC} Horizon is running"
else
    echo "   Horizon status: $HORIZON_STATUS"
fi
echo ""

# Final verification
echo "7. Final verification..."
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
SUPERVISOR_COUNT=$(docker exec call-service ps aux | grep "[s]upervisord" | wc -l)
if [ "$SUPERVISOR_COUNT" -gt 0 ]; then
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
    sleep 2
    HTTP_TEST=$(docker exec proxy-server wget -qO- --timeout=5 http://call-service:80 2>&1 || echo "failed")
    if echo "$HTTP_TEST" | grep -q "html\|Laravel\|<!DOCTYPE"; then
        echo -e "   ${GREEN}✓${NC} proxy-server can reach call-service"
    else
        echo -e "   ${YELLOW}⚠${NC} proxy-server cannot reach call-service"
        echo "   This may be normal if PHP-FPM is not running"
    fi
else
    echo -e "   ${YELLOW}⚠${NC} proxy-server is not running"
fi
echo ""

echo "=========================================="
echo "Fix Complete"
echo "=========================================="
echo ""
echo "Summary:"
echo "- Nginx: $(docker exec call-service service nginx status 2>&1 | head -1 | grep -q 'running' && echo 'Running' || echo 'Check manually')"
echo "- PHP-FPM: $(docker exec call-service ps aux | grep php-fpm | grep -v grep | wc -l) processes"
echo "- Supervisor: $(docker exec call-service ps aux | grep '[s]upervisord' | wc -l) process(es)"
echo ""
echo "If issues persist:"
echo "1. Check PHP-FPM: docker exec call-service tail -50 /var/log/php*-fpm.log"
echo "2. Check supervisor: docker exec call-service supervisorctl status"
echo "3. Check Laravel: docker exec call-service tail -50 /var/www/html/storage/logs/laravel.log"
echo "4. Restart container: docker restart call-service"
echo ""

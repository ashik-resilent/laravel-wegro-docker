#!/bin/bash
# Quick fix script for call-service - run this first if services are down
# This is a minimal script that attempts the most common fixes

set -e

echo "=== Quick Fix for Call-Service ==="
echo ""

# Ensure container is running
if ! docker ps | grep -q "call-service"; then
    echo "Starting call-service container..."
    docker start call-service
    sleep 3
fi

# Start nginx
echo "Starting nginx..."
docker exec call-service service nginx start 2>&1 || docker exec call-service /usr/sbin/nginx 2>&1 || true
sleep 1

# Start PHP-FPM (try common versions)
echo "Starting PHP-FPM..."
docker exec call-service service php8.2-fpm start 2>&1 || \
docker exec call-service service php8.1-fpm start 2>&1 || \
docker exec call-service service php-fpm start 2>&1 || true
sleep 1

# Restart supervisor services
echo "Restarting supervisor services..."
docker exec call-service supervisorctl restart all 2>&1 || true
sleep 2

# Verify
echo ""
echo "=== Verification ==="
echo "Nginx: $(docker exec call-service service nginx status 2>&1 | head -1)"
echo "PHP-FPM processes: $(docker exec call-service ps aux | grep php-fpm | grep -v grep | wc -l)"
echo "Supervisor status:"
docker exec call-service supervisorctl status 2>&1 | head -5 || echo "Could not get supervisor status"

echo ""
echo "=== Quick Fix Complete ==="
echo "If issues persist, run: ./DIAGNOSE_CALL_SERVICE.sh"

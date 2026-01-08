# Call-Service Container Troubleshooting Guide

## Overview

This guide helps diagnose and fix issues with the `call-service` Laravel container, particularly when nginx, PHP-FPM, or supervisor services are not running.

## Common Issues

### 1. Nginx Not Running

**Symptoms:**
- `docker exec call-service service nginx status` shows "nginx is not running"
- Proxy-server cannot reach call-service
- Application returns 502 Bad Gateway

**Causes:**
- Nginx service not started
- Nginx configuration errors
- Container entrypoint didn't start nginx
- Supervisor not managing nginx

**Solutions:**

```bash
# Quick fix - start nginx manually
docker exec call-service service nginx start

# Check nginx configuration
docker exec call-service nginx -t

# Check nginx error logs
docker exec call-service tail -50 /var/log/nginx/error.log

# If nginx keeps stopping, check if it's managed by supervisor
docker exec call-service supervisorctl status
```

### 2. PHP-FPM Not Running

**Symptoms:**
- `docker exec call-service ps aux | grep php-fpm` returns nothing
- Nginx returns 502 errors
- PHP files not executing

**Causes:**
- PHP-FPM service not started
- Wrong PHP version
- PHP-FPM configuration errors

**Solutions:**

```bash
# Try different PHP-FPM service names
docker exec call-service service php8.2-fpm start
docker exec call-service service php8.1-fpm start
docker exec call-service service php-fpm start

# Check which PHP-FPM is available
docker exec call-service ls /etc/init.d/ | grep php

# Check PHP-FPM logs
docker exec call-service tail -50 /var/log/php*-fpm.log

# Start PHP-FPM directly if service doesn't work
docker exec call-service php-fpm8.2 --daemonize
```

### 3. Supervisor Services Failing

**Symptoms:**
- Horizon keeps restarting (FATAL state)
- Reverb not running
- Services exit immediately after start

**Causes:**
- Missing dependencies
- Configuration errors
- Permission issues
- Missing Laravel packages

**Solutions:**

```bash
# Check supervisor status
docker exec call-service supervisorctl status

# View supervisor logs
docker exec call-service tail -50 /var/log/supervisor/supervisord.log

# Check specific service logs
docker exec call-service tail -50 /var/log/supervisor/horizon*.log
docker exec call-service tail -50 /var/log/supervisor/reverb*.log

# Restart specific service
docker exec call-service supervisorctl restart horizon

# Restart all services
docker exec call-service supervisorctl restart all

# If Horizon is failing, check if it's installed
docker exec call-service composer show laravel/horizon

# Check Horizon configuration
docker exec call-service php artisan horizon:status
```

### 4. Network Connectivity Issues

**Symptoms:**
- proxy-server cannot reach call-service
- Connection refused errors
- DNS resolution failures

**Causes:**
- Container not on correct network
- Network not created
- Container name mismatch

**Solutions:**

```bash
# Check if wegro_development_network exists
docker network ls | grep wegro_development_network

# Check if call-service is on the network
docker network inspect wegro_development_network | grep call-service

# Connect call-service to network
docker network connect wegro_development_network call-service

# Test connectivity from proxy-server
docker exec proxy-server ping -c 1 call-service
docker exec proxy-server wget -qO- http://call-service:80
```

### 5. Port 80 Not Listening

**Symptoms:**
- Nginx appears running but port 80 not accessible
- Connection refused on port 80

**Causes:**
- Nginx not actually running
- Wrong nginx configuration
- Port binding issues

**Solutions:**

```bash
# Check if port 80 is listening
docker exec call-service netstat -tlnp | grep :80
docker exec call-service ss -tlnp | grep :80

# Check nginx is actually running
docker exec call-service ps aux | grep nginx

# Verify nginx configuration
docker exec call-service nginx -t

# Check nginx is listening on correct interface
docker exec call-service cat /etc/nginx/sites-enabled/default | grep listen
```

## Diagnostic Scripts

### Quick Diagnosis

Run the diagnostic script to identify all issues:

```bash
cd ~/laravel-wegro-docker
./DIAGNOSE_CALL_SERVICE.sh
```

This script checks:
- Container status
- Nginx status
- PHP-FPM status
- Supervisor status
- Network connectivity
- Port listening
- Log files

### Automatic Fix

Run the fix script to attempt automatic repairs:

```bash
cd ~/laravel-wegro-docker
./FIX_CALL_SERVICE.sh
```

This script attempts to:
- Start nginx
- Start PHP-FPM
- Fix supervisor services
- Connect to correct network
- Verify all services

## Manual Fix Steps

If automatic fixes don't work, follow these steps:

### Step 1: Ensure Container is Running

```bash
docker ps -a | grep call-service
docker start call-service
```

### Step 2: Check Network

```bash
# Ensure network exists
docker network create wegro_development_network 2>/dev/null || true

# Connect call-service to network
docker network connect wegro_development_network call-service
```

### Step 3: Start Nginx

```bash
# Test configuration first
docker exec call-service nginx -t

# Start nginx
docker exec call-service service nginx start

# Verify it's running
docker exec call-service service nginx status
docker exec call-service ps aux | grep nginx
```

### Step 4: Start PHP-FPM

```bash
# Find correct PHP-FPM service
docker exec call-service ls /etc/init.d/ | grep php

# Start PHP-FPM (try different versions)
docker exec call-service service php8.2-fpm start
# OR
docker exec call-service service php8.1-fpm start

# Verify it's running
docker exec call-service ps aux | grep php-fpm
```

### Step 5: Fix Supervisor

```bash
# Check supervisor status
docker exec call-service supervisorctl status

# If Horizon is failing, check logs
docker exec call-service tail -50 /var/log/supervisor/horizon*.log

# Common Horizon issues:
# 1. Missing package: docker exec call-service composer install
# 2. Config missing: docker exec call-service php artisan horizon:install
# 3. Redis connection: Check .env REDIS_HOST, REDIS_PORT

# Restart services
docker exec call-service supervisorctl restart all
```

### Step 6: Verify Everything

```bash
# Check all services
docker exec call-service service nginx status
docker exec call-service ps aux | grep php-fpm
docker exec call-service supervisorctl status

# Test from proxy-server
docker exec proxy-server wget -qO- http://call-service:80
```

## Common Configuration Issues

### Horizon Failing

If Horizon keeps failing, check:

1. **Package installed:**
   ```bash
   docker exec call-service composer show laravel/horizon
   ```

2. **Configuration exists:**
   ```bash
   docker exec call-service ls -la /var/www/html/config/horizon.php
   ```

3. **Redis connection:**
   ```bash
   docker exec call-service php artisan tinker
   # Then: Redis::connection()->ping();
   ```

4. **Publish config if missing:**
   ```bash
   docker exec call-service php artisan horizon:install
   ```

### Nginx Configuration Errors

Check nginx configuration:

```bash
# Test configuration
docker exec call-service nginx -t

# View configuration
docker exec call-service cat /etc/nginx/sites-enabled/default

# Common issues:
# - Wrong root path
# - PHP-FPM socket path incorrect
# - Missing fastcgi_pass configuration
```

### PHP-FPM Socket Issues

Check PHP-FPM socket:

```bash
# Check socket path in nginx config
docker exec call-service grep fastcgi_pass /etc/nginx/sites-enabled/default

# Check if socket exists
docker exec call-service ls -la /var/run/php/

# Common socket paths:
# - /var/run/php/php8.2-fpm.sock
# - /var/run/php/php8.1-fpm.sock
# - /var/run/php/php-fpm.sock
```

## Prevention

To prevent these issues:

1. **Ensure entrypoint script starts all services:**
   - Check Dockerfile CMD or ENTRYPOINT
   - Verify supervisor starts nginx and php-fpm

2. **Use supervisor for service management:**
   - Configure supervisor to manage nginx
   - Configure supervisor to manage php-fpm
   - This ensures services restart if they crash

3. **Proper network configuration:**
   - Ensure call-service is on wegro_development_network
   - Use docker-compose networks for automatic setup

4. **Health checks:**
   - Add health checks to docker-compose
   - Monitor service status regularly

## Getting Help

If issues persist:

1. Run diagnostic script: `./DIAGNOSE_CALL_SERVICE.sh`
2. Collect logs:
   ```bash
   docker exec call-service tail -100 /var/log/nginx/error.log > nginx-errors.log
   docker exec call-service tail -100 /var/log/supervisor/supervisord.log > supervisor.log
   docker exec call-service tail -100 /var/www/html/storage/logs/laravel.log > laravel.log
   ```
3. Check container logs: `docker logs call-service --tail 100`
4. Review supervisor config: `docker exec call-service cat /etc/supervisor/conf.d/*.conf`

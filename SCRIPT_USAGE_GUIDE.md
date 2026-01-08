# Script Usage Guide for Call-Service Fix

## Which Script to Run for 8883 Port Issue?

Based on your production issues, here's which script to run:

### **For Immediate Fix: Run `FIX_CALL_SERVICE_COMPLETE.sh`**

This is the **recommended script** for your current situation because:
- ✅ It addresses PHP-FPM startup issues (your main problem)
- ✅ It fixes supervisor startup problems
- ✅ It has improved error handling and multiple fallback methods
- ✅ It provides detailed diagnostics

### Script Comparison

| Script | Purpose | When to Use |
|--------|---------|-------------|
| **QUICK_FIX.sh** | Minimal quick fix | When you just need nginx/php-fpm started quickly |
| **FIX_CALL_SERVICE.sh** | Standard fix | General issues, but may not handle PHP-FPM failures well |
| **FIX_CALL_SERVICE_COMPLETE.sh** | **Complete fix with improved methods** | **Use this for your current issues** |
| **DIAGNOSE_CALL_SERVICE.sh** | Diagnostic only | When you need to understand what's wrong |
| **fix-8883-conflict.sh** | Port conflict fix | Only for port 8883 conflicts, not service startup |

## Current Issues and Solutions

### Issue 1: PHP-FPM Not Starting ✅ Fixed in FIX_CALL_SERVICE_COMPLETE.sh

**Problem:** PHP-FPM fails to start with `--daemonize` flag

**Solution in FIX_CALL_SERVICE_COMPLETE.sh:**
- Checks PHP-FPM logs first
- Tries multiple startup methods (service, direct binary)
- Finds correct PHP-FPM config automatically
- Provides detailed error messages

### Issue 2: Supervisor Not Running ✅ Fixed in FIX_CALL_SERVICE_COMPLETE.sh

**Problem:** Supervisor service not starting

**Solution in FIX_CALL_SERVICE_COMPLETE.sh:**
- Checks if supervisor is already running
- Tries multiple startup methods
- Verifies configuration exists
- Provides fallback methods

### Issue 3: 8883 Port Configuration

**Important:** The 8883 port is handled by **proxy-server**, not call-service!

- **call-service** should only listen on **port 80** internally
- **proxy-server** handles port 8883 and forwards to call-service:80
- If you need 8883, ensure proxy-server has it in docker-compose.yml ports

## Step-by-Step Instructions

### Step 1: Run the Complete Fix Script

```bash
cd ~/laravel-wegro-docker
chmod +x FIX_CALL_SERVICE_COMPLETE.sh
./FIX_CALL_SERVICE_COMPLETE.sh
```

This will:
1. Ensure call-service is running
2. Verify network connectivity
3. Start/fix nginx
4. **Fix PHP-FPM with improved methods**
5. **Fix supervisor with improved methods**
6. Check Horizon
7. Verify all services
8. Test connectivity

### Step 2: If PHP-FPM Still Fails

If PHP-FPM still doesn't start, check the logs:

```bash
# Check PHP-FPM error logs
docker exec call-service find /var/log -name "*php*fpm*.log" -type f
docker exec call-service tail -50 /var/log/php*-fpm.log

# Check PHP-FPM configuration
docker exec call-service php-fpm8.2 -t
# OR
docker exec call-service php-fpm8.1 -t

# Check if socket directory exists
docker exec call-service ls -la /var/run/php/
```

Common PHP-FPM issues:
- Missing socket directory: `docker exec call-service mkdir -p /var/run/php/`
- Wrong permissions: `docker exec call-service chown www-data:www-data /var/run/php/`
- Config error: Check the config test output

### Step 3: If Supervisor Still Fails

If supervisor still doesn't start:

```bash
# Check supervisor logs
docker exec call-service tail -50 /var/log/supervisor/supervisord.log

# Check supervisor config
docker exec call-service cat /etc/supervisor/supervisord.conf

# Try manual start
docker exec call-service /usr/bin/supervisord -c /etc/supervisor/supervisord.conf -n
```

### Step 4: Verify 8883 Port Setup

The 8883 port is for **proxy-server**, not call-service:

```bash
# Check if proxy-server has port 8883
docker ps | grep proxy-server
# Should show: 0.0.0.0:8883->8883/tcp

# If not, add to docker-compose.yml:
# ports:
#   - "80:80"
#   - "443:443"
#   - "8883:8883"  # Add this line

# Then restart:
cd ~/laravel-wegro-docker
docker compose restart proxy-server
```

## Quick Reference Commands

### Check Service Status
```bash
# Nginx
docker exec call-service service nginx status

# PHP-FPM
docker exec call-service ps aux | grep php-fpm

# Supervisor
docker exec call-service supervisorctl status

# All services
docker exec call-service ps aux | grep -E "nginx|php-fpm|supervisord"
```

### Manual Service Start
```bash
# Nginx
docker exec call-service service nginx start

# PHP-FPM (try different versions)
docker exec call-service service php8.2-fpm start
docker exec call-service service php8.1-fpm start

# Supervisor
docker exec call-service service supervisor start
```

### Check Logs
```bash
# Nginx errors
docker exec call-service tail -50 /var/log/nginx/error.log

# PHP-FPM errors
docker exec call-service tail -50 /var/log/php*-fpm.log

# Supervisor logs
docker exec call-service tail -50 /var/log/supervisor/supervisord.log

# Laravel logs
docker exec call-service tail -50 /var/www/html/storage/logs/laravel.log
```

## Expected Results After Running FIX_CALL_SERVICE_COMPLETE.sh

After running the script, you should see:

```
✓ call-service container is running
✓ call-service is on wegro_development_network
✓ nginx is running
✓ PHP-FPM is now running (X processes)
✓ supervisord is running
✓ Port 80: Listening
✓ proxy-server can reach call-service
```

If you see ✗ (red X) for any service, follow the troubleshooting steps provided by the script.

## Summary

**For your current production issues, run:**
```bash
./FIX_CALL_SERVICE_COMPLETE.sh
```

This script is specifically designed to handle:
- PHP-FPM startup failures (your main issue)
- Supervisor startup problems
- Multiple fallback methods
- Better error diagnostics

The 8883 port is handled by proxy-server configuration, not call-service. Call-service only needs to work on port 80 internally.

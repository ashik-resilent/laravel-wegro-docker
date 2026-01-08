# Immediate Fix Instructions for Production

## Current Issues Identified

Based on the error logs:
1. ✅ **Nginx is not running** in call-service container
2. ✅ **PHP-FPM is not running** in call-service container  
3. ✅ **Horizon is failing** (exit status 1, FATAL state)
4. ✅ **Supervisor is running** but services aren't starting properly

## Quick Fix (Run This First)

On your production server, run:

```bash
cd ~/laravel-wegro-docker
./QUICK_FIX.sh
```

This will attempt to:
- Start nginx
- Start PHP-FPM
- Restart supervisor services

## Full Diagnostic and Fix

If quick fix doesn't work, run the comprehensive scripts:

### Step 1: Diagnose
```bash
cd ~/laravel-wegro-docker
./DIAGNOSE_CALL_SERVICE.sh
```

This will show you:
- Container status
- Service status (nginx, php-fpm, supervisor)
- Network connectivity
- Log files
- Configuration issues

### Step 2: Auto-Fix
```bash
cd ~/laravel-wegro-docker
./FIX_CALL_SERVICE.sh
```

This will attempt to automatically fix:
- Nginx startup
- PHP-FPM startup
- Supervisor configuration
- Network connectivity
- Service verification

## Manual Fix Steps

If scripts don't work, follow these manual steps:

### 1. Start Nginx
```bash
docker exec call-service service nginx start
docker exec call-service service nginx status
```

### 2. Start PHP-FPM
```bash
# Try different PHP versions
docker exec call-service service php8.2-fpm start
# OR
docker exec call-service service php8.1-fpm start
# OR  
docker exec call-service service php-fpm start

# Verify
docker exec call-service ps aux | grep php-fpm
```

### 3. Fix Horizon (if failing)
```bash
# Check why Horizon is failing
docker exec call-service tail -50 /var/log/supervisor/horizon*.log

# Common fixes:
# - If package missing:
docker exec call-service composer install

# - If config missing:
docker exec call-service php artisan horizon:install

# - Check Redis connection in .env
docker exec call-service grep REDIS /var/www/html/.env

# Restart Horizon
docker exec call-service supervisorctl restart horizon
```

### 4. Verify Network
```bash
# Ensure call-service is on wegro_development_network
docker network inspect wegro_development_network | grep call-service

# If not, connect it:
docker network connect wegro_development_network call-service

# Test connectivity from proxy-server
docker exec proxy-server ping -c 1 call-service
docker exec proxy-server wget -qO- --timeout=3 http://call-service:80
```

### 5. Verify Everything Works
```bash
# Check all services
docker exec call-service service nginx status
docker exec call-service ps aux | grep php-fpm
docker exec call-service supervisorctl status

# Test from proxy-server
docker exec proxy-server curl -I http://call-service:80
```

## Root Cause Analysis

The main issue is that **services are not starting automatically** when the container starts. This could be because:

1. **Entrypoint script not starting services** - The Dockerfile entrypoint may not be starting nginx/php-fpm
2. **Supervisor not configured for nginx/php-fpm** - Supervisor may only be managing Horizon/Reverb
3. **Services crashing immediately** - Configuration errors causing services to exit

## Long-term Fix

To prevent this from happening again, you need to ensure:

1. **Supervisor manages nginx and php-fpm** - Add them to supervisor config
2. **Proper entrypoint script** - Ensure all services start on container boot
3. **Health checks** - Add health checks to detect when services are down

### Recommended Supervisor Configuration

Add to `/etc/supervisor/conf.d/nginx.conf`:
```ini
[program:nginx]
command=/usr/sbin/nginx -g "daemon off;"
autostart=true
autorestart=true
stderr_logfile=/var/log/supervisor/nginx.err.log
stdout_logfile=/var/log/supervisor/nginx.out.log
```

Add to `/etc/supervisor/conf.d/php-fpm.conf`:
```ini
[program:php-fpm]
command=/usr/sbin/php-fpm8.2 --nodaemonize --fpm-config /etc/php/8.2/fpm/php-fpm.conf
autostart=true
autorestart=true
stderr_logfile=/var/log/supervisor/php-fpm.err.log
stdout_logfile=/var/log/supervisor/php-fpm.out.log
```

## Files Created

I've created the following files in `laravel-wegro-docker`:

1. **QUICK_FIX.sh** - Quick fix script (run this first)
2. **DIAGNOSE_CALL_SERVICE.sh** - Comprehensive diagnostic script
3. **FIX_CALL_SERVICE.sh** - Automatic fix script
4. **CALL_SERVICE_TROUBLESHOOTING.md** - Detailed troubleshooting guide
5. **IMMEDIATE_FIX_INSTRUCTIONS.md** - This file

## Next Steps

1. **Copy scripts to production server:**
   ```bash
   # On your local machine (if you have access)
   scp ~/laravel-wegro-docker/*.sh user@server:~/laravel-wegro-docker/
   scp ~/laravel-wegro-docker/*.md user@server:~/laravel-wegro-docker/
   ```

2. **Run on production:**
   ```bash
   cd ~/laravel-wegro-docker
   chmod +x *.sh
   ./QUICK_FIX.sh
   ```

3. **If issues persist:**
   ```bash
   ./DIAGNOSE_CALL_SERVICE.sh > diagnosis.log
   ./FIX_CALL_SERVICE.sh > fix.log
   ```

4. **Review logs and fix root cause** in the call-service Dockerfile/entrypoint

## Support

If issues continue after running these scripts:
1. Check the diagnostic output
2. Review log files mentioned in the output
3. Check the troubleshooting guide: `CALL_SERVICE_TROUBLESHOOTING.md`
4. Verify call-service Dockerfile and entrypoint scripts

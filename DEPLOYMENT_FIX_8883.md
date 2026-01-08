# Fix for Port 8883 and Root URL Issues

## Issues Fixed

1. **Port 8883 returning 503**: Fixed by adding port 8883 to proxy-server and creating custom nginx configuration
2. **Root URL (http://138.68.55.52/) connection refused**: Fixed by adding default server block for IP address access

## Changes Made

### 1. laravel-wegro-docker/docker-compose.yml
- Added port `8883:8883` to proxy-server service

### 2. laravel-wegro-docker/nginx/conf.d/callcircle-8883.conf (NEW)
- Created custom nginx server block for port 8883
- Proxies HTTP requests to call-service:80
- Handles both domain name and IP address access

### 3. laravel-wegro-docker/nginx/conf.d/default-ip.conf (NEW)
- Created default server block for port 80
- Handles direct IP address access (138.68.55.52)
- Proxies to call-service when available

## Deployment Steps

### Step 1: Update laravel-wegro-docker

```bash
cd ~/laravel-wegro-docker
git pull origin main  # or fetch the latest changes
docker compose down proxy-server
docker compose up -d proxy-server
```

### Step 2: Verify Port 8883 is Listening

```bash
docker ps | grep proxy-server
# Should show: 0.0.0.0:8883->8883/tcp
```

### Step 3: Start call-service (if not running)

```bash
cd ~/resilient-projects/Final_project/call-circle-docker

# Ensure .env file has correct VIRTUAL_HOST
# VIRTUAL_HOST=callcircle.resilentsolutions.com

# Start call-service
docker compose -f docker/composes/docker-compose.yml -f docker/composes/docker-compose.prod.yml up -d call-service
```

### Step 4: Verify Services

```bash
# Check call-service is running
docker ps | grep call-service

# Check proxy-server logs
docker logs proxy-server

# Test port 8883
curl -I http://138.68.55.52:8883/login

# Test root URL
curl -I http://138.68.55.52/
```

## Troubleshooting

### Port 8883 still returns 503

1. **Check if call-service is running:**
   ```bash
   docker ps | grep call-service
   ```

2. **Check if call-service is on the correct network:**
   ```bash
   docker inspect call-service | grep -A 5 Networks
   # Should show: wegro_development_network
   ```

3. **Check proxy-server can reach call-service:**
   ```bash
   docker exec proxy-server ping -c 2 call-service
   ```

4. **Check nginx configuration:**
   ```bash
   docker exec proxy-server nginx -t
   docker exec proxy-server cat /etc/nginx/conf.d/callcircle-8883.conf
   ```

### Root URL still refuses connection

1. **Check if proxy-server is listening on port 80:**
   ```bash
   docker ps | grep proxy-server
   # Should show: 0.0.0.0:80->80/tcp
   ```

2. **Check firewall:**
   ```bash
   sudo ufw status
   # Should show: 80/tcp ALLOW
   ```

3. **Check nginx logs:**
   ```bash
   docker logs proxy-server
   ```

## Important Notes

- **Port 8883** is now handled by proxy-server, not call-service directly
- **call-service** should use `expose: - "80"` in production (already configured in docker-compose.prod.yml)
- **VIRTUAL_HOST** environment variable must be set in call-service's .env file
- The custom nginx configs are included by nginx-proxy automatically

## Network Configuration

Both proxy-server and call-service must be on the same Docker network:
- Network name: `wegro_development_network`
- This is configured in both docker-compose files

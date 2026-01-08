# Fix for Port 8883 and Root URL Issues

## Issues Fixed

1. **Port 8883 returning 502 Bad Gateway**: Fixed by changing call-service to directly expose port 8883 (bypassing nginx-proxy)
2. **Root URL (http://138.68.55.52/) connection refused**: Fixed by direct port exposure

## Solution

call-service now directly exposes port 8883, similar to admin-portal on port 8884. This bypasses nginx-proxy entirely for port 8883.

## Changes Made

### 1. laravel-wegro-docker/docker-compose.yml
- **Removed** port `8883:8883` from proxy-server (no longer needed)
- **Removed** custom nginx configs (callcircle-8883.conf, default-ip.conf)

### 2. call-circle-docker/docker/composes/docker-compose.prod.yml
- **Changed** from `expose: - "80"` to `ports: - "8883:80"` (direct port mapping)
- **Removed** VIRTUAL_HOST environment variables (not needed for direct exposure)
- **Added** `container_name: call-service` for consistency

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

### Port 8883 still returns 502

1. **Check if call-service is running:**
   ```bash
   docker ps | grep call-service
   ```

2. **Check if port 8883 is mapped:**
   ```bash
   docker ps | grep call-service
   # Should show: 0.0.0.0:8883->80/tcp
   ```

3. **Check firewall:**
   ```bash
   sudo ufw status
   # Port 8883 should be allowed
   ```

4. **Check call-service logs:**
   ```bash
   docker logs call-service
   ```

5. **Test from inside container:**
   ```bash
   docker exec call-service curl -I http://localhost/
   ```

### Port conflict error

If you get a port conflict, check what's using port 8883:
```bash
sudo lsof -i :8883
# or
sudo netstat -tulpn | grep 8883
```

## Important Notes

- **Port 8883** is now directly exposed by call-service (bypassing nginx-proxy)
- **call-service** uses `ports: - "8883:80"` for direct port mapping
- **No VIRTUAL_HOST** environment variables needed (direct exposure)
- **Architecture matches admin-portal** on port 8884

## Network Configuration

call-service must be on the Docker network:
- Network name: `wegro_development_network`
- Configured in docker-compose.prod.yml

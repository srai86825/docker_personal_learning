# Docker Compose Guide - Complete Reference

## File Structure Overview

```yaml
version: '3.8'      # Compose file format version
services:           # Define containers
networks:           # Custom networks
volumes:            # Persistent storage
```

## Version

```yaml
version: '3.8'
```
- **Purpose**: Specifies Docker Compose file format
- **Common versions**: `3.8`, `3.9` (latest), `2.4` (legacy)
- **Why matters**: Different versions support different features

## Services Section

### API Service Configuration

```yaml
api:
  build: .                    # Build from Dockerfile in current directory
  container_name: vq-api      # Custom container name (instead of auto-generated)
  restart: always             # Restart policy
```

#### Build vs Image
```yaml
build: .              # Build from local Dockerfile
# OR
image: nginx:alpine   # Use pre-built image from registry
```

#### Restart Policies
```yaml
restart: always       # Always restart on failure/reboot
restart: unless-stopped  # Restart unless manually stopped
restart: on-failure   # Only restart on error
restart: no          # Never restart (default)
```

### Database Service Configuration

```yaml
db:
  image: postgres:15-alpine   # Use official PostgreSQL image
  container_name: vq-db
```

#### Image Naming Convention
```yaml
postgres:15-alpine    # postgres=name, 15=version, alpine=variant
node:18-slim         # node=name, 18=version, slim=variant
```

## Port Mapping

```yaml
ports:
  - "4000:4000"      # host_port:container_port
  - "5432:5432"
```

- **Left side (4000)**: Port on your computer
- **Right side (4000)**: Port inside container
- **Access**: `localhost:4000` connects to container port 4000

### Port Examples
```yaml
ports:
  - "3000:4000"      # localhost:3000 → container:4000
  - "80:8080"        # localhost:80 → container:8080
  - "5432"           # Random host port → container:5432
```

## Environment Variables

```yaml
environment:
  - NODE_ENV=development           # Key=Value format
  - PORT=4000
  - DATABASE_URL=postgresql://...
```

### Alternative Formats
```yaml
environment:
  NODE_ENV: development           # YAML key-value
  PORT: 4000
  
# OR use .env file
env_file:
  - .env                         # Load from file
```

## Dependencies

```yaml
depends_on:
  - db                          # Start 'db' before 'api'
```

- **Purpose**: Control startup order
- **Limitation**: Only waits for container start, not service readiness
- **Production**: Use health checks for true readiness

## Volumes

### Named Volumes
```yaml
volumes:
  postgres_data:                # Named volume (managed by Docker)

services:
  db:
    volumes:
      - postgres_data:/var/lib/postgresql/data
```

### Bind Mounts
```yaml
volumes:
  - ./logs:/usr/src/app/logs    # ./logs (host) → /usr/src/app/logs (container)
  - ./db-init:/docker-entrypoint-initdb.d
```

#### Volume Types Comparison
```yaml
# Named volume (Docker managed)
- postgres_data:/var/lib/postgresql/data

# Bind mount (host directory)
- ./logs:/usr/src/app/logs

# Anonymous volume
- /app/node_modules
```

## Networks

```yaml
networks:
  vq-network:
    driver: bridge              # Default network type
```

### Network Benefits
- **Isolation**: Services in same network can communicate
- **DNS**: Services find each other by name (`db:5432`)
- **Security**: Isolated from other Docker networks

### Communication Example
```yaml
# API connects to database using service name
DATABASE_URL=postgresql://user:pass@db:5432/dbname
#                                    ↑
#                              service name, not localhost
```

## Essential Commands

### Basic Operations
```bash
# Start all services
docker-compose up

# Start in background
docker-compose up -d

# Stop all services
docker-compose down

# Stop and remove volumes
docker-compose down -v
```

### Building & Rebuilding
```bash
# Build images
docker-compose build

# Force rebuild
docker-compose build --no-cache

# Build and start
docker-compose up --build
```

### Scaling Services
```bash
# Run multiple instances
docker-compose up --scale api=3

# Scale specific service
docker-compose scale api=5
```

### Viewing & Debugging
```bash
# View running services
docker-compose ps

# View logs
docker-compose logs
docker-compose logs api          # Specific service
docker-compose logs -f api       # Follow logs

# Execute commands in container
docker-compose exec api bash     # Open shell
docker-compose exec db psql -U vquser -d vqdb  # Database shell
```

### Development Workflow
```bash
# Development with file watching
docker-compose up --build

# Restart single service
docker-compose restart api

# View service details
docker-compose config           # Validate and view config
```

## File Naming & Location

```bash
# Default file names (auto-detected)
docker-compose.yml
docker-compose.yaml

# Custom file name
docker-compose -f my-compose.yml up

# Multiple files (override pattern)
docker-compose -f docker-compose.yml -f docker-compose.prod.yml up
```

## Environment-Specific Configs

### Development
```yaml
# docker-compose.yml
environment:
  - NODE_ENV=development
  - DEBUG=true
```

### Production Override
```yaml
# docker-compose.prod.yml
services:
  api:
    environment:
      - NODE_ENV=production
      - DEBUG=false
    restart: unless-stopped
```

## Security Best Practices

### Secrets Management
```yaml
# Don't do this in production
environment:
  - AWS_SECRET_ACCESS_KEY=actual_secret

# Better approach
env_file:
  - .env.local          # Add to .gitignore
  
# Best approach (Docker Swarm/K8s)
secrets:
  db_password:
    file: ./secrets/db_password.txt
```

### Network Security
```yaml
# Don't expose database ports externally in production
db:
  # ports: - "5432:5432"  ← Remove this line
  expose:
    - "5432"                     # Only internal access
```

## Troubleshooting

### Common Issues
```bash
# Port already in use
docker-compose down              # Stop conflicting services

# Permission denied
sudo docker-compose up          # Run with elevated permissions

# Image not found
docker-compose build            # Build local images first

# Network issues
docker-compose down && docker-compose up  # Recreate network
```

### Health Checks
```yaml
services:
  api:
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:4000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
```

## Key Concepts Summary

| Concept | Purpose | Example |
|---------|---------|---------|
| **Services** | Define containers | `api:`, `db:` |
| **Networks** | Container communication | `vq-network` |
| **Volumes** | Data persistence | `postgres_data` |
| **Ports** | External access | `"4000:4000"` |
| **Environment** | Configuration | `NODE_ENV=development` |
| **Depends_on** | Startup order | `depends_on: - db` |
| **Build** | Custom images | `build: .` |
| **Image** | Pre-built images | `postgres:15-alpine` |

## Next Steps to Kubernetes

Your compose file demonstrates understanding of:
- ✅ **Multi-service orchestration** → K8s Deployments
- ✅ **Service networking** → K8s Services  
- ✅ **Persistent storage** → K8s PersistentVolumes
- ✅ **Configuration management** → K8s ConfigMaps/Secrets
- ✅ **Container dependencies** → K8s InitContainers


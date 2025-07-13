# Security: images using normal user isntead of root
## The problem:
```dockerfile
# By default, everything runs as root user (dangerous!)
FROM node:20-alpine
WORKDIR /app
COPY . .
CMD ["node", "app.js"]        # Runs as root = security risk
```

## The solution:
```dockerfile
FROM node:20-alpine
RUN addgroup app && adduser -S -G app app
USER app                      # Switch to non-root user
WORKDIR /app
COPY . .
CMD ["node", "app.js"]        # Now runs as 'app' user
```

## Breaking down the syntax:

```bash
RUN addgroup app && adduser -S -G app app
    ↑        ↑      ↑       ↑  ↑  ↑   ↑
    │        │      │       │  │  │   └── Username: 'app'
    │        │      │       │  │  └──── Group: 'app' 
    │        │      │       │  └─────── Add to group (-G)
    │        │      │       └────────── System user (-S)
    │        │      └────────────────── Add user command
    │        └───────────────────────── Group name: 'app'
    └────────────────────────────────── Create group command
```

## What each part does:
- `addgroup app` → Creates group called "app"
- `adduser -S -G app app` → Creates system user "app" in group "app"
- `USER app` → All future commands run as "app" user

## Why this matters:
```bash
# Bad - runs as root
docker run my-app              # If hacked, attacker has root access

# Good - runs as regular user  
docker run my-app              # If hacked, attacker has limited access
```

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

## Type of roles
### 1. Root user (dangerous)
UID: 0
Privileges: EVERYTHING
Can: Delete system files, access all data

### 2. Regular user  
UID: 1000+
Privileges: Limited
Can: Access own files, run programs
Has: Home directory, login shell

### 3. System user (what we create)
UID: 100-999  
Privileges: Limited (like regular user)
Can: Run programs, access assigned files
Has: NO home directory, NO login shell

## What each part does:
- `addgroup app` → Creates group called "app"
- `adduser -S -G app app` → Creates system user "app" in group "app"
- `USER app` → All future commands run as "app" user

## Change ownership of files before running
```bash
RUN chown -R app_user:app_group /app
    ↑     ↑  ↑        ↑         ↑
    │     │  │        │         └── Target directory
    │     │  │        └─────────── Group to assign
    │     │  └──────────────────── User to assign  
    │     └─────────────────────── Recursive flag
    └───────────────────────────── Change ownership command
```

## Why this matters:
```bash
# Bad - runs as root
docker run my-app              # If hacked, attacker has root access

# Good - runs as regular user  
docker run my-app              # If hacked, attacker has limited access
```



## Handling images/containers

### 1. Build image from dockerfile in current directory with :latest (default) tag
 docker build -t react-docker .    

### 2. Run the image in a container while mapping port 5173 of isolated container to 3000 of host 
 docker run -p 3000:5173 react-docker

### 3. Delete all the stopped containers
 docker container prune

###4. 





# Dev environment run a app

```bash
docker run -p 3000:5173 -v "$(pwd):/app" -v /app/node_modules react-docker
           ↑            ↑               ↑
           │            │               └── Anonymous volume for node_modules
           │            └─────────────────── Mount your local code
           └──────────────────────────────── Port mapping
```

## What each flag does:

### 1. Port mapping:
```bash
-p 3000:5173
# Access container's port 5173 via localhost:3000
```

### 2. Code volume mount:
```bash
-v "$(pwd):/app"
# Mount your local project folder to /app in container
# Enables hot reloading!
```

### 3. Node modules protection:
```bash
-v /app/node_modules
# Creates anonymous volume for node_modules
# Prevents local files from overwriting container's node_modules
```

## Why the second volume is crucial:

```bash
# Without /app/node_modules volume:
-v "$(pwd):/app"              # Your local folder overwrites EVERYTHING in /app
                             # Including node_modules built for Alpine Linux!
                             # App crashes: "Cannot find module 'xyz'"

# With /app/node_modules volume:
-v "$(pwd):/app"              # Your code files mount
-v /app/node_modules          # But node_modules stays from container
                             # App works perfectly!
```

## What gets mounted where:

```
Your Computer          Container
├── src/              →  /app/src/              (live sync)
├── package.json      →  /app/package.json     (live sync)  
├── node_modules/     ×  /app/node_modules/    (container's version protected)
└── README.md         →  /app/README.md        (live sync)
```

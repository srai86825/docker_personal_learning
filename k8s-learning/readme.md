# Kubernetes Learning Notes - Core Concepts

## Node vs Pod vs Container

### Node (Physical/Virtual Machine)
```
Node = Your actual computer/server
├─ Like your laptop or cloud instance
├─ Runs Docker + Kubernetes agent (kubelet)
└─ Can host multiple pods
```

### Pod (Wrapper around containers)
```
Pod = Smallest deployable unit in K8s
├─ Usually contains 1 container (your app)
├─ Sometimes 2+ containers that work together
├─ Shares network (same IP) and storage
└─ Gets scheduled on a Node
```

### Container (Your actual app)
```
Container = Your Docker image running
├─ Your Node.js app, database, etc.
├─ Lives inside a Pod
└─ Same as docker run command
```

## Relationship Breakdown

```
Cluster (Kitchen)
├── Node 1 (Counter 1)
│   ├── Pod A (Station 1) → Container: your-agent
│   └── Pod B (Station 2) → Container: nginx
├── Node 2 (Counter 2)  
│   ├── Pod C (Station 3) → Container: your-agent
│   └── Pod D (Station 4) → Container: postgres
└── Node 3 (Counter 3)
    └── Pod E (Station 5) → Container: your-agent
```

## Docker vs Kubernetes

| **Docker** | **Kubernetes** |
|------------|----------------|
| `docker run my-app` | Pod with my-app container |
| Single machine | Multiple machines |
| Manual scaling | Auto-scaling |
| `docker-compose.yml` | YAML manifests |

## One App Per Pod Rule

#### ✅ Correct Way
```yaml
# Pod 1: Agent app
apiVersion: v1
kind: Pod
spec:
  containers:
  - name: agent
    image: your-agent:latest

# Pod 2: Database  
apiVersion: v1
kind: Pod
spec:
  containers:
  - name: database
    image: postgres:15
```

#### ❌ Wrong Way
```yaml
# DON'T: Multiple apps in same pod
apiVersion: v1
kind: Pod
spec:
  containers:
  - name: agent
    image: your-agent:latest
  - name: database
    image: postgres:15
```

### Why One App Per Pod?

**Scaling**: 
- Need 5 agents? Scale agent pods only
- Don't need 5 databases too

**Independence**:
- Agent crashes → only agent restarts
- Database stays running

**Resources**:
- Agent needs 1GB RAM
- Database needs 4GB RAM
- Can allocate separately

##### Exception: Helper Containers
```yaml
# OK: Main app + helper containers
apiVersion: v1
kind: Pod
spec:
  containers:
  - name: agent           # Main app
    image: your-agent:latest
  - name: log-collector   # Helper: collects logs
    image: fluentd:latest
  - name: proxy          # Helper: handles SSL
    image: nginx:latest
```

**Rule**: If containers MUST work together and share files/network, they can be in same pod.


### ConfigMaps & Secrets

#### ConfigMaps
• **Purpose**: Store non-sensitive configuration data (URLs, settings, feature flags)
• **Usage**: Inject as environment variables or mount as files in pods
• **Example**: `DATABASE_URL`, `API_ENDPOINT`, `NODE_ENV=production`
• **Security**: Plain text, visible to anyone with cluster access

#### Secrets
• **Purpose**: Store sensitive data (passwords, API keys, certificates)
• **Usage**: Same as ConfigMaps but with encryption and restricted access
• **Example**: `JWT_SECRET`, `AWS_SECRET_KEY`, `DATABASE_PASSWORD`
• **Security**: Base64 encoded, encrypted at rest, role-based access control

#### Quick Decision Rule
• **Public info you'd put in Git** → ConfigMap
• **Private info you'd never commit** → Secret


## Communication Between Pods
There are several ways to do this, including hardcoded IPs, etc. 

### 1. Pod IPs (Basic but unstable)
```bash
# Each pod gets an IP
Pod A: 10.244.1.5
Pod B: 10.244.1.6
Pod C: 10.244.2.3

# Pod A can talk to Pod B
curl http://10.244.1.6:8080/api
```

**Problem**: IPs change when pods restart!

### 2. Services (Stable communication)
Service is a way to expose a group of Pods under a single IP and DNS name. It ensures consistent access to Pods, even if they restart or change IPs.
```yaml
# Service = Stable endpoint for pods
apiVersion: v1
kind: Service
metadata:
  name: agent-service
spec:
  selector:
    app: agent        # Targets pods with label app=agent
  ports:
  - port: 8080
    targetPort: 8080
```
**Agent example**:
```javascript
// Instead of hardcoded IP
const response = await fetch('http://10.244.1.5:8080/execute');

// Use service name
const response = await fetch('http://agent-service:8080/execute');
```

**How it works**:
User sends request Calculate("2+3") to Service (Uses load balancing), it automatically decide which pod to give this request to resolve. It uses Round-robin to decide it. Then sends back the response.

example:
```
Web API, Image resizer, Calculator service
├─ Request 1 to Pod A: "2 + 2" → Response: "4"
├─ Request 2 to Pod B: "3 + 3" → Response: "6"  
└─ No problem! Each request is independent
```

# Stateless vs Stateful Services - Communication & Failover

## Stateless Services (Load Balancing Works)

**Definition**: Each request is independent, no memory between requests.

```
Client → Service → Pod A: "Calculate 2+2" → Response: "4"
Client → Service → Pod B: "Calculate 3+3" → Response: "6"
✅ Works perfectly! Any pod can handle any request.

Failover Flow:
Pod A dies → Service automatically routes all traffic to Pod B
No data loss, seamless experience.
```

## Stateful Services (Load Balancing Breaks)

**Definition**: Maintains state/memory between requests (sessions, files, user data).

```
Client → Service → Pod A: "Login user1, store session" → Pod A remembers user1
Client → Service → Pod B: "Get user1 data" → Pod B: "Who is user1??" ❌
Problem: State stored in Pod A, but request went to Pod B.

Failover Flow:
Pod A dies → All user1's session data LOST
Pod B can't help user1 because it doesn't know user1's state.
```

## Solutions for Each Type

#### Stateless Solutions
- **Standard Service**: Load balance freely across all pods
- **Auto-scaling**: Add/remove pods based on traffic
- **Rolling updates**: Replace pods without downtime

#### Stateful Solutions
1. **Individual Services**: One service per stateful instance (`user1-service` → `user1-pod`)
2. **Session Affinity**: Sticky sessions route same client to same pod
3. **StatefulSets**: Pods get stable names + persistent storage
4. **External State**: Store state in database/cache, not in pods





###  Service Discovery (DNS)
Kubernetes DNS automatically assigns a DNS name to each Service, like `my-service.default.svc.cluster.local`, which resolves to the Service’s ClusterIP. This allows Pods to communicate using Service names instead of IPs. DNS is handled by CoreDNS inside the cluster. For example, a Pod can call `http://calculator-service/compute` to reach the calculator service internally.

```bash
# K8s automatically creates DNS
agent-service.default.svc.cluster.local
    ↑         ↑       ↑      ↑
service   namespace  service cluster
 name                type   domain

# Short form works within same namespace
agent-service
```


### 3. Ingress (External Access)
**What it is**: Allows outside world (internet) to reach pods using domain names.

```
Internet → https://myapp.com → Ingress → Service → Pod B
```

**Example**:
```javascript
// Your browser or external API
const response = await fetch('https://myapp.com/api/users');
// Reaches Pod B inside the cluster
```


## StatefulSets (Coordinated State)
• **Purpose**: Multiple pods that need to coordinate and share state
• **Stable identities**: Pods get fixed names (web-0, web-1, web-2)
• **Persistent storage**: Each pod gets dedicated storage that survives restarts
• **Ordered operations**: Pods created/deleted in sequence (0→1→2, then 2→1→0)
• **Use cases**: Databases, distributed systems, clustered applications

```yaml
# StatefulSet Example
spec:
  serviceName: "web"
  replicas: 3
  # Creates: web-0, web-1, web-2 pods
  # Each pod can find others at: web-0.web, web-1.web, web-2.web
```
#### When to Use StatefulSets?

• **Database cluster**: PostgreSQL primary + replicas need to coordinate
• **Distributed cache**: Redis cluster nodes need to know each other
• **Message queue**: Kafka brokers need stable identities



# K8s Deployments 

#### What is Deployment?
• **Pod Manager**: Creates and controls multiple identical pods automatically
• **Declarative**: You say "I want 3 pods", K8s ensures 3 pods always exist
• **Higher-level abstraction**: Don't manage individual pods, manage the group

#### Why Better than Manual Pods?
• **Auto-restart**: Pod crashes → Deployment creates new one immediately
• **Rolling updates**: Update image → Gradual replacement, no downtime
• **Scaling**: Change replicas → K8s adds/removes pods automatically
• **Self-healing**: Unhealthy pods → Automatically replaced with healthy ones

#### What Deployments Handle?
• **Replica management**: Maintain desired number of pods
• **Pod lifecycle**: Creation, deletion, health monitoring
• **Version control**: Track rollout history, easy rollbacks
• **Load distribution**: Spread pods across different nodes

#### When to Move to Dynamic Scaling?
• **Variable demand**: Users come and go unpredictably
• **Resource efficiency**: Don't want to pay for unused capacity
• **Per-user isolation**: Each user needs dedicated resources
• **Cost optimization**: Scale to zero when no users active

### Dynamic Scaling Approaches

#### 1. Horizontal Pod Autoscaler (HPA)
• **Use case**: Shared service with varying load
• **Trigger**: CPU/memory thresholds (>70% → scale up)
• **Example**: Web API serving multiple users

#### 2. Manual Scaling via API
• **Use case**: Application-controlled scaling
• **Trigger**: Business logic (user count, time of day)
• **Example**: Scale up during business hours

#### 3. Dynamic Deployment Creation
• **Use case**: Complete user isolation (your agents)
• **Trigger**: User joins/leaves
• **Example**: 1 deployment per user, delete when user inactive

#### 4. Scale-to-Zero
• **Use case**: Keep deployment but pause resources
• **Trigger**: Inactivity periods
• **Example**: Set replicas=0 for idle users, replicas=1 when active

## Best Practice Decision Tree
• **Shared stateless service** → Fixed replicas + HPA
• **Shared service with predictable patterns** → Manual scaling
• **Per-user isolated service** → Dynamic deployment creation
• **Expensive resources with idle time** → Scale-to-zero approach






--------------

# Kubernetes Architecture

```
Kubernetes Cluster
├── Control Plane (Master Node)
│   ├── API Server
│   ├── etcd Database  
│   ├── Scheduler
│   └── Controller Manager
└── Worker Nodes (1 to N)
    ├── Kubelet
    ├── Container Runtime (Docker/containerd)
    ├── Kube-proxy
    └── Your Pods (Applications)
```


![Kubernetes Cluster Architecture](https://kubernetes.io/images/docs/kubernetes-cluster-architecture.svg)

## Control Plane Components (Master Node)

### API Server (kube-apiserver)
• **Role**: Central hub - all communication goes through here
• **Function**: REST API that validates and processes all requests
• **Clients**: kubectl, other K8s components, your applications
• **Authentication**: Handles user/service account verification

### etcd Database
• **Role**: Cluster's brain - stores all cluster state and configuration
• **Data**: Pod specs, services, secrets, configmaps, cluster metadata
• **Type**: Distributed key-value store, highly available
• **Critical**: If etcd dies, cluster loses all state

### Scheduler (kube-scheduler)
• **Role**: Decides which worker node should run new pods
• **Logic**: Considers resource requirements, node capacity, affinity rules
• **Process**: Watches for unscheduled pods → selects best node → updates etcd
• **Smart**: Balances load across nodes, respects constraints

### Controller Manager (kube-controller-manager)
• **Role**: Monitors cluster state and makes corrections
• **Controllers**: Deployment, ReplicaSet, Service, Node controllers
• **Function**: Ensures desired state matches actual state
• **Example**: If pod dies, controller creates replacement

## Worker Node Components

### Kubelet
• **Role**: Node agent - K8s representative on each worker node
• **Functions**: 
  - Receives pod specs from API server
  - Manages pod lifecycle (start, stop, health checks)
  - Reports node and pod status back to API server
  - Mounts volumes, manages secrets/configmaps
• **Communication**: Talks to API server and container runtime

### Container Runtime
• **Role**: Actually runs containers (your applications)
• **Options**: Docker, containerd, CRI-O
• **Interface**: Kubelet talks to runtime via Container Runtime Interface (CRI)
• **Functions**: Pull images, create/start/stop containers, manage container networking

### Kube-proxy
• **Role**: Network proxy - handles service networking
• **Function**: Implements K8s service concept on each node
• **Networking**: Routes traffic from services to correct pods
• **Load balancing**: Distributes requests across multiple pod replicas

### Pod Network (CNI)
• **Role**: Provides networking between pods across nodes
• **Examples**: Flannel, Calico, Weave Net
• **Function**: Assigns IP addresses to pods, enables pod-to-pod communication
• **Requirement**: All pods can communicate with all other pods

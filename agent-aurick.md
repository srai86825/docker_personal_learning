# Agent Architecture & Communication Guide

## System Overview

```

## System Flows & Use Cases

### Flow 1: User Starts Agent for Project

```
User Action: Opens project workspace
1. Frontend Request
   POST /api/projects/{projectId}/start-agent
   Headers: { Authorization: Bearer <user_token> }
    ↓
2. Main Backend Validation
   ├─ Check user permissions for project
   ├─ Verify user subscription status  
   └─ Check if user already has active agent for this project
    ↓
3. Resource Availability Check
   ├─ Check maxAgent limit (business rule)
   ├─ Check cluster resource availability
   ├─ Check machine capacity across nodes
   └─ Decision: Create, Queue, or Reject
    ↓
4A. If Resources Available → Create Agent
    ├─ Generate unique agentId
    ├─ Create K8s deployment + service
    ├─ Store agent metadata in database
    └─ Return agentId and connection details
    ↓
4B. If Resources Unavailable → Queue Request
    ├─ Add to pending queue with priority
    ├─ Return queue position and estimated wait time
    └─ Set up queue monitoring for user
    ↓
5. Agent Container Startup (7-18 seconds)
   ├─ Container pulls image and starts
   ├─ Internal API connects to main backend via WebSocket
   ├─ Browser_use and NoVNC services initialize
   └─ Agent sends "ready" status to main backend
    ↓
6. User Connection Established
   ├─ Frontend receives agent connection details
   ├─ User can access NoVNC for visual control
   └─ User can send commands via frontend → backend → agent
```

**Pseudocode:**
```javascript
// Main Backend - Agent Creation Flow
POST /api/projects/:projectId/start-agent {
  
  // Step 2: Validation
  validateUser(userId, projectId)
  existingAgent = getActiveAgent(userId, projectId)
  if (existingAgent) return existingAgent
  
  // Step 3: Resource Check
  resourceCheck = checkResourceAvailability(userId)
  
  if (resourceCheck.unavailable) {
    // Step 4B: Queue
    queuePosition = addToQueue(userId, projectId, userTier)
    return { status: 'queued', position, estimatedWait }
  }
  
  // Step 4A: Create Agent
  agentId = generateAgentId(userId, projectId)
  createKubernetesAgent(agentId, userId, projectId)
  storeAgentInDatabase(agentId, userId, projectId)
  
  return { agentId, status: 'creating', connections }
}

function checkResourceAvailability(userId) {
  // Business limit check (maxAgent parameter)
  userAgentCount = getUserActiveAgentCount(userId)
  maxAllowed = getMaxAgentsForUser(userId) // Based on subscription
  if (userAgentCount >= maxAllowed) {
    return { unavailable: true, reason: 'max_agents_exceeded' }
  }
  
  // Hardware resource check  
  clusterStatus = getClusterResourceStatus()
  if (clusterStatus.memoryPercent > 90 || clusterStatus.cpuPercent > 85) {
    return { unavailable: true, reason: 'insufficient_resources' }
  }
  
  return { available: true }
}
```

### Flow 2: Backend Decides to Terminate Agent

```
Trigger Conditions:
├─ User inactivity timeout (30+ minutes)
├─ User explicitly closes project
├─ User subscription expired
├─ Resource pressure (cluster >90% utilization)
├─ Scheduled maintenance
└─ Agent health check failures
    ↓
1. Main Backend Initiates Termination
   ├─ Log termination reason and timestamp
   └─ Mark agent as "terminating" in database
    ↓
2. Graceful Shutdown Sequence
   ├─ Send shutdown warning to user (if online)
   ├─ Give user 2-minute grace period to save work
   └─ Send graceful shutdown signal to agent
    ↓
3. Agent Cleanup
   ├─ Agent saves any in-progress work
   ├─ Agent closes browser sessions
   ├─ Agent disconnects from main backend
   └─ Agent container exits gracefully
    ↓
4. Kubernetes Cleanup
   ├─ Remove K8s deployment
   ├─ Remove K8s service
   └─ Clean up volumes (if configured)
    ↓
5. Resource Reallocation
   ├─ Update cluster resource tracking
   ├─ Process next item in queue (if any)
   └─ Notify waiting users of availability
    ↓
6. Database Cleanup
   ├─ Mark agent as "terminated"
   ├─ Update user session status
   └─ Log final resource usage
```

**Pseudocode:**
```javascript
function terminateAgent(agentId, reason, gracePeriod = 120000) {
  // Step 1: Mark as terminating
  updateAgentStatus(agentId, 'terminating', reason)
  
  // Step 2: Notify user if online
  if (reason !== 'user_requested') {
    notifyUser(agent.userId, 'agent_terminating', gracePeriod)
  }
  
  // Step 3: Graceful shutdown after grace period
  setTimeout(() => {
    try {
      sendToAgent(agentId, 'graceful_shutdown')
      waitForAgentShutdown(agentId, 30000)
    } catch {
      forceTermination(agentId)
    }
    
    // Step 4: K8s cleanup
    k8s.deleteDeployment(`agent-${agentId}`)
    k8s.deleteService(`agent-${agentId}-service`)
    
    // Step 5: Update database & process queue
    updateAgentStatus(agentId, 'terminated')
    processAgentQueue()
  }, gracePeriod)
}

// Auto-termination triggers
setInterval(() => {
  // Check for inactive agents (30+ min)
  inactiveAgents = getInactiveAgents(30 * 60 * 1000)
  inactiveAgents.forEach(agent => terminateAgent(agent.id, 'inactivity'))
  
  // Check resource pressure
  if (getClusterResourceUsage().memoryPercent > 90) {
    oldestAgents = getOldestAgents(5)
    oldestAgents.forEach(agent => terminateAgent(agent.id, 'resource_pressure'))
  }
}, 60000)
```

### Flow 3: Agent/Container Fails

```
Failure Detection:
├─ Container crash (exit code > 0)
├─ Health check failures (3 consecutive)
├─ WebSocket connection lost >2 minutes
├─ Node failure (machine goes down)
└─ Out of memory kill (OOMKilled)
    ↓
1. Kubernetes Detects Failure
   ├─ Pod status changes to "Failed" or "Unknown"
   └─ K8s generates event logs
    ↓
2. Main Backend Detects via Monitoring
   ├─ WebSocket disconnect event
   ├─ Health check monitoring alerts
   └─ K8s API watch events
    ↓
3. Determine Recovery Action
   ├─ If user still active → Restart agent
   ├─ If temporary failure → Auto-restart with backoff
   ├─ If persistent failure → Mark as failed, notify user
   └─ If node failure → Reschedule on different machine
    ↓
4A. Auto-Restart Flow
    ├─ Increment restart counter
    ├─ Apply exponential backoff delay
    ├─ Create new pod with same configuration
    └─ Update database with restart attempt
    ↓
4B. Permanent Failure Flow
    ├─ Mark agent as "failed" in database
    ├─ Notify user of failure with option to restart
    ├─ Clean up K8s resources
    └─ Log failure for analysis
    ↓
5. User Notification
   ├─ Real-time alert via WebSocket
   ├─ Email notification for critical failures
   └─ Option to restart or switch to different agent
```

**Pseudocode:**
```javascript
class AgentFailureHandler {
  
  handleAgentDisconnect(agentId) {
    // Give agent 2 minutes to reconnect
    setTimeout(() => {
      if (!isAgentConnected(agentId)) {
        handleAgentFailure(agentId, 'websocket_disconnect')
      }
    }, 120000)
  }
  
  handleAgentFailure(agentId, reason) {
    agent = getAgent(agentId)
    restartCount = agent.restartCount || 0
    
    // Max 3 restart attempts
    if (restartCount < 3 && shouldAutoRestart(reason)) {
      restartAgent(agentId, restartCount + 1)
    } else {
      markAgentAsFailed(agentId, reason)
    }
  }
  
  restartAgent(agentId, restartCount) {
    backoffDelay = Math.pow(2, restartCount) * 1000 // Exponential backoff
    
    setTimeout(() => {
      try {
        k8s.deleteDeployment(`agent-${agentId}`)
        k8s.createDeployment(generateAgentDeployment(agentId))
        updateAgentStatus(agentId, 'restarting', restartCount)
      } catch {
        markAgentAsFailed(agentId, 'restart_failed')
      }
    }, backoffDelay)
  }
  
  watchKubernetesPodEvents() {
    k8s.watch('/api/v1/pods', (type, pod) => {
      if (pod.metadata?.labels?.app === 'agent') {
        agentId = pod.metadata.labels.agentId
        
        if (type === 'DELETED' || pod.status?.phase === 'Failed') {
          handleAgentFailure(agentId, 'pod_failure')
        }
      }
    })
  }
}
```

### Flow 4: Resources Choked

```
Resource Pressure Detection:
├─ Cluster CPU usage >85%
├─ Cluster Memory usage >90%
├─ Individual node capacity reached
├─ Disk space <10% available
└─ Network bandwidth exhausted
    ↓
1. Monitoring System Alerts
   ├─ Prometheus/Grafana alerts trigger
   ├─ K8s resource quotas exceeded
   └─ Custom application metrics breach thresholds
    ↓
2. Immediate Response Actions
   ├─ Stop accepting new agent requests
   ├─ Add incoming requests to queue
   ├─ Scale out cluster (if auto-scaling enabled)
   └─ Alert operations team
    ↓
3. Resource Optimization
   ├─ Identify idle/low-usage agents
   ├─ Terminate agents with users offline >15 min
   ├─ Reduce resource limits for non-critical agents
   └─ Migrate agents to less loaded nodes
    ↓
4. Queue Management
   ├─ Process queue based on priority (paid users first)
   ├─ Provide accurate wait time estimates
   └─ Allow users to schedule agent start times
    ↓
5. Capacity Planning
   ├─ Trigger auto-scaling if configured
   ├─ Generate alerts for manual scaling
   └─ Log metrics for capacity planning
```

### Resource Availability Decision Engine

**Decision Priority Matrix:**
```
1. Business Rule (maxAgent) → If exceeded: REJECT (upgrade needed)
2. Hardware Resources → If choked: QUEUE (wait for resources)  
3. Node Capacity → If full: QUEUE (wait for space)
✅ If all pass: CREATE immediately
```

**Pseudocode:**
```javascript
class ResourceManager {
  maxAgentLimits = {
    free_tier: 1, basic_plan: 3, premium_plan: 10, enterprise: 50
  }
  
  clusterThresholds = {
    cpu_percent: 85, memory_percent: 90, disk_percent: 90
  }
  
  canCreateAgent(userId, projectId) {
    // Check 1: Business rule (maxAgent parameter)
    userTier = getUserSubscriptionTier(userId)
    currentAgentCount = getUserActiveAgentCount(userId)
    maxAllowed = this.maxAgentLimits[userTier]
    
    if (currentAgentCount >= maxAllowed) {
      return {
        canCreate: false,
        reason: 'max_agents_exceeded',
        action: 'upgrade_subscription'
      }
    }
    
    // Check 2: Cluster resource availability
    clusterStatus = getClusterResourceStatus()
    if (isResourceChoked(clusterStatus)) {
      return {
        canCreate: false,
        reason: 'insufficient_cluster_resources', 
        action: 'queue_request'
      }
    }
    
    // Check 3: Node capacity for scheduling
    if (!canScheduleNewPod()) {
      return {
        canCreate: false,
        reason: 'no_suitable_node',
        action: 'queue_request'
      }
    }
    
    return { canCreate: true }
  }
  
  isResourceChoked(clusterStatus) {
    return (
      clusterStatus.cpu_percent > this.clusterThresholds.cpu_percent ||
      clusterStatus.memory_percent > this.clusterThresholds.memory_percent ||
      clusterStatus.availableNodes === 0
    )
  }
}
```

### Queue Management System

**Queue Logic:**
- **Priority Order**: Enterprise → Premium → Basic → Free  
- **Wait Time**: Based on average agent lifespan (45min) + queue position
- **Max Queue Size**: 1000 requests
- **Processing**: Auto-process when resources free up

**Pseudocode:**
```javascript
class AgentQueueManager {
  queue = []
  maxQueueSize = 1000
  priorities = { enterprise: 1, premium: 2, basic: 3, free: 4 }
  
  addToQueue(userId, projectId, userTier) {
    if (this.queue.length >= this.maxQueueSize) {
      throw new Error('Queue is full')
    }
    
    queueItem = {
      id: generateId(),
      userId, projectId,
      priority: this.priorities[userTier],
      timestamp: Date.now(),
      estimatedWaitMinutes: calculateWaitTime()
    }
    
    // Insert based on priority (binary search)
    insertIndex = findInsertPosition(queueItem)
    this.queue.splice(insertIndex, 0, queueItem)
    
    // Store in database for persistence
    db.agentQueue.create(queueItem)
    updateWaitTimes()
    
    return { position: insertIndex + 1, estimatedMinutes: queueItem.estimatedWaitMinutes }
  }
  
  processQueue() {
    while (this.queue.length > 0) {
      resourceCheck = resourceManager.canCreateAgent(this.queue[0].userId, this.queue[0].projectId)
      
      if (!resourceCheck.canCreate) break // Still no resources
      
      // Process next item
      nextItem = this.queue.shift()
      createAgentFromQueue(nextItem)
      db.agentQueue.delete(nextItem.id)
    }
    
    updateWaitTimes()
  }
  
  calculateWaitTime() {
    averageAgentLifespanMinutes = 45
    currentActiveAgents = getCurrentActiveAgentCount()
    queuePosition = this.queue.length + 1
    
    estimatedTurnoverRate = currentActiveAgents / averageAgentLifespanMinutes
    waitMinutes = queuePosition / Math.max(estimatedTurnoverRate, 0.1)
    
    return Math.ceil(waitMinutes)
  }
}
```

### Complete Decision Flow Integration

**API Endpoint Logic:**
```javascript
POST /api/projects/:projectId/start-agent {
  userId = req.user.id
  userTier = getUserSubscriptionTier(userId)
  
  canCreate = resourceManager.canCreateAgent(userId, projectId)
  
  if (canCreate.canCreate) {
    // Create immediately
    agent = createAgent(userId, projectId)
    return { status: 'created', agent }
  } else {
    if (canCreate.reason === 'max_agents_exceeded') {
      // Business limit - cannot queue
      return { 
        status: 'rejected', 
        reason: canCreate.reason,
        action: 'upgrade_subscription'
      }
    } else {
      // Resource limit - add to queue  
      queueResult = queueManager.addToQueue(userId, projectId, userTier)
      return {
        status: 'queued',
        position: queueResult.position,
        estimatedWaitMinutes: queueResult.estimatedMinutes
      }
    }
  }
}
```

**Key Decision Points:**

| Condition | maxAgent Limit | Hardware Resources | Result |
|-----------|----------------|-------------------|---------|
| ✅ Under limit | ✅ Available | **CREATE** immediately |
| ✅ Under limit | ❌ Choked | **QUEUE** (wait for resources) |
| ❌ Over limit | ✅ Available | **REJECT** (upgrade needed) |
| ❌ Over limit | ❌ Choked | **REJECT** (upgrade needed) |

**Resource Thresholds:**
- **CPU >85%** = Queue new requests, continue existing
- **Memory >90%** = Queue new + terminate idle agents  
- **Disk >90%** = Emergency cleanup + queue all requests
Main Backend Server (Not Containerized)
         ↕ (Socket Updates & API Requests)
    Load Balancer / Service Discovery
         ↕
┌─────────────────────────────────────────┐
│ Kubernetes Cluster (2-3 Machines)       │
│                                         │
│  Agent Pod 1    Agent Pod 2    Agent N  │
│ ┌─────────────┐ ┌─────────────┐ ┌─────┐ │
│ │Internal API │ │Internal API │ │ ... │ │
│ │Browser Use  │ │Browser Use  │ │     │ │
│ │NoVNC        │ │NoVNC        │ │     │ │
│ └─────────────┘ └─────────────┘ └─────┘ │
└─────────────────────────────────────────┘
```

## User Flow & Scaling

```
User 1 joins → K8s creates Agent Pod 1
User 2 joins → K8s creates Agent Pod 2  
User 1 leaves → K8s destroys Agent Pod 1
User 3 joins → K8s creates Agent Pod 3
```

Each agent pod contains: **Internal API + Browser Use + NoVNC**

## Technology Stack

### Core Technologies
- **Docker**: Containerize agent components
- **Kubernetes**: Orchestrate across multiple machines
- **Load Balancer**: Route traffic to correct agent instances
- **WebSockets**: Real-time communication between agents and main backend

### Agent Container Stack
```dockerfile
# Single container with all agent components
FROM ubuntu:20.04
RUN install nodejs          # For internal API
RUN install browser_use     # Browser automation
RUN install novnc          # Remote desktop access
COPY internal_api_code /app
CMD ["start_all_services.sh"]
```

### Main Backend (Not Containerized)
- **Language**: Your existing backend (Node.js/Python/etc.)
- **Location**: External server/cloud instance
- **Role**: User management, project coordination, agent orchestration

## Communication Architecture

### 1. Internal API → Main Backend (Socket Updates)

```javascript
// Inside each agent's internal API
const io = require('socket.io-client');
const socket = io.connect('https://your-main-backend.com');

// Send updates to main backend
socket.emit('agent_status', {
  agentId: process.env.AGENT_ID,
  userId: process.env.USER_ID,
  projectId: process.env.PROJECT_ID,
  status: 'working',
  data: browserActionResults
});
```

### 2. Main Backend → Internal APIs (API Requests)

**Challenge**: How to send requests to specific agent among N instances?

**Solution Options**:

#### Option A: Kubernetes Service + Agent Registry
```yaml
# K8s Service exposes all agents
apiVersion: v1
kind: Service
metadata:
  name: agent-service
spec:
  selector:
    app: agent
  ports:
  - port: 8080
    targetPort: 8080
```

```javascript
// Main backend maintains agent registry
const agentRegistry = {
  'user1-project1-agent1': 'http://agent-service:8080/user1-project1-agent1',
  'user2-project1-agent1': 'http://agent-service:8080/user2-project1-agent1'
};

// Send request to specific agent
async function sendToAgent(agentId, command) {
  const agentUrl = agentRegistry[agentId];
  return await fetch(`${agentUrl}/execute`, {
    method: 'POST',
    body: JSON.stringify(command)
  });
}
```

#### Option B: Individual Agent Services (Recommended)
```yaml
# Each agent gets unique service
apiVersion: v1
kind: Service
metadata:
  name: agent-user1-project1
spec:
  selector:
    app: agent
    userId: user1
    projectId: project1
```

```javascript
// Main backend connects to specific agent services
const agentUrl = `http://agent-${userId}-${projectId}.default.svc.cluster.local:8080`;
```

## Implementation Details

### Agent Container Environment
```dockerfile
# Environment variables for each agent
ENV AGENT_ID=user1-project1-agent1
ENV USER_ID=user1  
ENV PROJECT_ID=project1
ENV MAIN_BACKEND_URL=https://your-main-backend.com
ENV AGENT_PORT=8080
ENV NOVNC_PORT=6080
```

### Agent Internal API Structure
```javascript
// internal_api.js
const express = require('express');
const io = require('socket.io-client');

const app = express();
const backendSocket = io.connect(process.env.MAIN_BACKEND_URL);

// API endpoint for receiving commands from main backend
app.post('/execute', async (req, res) => {
  const { command, parameters } = req.body;
  
  // Execute browser automation
  const result = await executeBrowserCommand(command, parameters);
  
  // Send update back via socket
  backendSocket.emit('command_result', {
    agentId: process.env.AGENT_ID,
    result: result
  });
  
  res.json({ status: 'executed' });
});

app.listen(process.env.AGENT_PORT);
```

### Main Backend Changes

#### Agent Lifecycle Management
```javascript
// When user joins project
async function createAgent(userId, projectId) {
  const agentId = `${userId}-${projectId}-${Date.now()}`;
  
  // Create K8s deployment for this agent
  await k8s.createDeployment({
    name: `agent-${agentId}`,
    image: 'your-agent:latest',
    env: {
      AGENT_ID: agentId,
      USER_ID: userId,
      PROJECT_ID: projectId,
      MAIN_BACKEND_URL: process.env.BACKEND_URL
    }
  });
  
  // Store agent info
  await db.agents.create({ agentId, userId, projectId, status: 'starting' });
  
  return agentId;
}

// When user leaves
async function destroyAgent(agentId) {
  await k8s.deleteDeployment(`agent-${agentId}`);
  await db.agents.delete({ agentId });
}
```

#### Socket Handler for Agent Updates
```javascript
// Socket.io server on main backend
io.on('connection', (socket) => {
  
  socket.on('agent_status', (data) => {
    // Update agent status in database
    updateAgentStatus(data.agentId, data.status);
    
    // Notify frontend users
    notifyUser(data.userId, data);
  });
  
  socket.on('command_result', (data) => {
    // Process command results
    handleCommandResult(data.agentId, data.result);
  });
});
```

## Kubernetes Configuration

### Agent Deployment Template
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: agent-${AGENT_ID}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: agent
      agentId: ${AGENT_ID}
  template:
    metadata:
      labels:
        app: agent
        agentId: ${AGENT_ID}
        userId: ${USER_ID}
        projectId: ${PROJECT_ID}
    spec:
      containers:
      - name: agent
        image: your-agent:latest
        ports:
        - containerPort: 8080  # Internal API
        - containerPort: 6080  # NoVNC
        env:
        - name: AGENT_ID
          value: ${AGENT_ID}
        - name: USER_ID
          value: ${USER_ID}
        - name: PROJECT_ID
          value: ${PROJECT_ID}
        - name: MAIN_BACKEND_URL
          value: "https://your-main-backend.com"
```

### Service for External Access
```yaml
apiVersion: v1
kind: Service
metadata:
  name: agent-${AGENT_ID}-service
spec:
  selector:
    agentId: ${AGENT_ID}
  ports:
  - name: api
    port: 8080
    targetPort: 8080
  - name: novnc
    port: 6080
    targetPort: 6080
  type: LoadBalancer  # For external access to NoVNC
```

## Main Backend Containerization

### Is It Mandatory? **NO**

**Pros of keeping main backend separate**:
- ✅ No need to rebuild/redeploy existing code
- ✅ Can scale independently  
- ✅ Simpler networking (agents connect to fixed URL)
- ✅ Less complex migration

**Communication Setup**:
```javascript
// Main backend exposes endpoints for agents
app.post('/agent-register', (req, res) => {
  // Register new agent when it starts
});

app.post('/agent-heartbeat', (req, res) => {
  // Health check from agents
});

// Agents connect via external URL
const MAIN_BACKEND_URL = 'https://your-main-backend.com';
```

### If You Do Containerize Later
```yaml
# Optional: Main backend in same cluster
apiVersion: apps/v1
kind: Deployment
metadata:
  name: main-backend
spec:
  replicas: 1
  template:
    spec:
      containers:
      - name: backend
        image: your-backend:latest
        ports:
        - containerPort: 4000
---
apiVersion: v1
kind: Service
metadata:
  name: main-backend-service
spec:
  selector:
    app: main-backend
  ports:
  - port: 4000
  type: LoadBalancer
```

## Deployment Steps

### 1. Prepare Agent Container
```bash
# Build agent image
docker build -t your-agent:latest .
docker push your-registry/your-agent:latest
```

### 2. Setup Kubernetes Cluster
```bash
# Setup cluster on 2-3 machines
kubeadm init
kubeadm join <cluster-token>

# Verify nodes
kubectl get nodes
```

### 3. Deploy Agent Management
```javascript
// Add to main backend
const k8s = require('@kubernetes/client-node');

async function deployAgent(userId, projectId) {
  // Create K8s resources dynamically
  const deployment = generateAgentDeployment(userId, projectId);
  await k8s.createDeployment(deployment);
}
```

### 4. Setup Communication
```javascript
// Agent connects to main backend on startup
const socket = io.connect(process.env.MAIN_BACKEND_URL);
socket.emit('agent_online', { agentId: process.env.AGENT_ID });
```

## Scaling & Management

### Automatic Scaling
```bash
# Scale based on active users
kubectl get deployments | grep agent | wc -l   # Count active agents

# Auto-scale cluster nodes
kubectl apply -f cluster-autoscaler.yaml
```

### Monitoring
```javascript
// Main backend tracks agent health
setInterval(() => {
  agents.forEach(agent => {
    pingAgent(agent.id);
  });
}, 30000);
```

### Resource Limits
```yaml
# Agent resource constraints
resources:
  requests:
    memory: "512Mi"
    cpu: "500m"
  limits:
    memory: "1Gi" 
    cpu: "1000m"
```

## Network Architecture Summary

```
Internet
    ↓
Main Backend Server (External)
    ↓ (WebSocket/HTTP)
Load Balancer
    ↓
Kubernetes Cluster
    ↓
Agent Pods (Internal API + Browser + NoVNC)
```

**Key Points**:
- Main backend stays external (no containerization needed)
- Agents connect to main backend via external URL/IP
- K8s handles agent distribution across machines
- Each agent is isolated but can communicate with main backend
- NoVNC accessible via LoadBalancer for user access

This architecture gives you dynamic scaling, multi-machine distribution, and maintains your existing main backend without modification!

## Frequently Asked Questions (FAQs)

### Hardware & Infrastructure

**Q: What are the minimum hardware requirements per machine?**
```
Minimum per machine:
- CPU: 4+ cores
- RAM: 8GB+ 
- Storage: 50GB+ SSD
- Network: 1Gbps+

Recommended per machine:
- CPU: 8+ cores (16+ for heavy usage)
- RAM: 16GB+ (32GB+ for many agents)
- Storage: 100GB+ NVMe SSD
- Network: 10Gbps+
```

**Q: How many agent instances can run per machine?**
```
Conservative estimate:
- Light agents (simple browser tasks): 10-20 per machine
- Heavy agents (complex automation): 5-10 per machine
- With NoVNC active: 5-15 per machine

Example with 16GB RAM machine:
- Each agent: ~1GB RAM
- OS overhead: ~2GB
- Available: ~14GB = 14 agents max
```

**Q: Can I mix different machine sizes in the cluster?**
**A:** Yes! K8s automatically considers machine capacity:
```bash
# Machine 1: 8GB RAM → K8s schedules 8 agents max
# Machine 2: 32GB RAM → K8s schedules 30 agents max  
# Machine 3: 16GB RAM → K8s schedules 15 agents max
```

**Q: What cloud providers work best?**
```
Recommended:
- AWS: EKS (managed K8s) + EC2 instances
- Google Cloud: GKE + Compute Engine
- DigitalOcean: DOKS + Droplets  
- Azure: AKS + Virtual Machines

Self-hosted:
- Any Ubuntu/CentOS servers
- Docker + Kubernetes installed
```

### Technology Stack & Compatibility

**Q: What if my main backend is in Python/Java/C#, not Node.js?**
**A:** No problem! Communication is language-agnostic:
```python
# Python main backend
import socketio
import requests

# Send to agent
response = requests.post(f'http://agent-{agent_id}:8080/execute', 
                        json={'command': 'click_button'})

# Receive from agent  
sio = socketio.Server()
@sio.on('agent_status')
def handle_agent_update(sid, data):
    print(f"Agent {data['agentId']} status: {data['status']}")
```

**Q: Can agents run on Windows containers?**
**A:** Yes, but Linux is recommended:
```yaml
# Windows node
nodeSelector:
  kubernetes.io/os: windows

# Linux node (recommended)
nodeSelector:
  kubernetes.io/os: linux
```

**Q: What browsers work with browser_use in containers?**
```
Supported browsers:
- Chrome/Chromium: ✅ Best support
- Firefox: ✅ Good support  
- Edge: ✅ Limited support
- Safari: ❌ Not available in containers

Recommended setup:
- Headless Chrome for automation
- NoVNC with desktop for debugging
```

### Timing & Performance

**Q: How long does it take to spin up a new agent?**
```
Typical timeline:
- K8s pod creation: 2-5 seconds
- Container startup: 3-8 seconds  
- Service initialization: 2-5 seconds
- Total cold start: 7-18 seconds

With image pre-pulled:
- Total time: 3-8 seconds

Optimization techniques:
- Pre-pull images on all nodes
- Use smaller base images (Alpine)
- Optimize container startup scripts
```

**Q: How long to spin down an agent?**
```
Graceful shutdown:
- Signal sent to container: 0.1 seconds
- App cleanup time: 1-3 seconds
- K8s cleanup: 1-2 seconds
- Total: 2-5 seconds

Force shutdown (if hung):
- K8s kills after: 30 seconds (configurable)
```

**Q: Can I speed up agent startup?**
```yaml
# Pre-pull images
spec:
  containers:
  - name: agent
    image: your-agent:latest
    imagePullPolicy: Always  # or IfNotPresent

# Resource requests for faster scheduling
resources:
  requests:
    cpu: 500m
    memory: 512Mi

# Readiness probe
readinessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 5
```

### Scaling & Load Balancing

**Q: How does K8s decide which machine to put new agents on?**
**A:** K8s scheduler considers multiple factors:
```
Scheduling factors:
1. Available CPU/RAM on each node
2. Current pod count per node
3. Node affinity rules
4. Resource requests vs limits

Example:
- Machine 1: 80% CPU used → Lower priority
- Machine 2: 30% CPU used → Higher priority
- Machine 3: Full → Skipped
```

**Q: Can I control which machine gets which agent?**
```yaml
# Pin to specific machine
spec:
  nodeSelector:
    kubernetes.io/hostname: machine-2

# Spread across machines
spec:
  topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: kubernetes.io/hostname
    whenUnsatisfiable: DoNotSchedule

# Prefer certain machines
spec:
  affinity:
    nodeAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        preference:
          matchExpressions:
          - key: machine-type
            operator: In
            values: ["high-memory"]
```

**Q: What happens if one machine goes down?**
**A:** K8s automatically handles failures:
```
Failure scenario:
1. Machine 2 goes down
2. K8s detects node failure (30-60 seconds)
3. Agents on Machine 2 marked as failed
4. New agents automatically scheduled on Machine 1 & 3
5. Users experience brief interruption (1-2 minutes)

High availability setup:
- Run agents across multiple machines
- Use persistent volumes for critical data
- Implement health checks and auto-restart
```

### When to Spin Up/Down

**Q: When should I create new agent instances?**
```javascript
// Trigger conditions
const shouldCreateAgent = (
  user.joinedProject && 
  !user.hasActiveAgent &&
  user.subscriptionActive &&
  cluster.hasAvailableResources
);

// Business logic examples
- User opens project workspace
- User requests browser automation
- User starts VNC session
- Scheduled task begins
```

**Q: When should I destroy agent instances?**
```javascript
// Trigger conditions  
const shouldDestroyAgent = (
  user.leftProject ||
  user.inactiveFor > 30_MINUTES ||
  user.subscriptionExpired ||
  cluster.resourcePressure > 90%
);

// Graceful shutdown sequence
1. Save any in-progress work
2. Notify user of shutdown
3. Close browser sessions
4. Terminate container
```

**Q: How to handle idle agents consuming resources?**
```yaml
# Auto-scale down based on CPU usage
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: agent-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: agent-deployment
  minReplicas: 0
  maxReplicas: 100
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 50
```

### Resource Management

**Q: How to prevent one user from consuming all resources?**
```yaml
# Resource quotas per namespace
apiVersion: v1
kind: ResourceQuota
metadata:
  name: user-quota
  namespace: user-workspace
spec:
  hard:
    requests.cpu: "4"
    requests.memory: 8Gi
    persistentvolumeclaims: "10"
    pods: "10"
```

```javascript
// Application-level limits
const userLimits = {
  maxAgentsPerUser: 5,
  maxAgentsPerProject: 10,
  cpuLimitPerAgent: '1000m',
  memoryLimitPerAgent: '1Gi'
};
```

**Q: How to monitor resource usage?**
```bash
# Node resource usage
kubectl top nodes

# Pod resource usage
kubectl top pods

# Detailed metrics
kubectl describe node machine-1

# Custom monitoring
kubectl apply -f prometheus-monitoring.yaml
```

### Networking & Security

**Q: How do agents communicate securely with main backend?**
```javascript
// HTTPS + authentication
const socket = io.connect('https://main-backend.com', {
  auth: {
    token: process.env.AGENT_TOKEN,
    agentId: process.env.AGENT_ID
  },
  secure: true,
  rejectUnauthorized: true
});
```

**Q: Can users access other users' agents?**
**A:** No, with proper isolation:
```yaml
# Network policies
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: agent-isolation
spec:
  podSelector:
    matchLabels:
      app: agent
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: main-backend
```

### Cost Optimization

**Q: How to minimize infrastructure costs?**
```
Cost optimization strategies:

1. Use spot/preemptible instances (30-70% cheaper)
2. Auto-scale down during off-hours
3. Use smaller base images (Alpine vs Ubuntu)
4. Implement resource limits per agent
5. Share GPU resources across agents
6. Use local storage vs cloud storage where possible

Example savings:
- Spot instances: $100/month → $30/month
- Auto-scaling: 24/7 → 12hrs/day = 50% savings
- Optimized images: 1GB → 200MB = faster startup
```

**Q: What's the break-even point vs traditional VMs?**
```
Traditional approach:
- 1 VM per user = $50/month × 100 users = $5000/month
- 70% VM utilization waste = $3500 wasted

Container approach:  
- 3 machines = $500/month
- Dynamic scaling = 95% utilization
- Total cost = $525/month

Break-even: ~10+ concurrent users
```

### Troubleshooting

**Q: What if an agent becomes unresponsive?**
```javascript
// Health check implementation
app.get('/health', (req, res) => {
  const status = {
    status: 'healthy',
    uptime: process.uptime(),
    memory: process.memoryUsage(),
    browserActive: browser.isConnected()
  };
  res.json(status);
});

// Auto-restart unresponsive agents
if (agent.lastHeartbeat < Date.now() - 60000) {
  restartAgent(agent.id);
}
```

**Q: How to debug agent startup failures?**
```bash
# Check pod status
kubectl describe pod agent-xyz

# View logs
kubectl logs agent-xyz

# Get shell access
kubectl exec -it agent-xyz -- /bin/bash

# Check resource constraints
kubectl top pod agent-xyz
```

**Q: What if the cluster runs out of resources?**
```javascript
// Implement queue system
const agentQueue = [];

async function requestAgent(userId, projectId) {
  if (cluster.availableResources < minimumRequired) {
    agentQueue.push({ userId, projectId, timestamp: Date.now() });
    return { status: 'queued', position: agentQueue.length };
  }
  
  return await createAgent(userId, projectId);
}
```
# Architecture

This document walks through the platform end to end: a change lands in
GitHub, the pipeline scans and plans it, an approved apply reaches AWS, and
the running system feeds observability data back out. Each diagram covers
one layer; together they're the full picture the [README](../README.md)
summarizes in one box.

## 1. End-to-end flow

```mermaid
flowchart TB
    DEV[Developer] -->|push / PR| REPO[(GitHub Repository)]

    subgraph CI["GitHub Actions"]
        direction TB
        LINT[Lint<br/>fmt, validate, tflint]
        SCAN[Security Scan<br/>tfsec + checkov + gitleaks]
        PLAN[terraform plan<br/>staging + production]
        APPROVE{{Manual Approval<br/>production Environment}}
        APPLY[terraform apply]
        DBUILD[Docker Build]
        DSCAN[Trivy Image Scan]
        DPUSH[Push to ECR]
        DDEPLOY[Deploy to ECS]

        LINT --> SCAN --> PLAN --> APPROVE --> APPLY
        DBUILD --> DSCAN --> DPUSH --> DDEPLOY
    end

    REPO --> CI
    APPLY -- "OIDC: short-lived AWS credentials" --> AWSCLOUD
    DDEPLOY -- "OIDC: short-lived AWS credentials" --> AWSCLOUD

    subgraph AWSCLOUD["AWS Account"]
        direction TB
        NET["Network layer<br/>(§3 - VPC, subnets, routing)"]
        RUN["Runtime layer<br/>(§3 - ALB, ECS Fargate, ECR)"]
        OBS["Observability layer<br/>(§5 - CloudWatch, CloudTrail, SNS)"]

        NET --> RUN
        RUN --> OBS
    end

    OBS -.->|alerts| ONCALL[("On-call<br/>(email via SNS)")]
    USER([End user]) -->|HTTPS| RUN
```

## 2. CI/CD pipeline detail

Two independent workflows, triggered by what changed - infrastructure
(`environments/`, `modules/`) or application code (`app/`).

```mermaid
flowchart LR
    subgraph TFPIPE["terraform-pipeline.yml"]
        direction TB
        T1[Lint] --> T2[Security Scan] --> T3["Plan<br/>(staging & production)"]
        T3 --> T4["Apply staging<br/>(auto)"]
        T3 --> T5{{"GitHub Environment:<br/>production<br/>required reviewers"}}
        T5 --> T6["Apply production"]
    end

    subgraph DOCKERPIPE["docker-build-scan.yml"]
        direction TB
        D1[Build image] --> D2["Trivy scan<br/>(CRITICAL/HIGH = hard fail)"]
        D2 --> D3{{"pull_request?"}}
        D3 -->|yes: stop here| D3END[No AWS access]
        D3 -->|no| D4[Push to ECR]
        D4 --> D5["Render + deploy<br/>ECS task definition"]
    end

    TRIGGER1["Push/PR touching<br/>modules/** or environments/**"] --> TFPIPE
    TRIGGER2["Push/PR touching<br/>app/**"] --> DOCKERPIPE
```

Trigger conditions and gates, precisely:

| Stage | Runs on | Gate |
|---|---|---|
| Lint, Security Scan, Plan | every PR and push to `main` | must pass to proceed |
| Apply staging | push to `main` only | none (staging is disposable, see `environments/staging/README` note in the root README) |
| Apply production | push to `main` only, after staging succeeds | GitHub Environment `production` required-reviewers rule |
| Docker build + Trivy scan | every PR and push touching `app/**` | Trivy CRITICAL/HIGH = hard fail |
| Push to ECR + deploy | push to `main` (→ staging) or manual dispatch (→ either) | same production Environment gate when targeting production |

## 3. Network & runtime architecture

What `modules/vpc`, `modules/security` and `modules/compute` actually build,
for one environment (staging shown; production is the same shape with a
NAT Gateway per AZ instead of one shared, per `single_nat_gateway`).

```mermaid
flowchart TB
    INTERNET([Internet]) --> IGW[Internet Gateway]

    subgraph VPC["VPC - modules/vpc (10.0.0.0/16)"]
        direction TB
        IGW --> PUBRT[Public Route Table]

        subgraph AZA["Availability Zone A"]
            direction TB
            PUBA["Public Subnet<br/>10.0.0.0/24"]
            PRIVA["Private Subnet<br/>10.0.10.0/24"]
        end

        subgraph AZB["Availability Zone B"]
            direction TB
            PUBB["Public Subnet<br/>10.0.1.0/24"]
            PRIVB["Private Subnet<br/>10.0.11.0/24"]
        end

        PUBRT --> PUBA
        PUBRT --> PUBB

        NAT["NAT Gateway<br/>(in a public subnet)"]
        PUBA --> NAT
        PRIVRT[Private Route Table] --> NAT
        PRIVRT -.-> PRIVA
        PRIVRT -.-> PRIVB

        ALB["Application Load Balancer<br/>modules/compute<br/>SG: alb-sg (80/443 in)"]
        PUBA --- ALB
        PUBB --- ALB

        subgraph FARGATE["ECS Fargate Service - modules/compute"]
            direction LR
            TASK1["Task<br/>SG: ecs-tasks-sg<br/>(ALB only, in)"]
            TASK2["Task<br/>SG: ecs-tasks-sg"]
        end
        PRIVA --- TASK1
        PRIVB --- TASK2

        ALB -->|"container_port"| TASK1
        ALB -->|"container_port"| TASK2
        TASK1 -.->|"443/tcp via NAT<br/>(image pulls, logs, APIs)"| NAT
        TASK2 -.->|"443/tcp via NAT"| NAT
    end

    ECR[("ECR<br/>scan-on-push, KMS-encrypted")] -.->|pull image| TASK1
    ECR -.->|pull image| TASK2

    FLOWLOGS["VPC Flow Logs<br/>-> CloudWatch Logs (KMS)"] -.-> VPC
```

Two independent layers of network control, both defined in
`modules/security`: **Security Groups** (stateful, resource-level - the
primary control: ECS tasks are reachable only from the ALB, on the
container port, full stop) and **NACLs** (stateless, subnet-level -
defense in depth on top of that). Neither ECS task ever has a public IP;
every inbound path runs through the ALB.

## 4. Identity: how CI reaches AWS

No AWS access keys exist anywhere in GitHub. Every workflow run exchanges a
short-lived OIDC token for AWS credentials, scoped to exactly the role its
job is allowed to assume - see `bootstrap/github-oidc/`.

```mermaid
sequenceDiagram
    participant Job as GitHub Actions job
    participant GH as GitHub OIDC Provider
    participant STS as AWS STS
    participant IAM as AWS IAM Role
    participant API as AWS APIs (EC2, ECS, S3, ...)

    Job->>GH: Request OIDC token<br/>(claims: repo, ref, environment)
    GH-->>Job: Signed JWT
    Job->>STS: AssumeRoleWithWebIdentity(JWT)
    STS->>IAM: Check trust policy:<br/>does "sub" claim match?
    Note over IAM: plan role: sub = repo:org/repo:*<br/>staging role: sub = repo:org/repo:environment:staging<br/>production role: sub = repo:org/repo:environment:production
    IAM-->>STS: Trust OK
    STS-->>Job: Short-lived credentials (~1h)
    Job->>API: terraform plan/apply,<br/>docker push, ecs update-service
```

A job can only ever obtain production credentials by explicitly declaring
`environment: production` - which is the same job GitHub's own
required-reviewers protection rule pauses for approval. The approval gate
and the credential scope are the same mechanism, not two things that could
drift apart.

## 5. Observability & security event flow

```mermaid
flowchart TB
    subgraph SOURCES["Signal sources"]
        direction LR
        ECSMETRICS["ECS metrics<br/>CPU, memory, task count"]
        ALBMETRICS["ALB metrics<br/>requests, 5xx, latency, host health"]
        CLOUDTRAIL["CloudTrail<br/>every AWS API call, account-wide"]
    end

    ECSMETRICS --> DASH["CloudWatch Dashboard<br/>modules/monitoring"]
    ALBMETRICS --> DASH

    ECSMETRICS --> ALARM1["Alarm: ECS CPU high"]
    ALBMETRICS --> ALARM2["Alarm: ALB 5xx rate"]
    ALBMETRICS --> ALARM3["Alarm: unhealthy hosts"]

    CLOUDTRAIL --> S3TRAIL[("S3 - CloudTrail archive<br/>KMS-encrypted, versioned")]
    CLOUDTRAIL --> CWLOGS["CloudWatch Logs<br/>(CloudTrail log group)"]

    CWLOGS --> MF1["Metric filter:<br/>unauthorized API calls"]
    CWLOGS --> MF2["Metric filter:<br/>root account usage"]
    CWLOGS --> MF3["Metric filter:<br/>IAM policy changes"]
    CWLOGS --> MF4["Metric filter:<br/>Security Group changes"]
    CWLOGS --> MF5["Metric filter:<br/>NACL changes"]
    CWLOGS --> MF6["Metric filter:<br/>CloudTrail config changes"]
    CWLOGS --> MF7["Metric filter:<br/>console sign-in failures"]

    MF1 & MF2 & MF3 & MF4 & MF5 & MF6 & MF7 --> CISALARMS["CIS-style security alarms"]

    ALARM1 & ALARM2 & ALARM3 & CISALARMS --> SNS["SNS Topic<br/>KMS-encrypted"]
    SNS --> EMAIL[("Email subscriber<br/>(alert_email)")]

    CLOUDTRAIL -.->|"log delivery notification"| SNS
```

`staging` and `production` share one CloudTrail trail, owned by
`production` (`enable_cloudtrail = true`) - CloudTrail is an account-level,
multi-region control, so creating one per environment would just produce
two overlapping trails billing and alerting on the same account activity.
Every other resource here (dashboards, ECS/ALB alarms, the SNS topic) is
per-environment. See `modules/monitoring/README.md` for the full reasoning.

## Module responsibility map

| Module | Owns | Does not own |
|---|---|---|
| `modules/vpc` | VPC, subnets, routing, NAT/IGW, Flow Logs | Security Groups, NACLs (→ `modules/security`) |
| `modules/security` | Security Groups, NACLs | The resources that use them (→ `modules/compute`) |
| `modules/compute` | ALB, ECS cluster/service/task, ECR, task IAM roles | Networking (consumes `modules/vpc` / `modules/security` outputs) |
| `modules/monitoring` | Dashboards, alarms, CloudTrail, SNS | Nothing upstream - it only reads metrics/logs the other modules emit |

`environments/staging` and `environments/production` are the only places
that wire all four together - see either one's `main.tf` for the concrete
call graph.

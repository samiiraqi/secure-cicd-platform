# app/ - demo application

A minimal Express app that exists to give the pipeline something real to
build, scan, and deploy: `GET /health` (used by the ALB target group and
the Docker `HEALTHCHECK`) and `GET /` (returns which environment it's
running in).

This is intentionally simple - the point of this directory is to
demonstrate the container half of the pipeline (`.github/workflows/docker-build-scan.yml`):
build → Trivy scan → push to ECR → roll the ECS service. Replace it with
your real application; keep the `/health` endpoint (or update
`health_check_path` / the Dockerfile `HEALTHCHECK` to match your app's).

## Local development

```bash
npm install
npm start        # listens on :8080 (PORT env var to override)
npm test
```

## Docker

```bash
docker build -t secure-cicd-demo-app .
docker run -p 8080:8080 secure-cicd-demo-app
curl http://localhost:8080/health
```

## Security notes

- Multi-stage build; the final image ships only production dependencies
  and application source, no build tooling.
- Runs as the non-root `node` user (built into the official Node image),
  not root.
- Pinned base image tag (`node:20.18.1-alpine3.20`), not `:latest`.
- `readonlyRootFilesystem = true` on the ECS task definition
  (`modules/compute`) - the app writes nothing to disk, so this works
  without extra volume mounts.
- Scanned by Trivy in CI before every push to ECR - see
  `.github/workflows/docker-build-scan.yml`.

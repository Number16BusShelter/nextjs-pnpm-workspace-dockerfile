
# Advance Multi-stage Dockerfile for deploying Next.js applications in a PNPM workspace (monorepo)

This project provides a production-grade multi-stage Dockerfile setup designed for Next.js services running inside a `pnpm` monorepo (workspace).

- Scoped builds for isolated services
- Workspace package utilization
- Efficient dependency pruning
- CDN-compatible asset handling
- Minimal runtime images with `standalone` output tracing

## Workspace Structure

```txt
monorepo/
├── services/
│   └── example-service/
│       ├── package.json
│       ├── public/
│       ├── .next/
│       ├── ...
├── packages/
│   └── shared-lib/
│       ├── package.json
│       └── ...
├── pnpm-lock.yaml
├── pnpm-workspace.yaml
├── Dockerfile
└── ...
```

## Example usage
```sh
docker build \
  --build-arg SERVICE=example-service \
  --build-arg NODE_ENV=production \
  --build-arg USE_CDN=true \
  --build-arg UPLOAD_ENV=production \
  -t example-service:latest .
```

## Notes

- If you're using a custom image loader (loader: 'custom'), make sure unoptimized is set to false. Otherwise, Next.js won't apply the loader in production.

- Next.js reads environment variables only from .env.production during next build. Passing them via ENV does not work. The .env.production must exist in the service root at build time.

- PNPM creates symlinks in node_modules, which can break module resolution in Docker if not preserved correctly. Use pnpm deploy to flatten dependencies before copying into the runtime container.

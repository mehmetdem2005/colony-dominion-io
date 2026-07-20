FROM node:22-alpine

RUN apk add --no-cache tini
WORKDIR /app
COPY backend/external-allocator/server.mjs /app/server.mjs

ENV NODE_ENV=production \
    PORT=8080 \
    DOCKER_SOCKET=/var/run/docker.sock \
    DOCKER_API_VERSION=v1.41 \
    ALLOCATOR_DATA_DIR=/data/allocations

EXPOSE 8080/tcp
VOLUME ["/data"]
HEALTHCHECK --interval=15s --timeout=5s --start-period=10s --retries=3 \
    CMD node -e "fetch('http://127.0.0.1:8080/health').then(r=>{if(!r.ok)process.exit(1)}).catch(()=>process.exit(1))"
ENTRYPOINT ["/sbin/tini", "--"]
CMD ["node", "/app/server.mjs"]

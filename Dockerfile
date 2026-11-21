# Shiori v1.8.0, official Alpine image (the plain v1.8.0 tag is FROM scratch and has no shell).
FROM ghcr.io/go-shiori/shiori:alpine-v1.8.0@sha256:79ca8588c0abc5cc1ccad11ce5ab7f9bab393966b699d60be9c82aa6b356fd3a

# SHIORI_DIR holds archives, thumbnails and ebooks: mount the Railway volume there.
# GOMAXPROCS / GOMEMLIMIT keep the Go runtime inside small plans (0.5 GB / 1 vCPU on Free).
ENV SHIORI_DIR=/shiori \
    PORT=8080 \
    GOMAXPROCS=2 \
    GOMEMLIMIT=400MiB

COPY start.sh /usr/local/bin/start.sh
RUN chmod +x /usr/local/bin/start.sh

EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/start.sh"]

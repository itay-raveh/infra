FROM ghcr.io/cloudnative-pg/plugin-barman-cloud-sidecar:v0.15.0@sha256:06c78deca670525daa35fb1e5323159092785d11cf87b86217bdd5c679a41a84

LABEL org.opencontainers.image.source="https://github.com/itay-raveh/infra"

USER 0:0
COPY patch.py /tmp/patch.py
RUN ["/venv/bin/python3", "/tmp/patch.py"]
USER 26:26

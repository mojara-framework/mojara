FROM ubuntu:24.04

ARG MOJARA_VERSION=1.2.9
ARG MOJARA_PACKAGE_MODE=channel
LABEL org.opencontainers.image.title="Mojara" \
      org.opencontainers.image.description="Mojo-first web framework and compiler-ready CLI" \
      org.opencontainers.image.source="https://github.com/mojara-framework/mojara" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.version="${MOJARA_VERSION}"

ENV DEBIAN_FRONTEND=noninteractive \
    PIXI_NO_TELEMETRY=1

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       bash ca-certificates curl build-essential \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /workspace \
    && chown ubuntu:ubuntu /workspace

USER ubuntu
ENV HOME=/home/ubuntu \
    PIXI_HOME=/home/ubuntu/.pixi \
    PATH=/home/ubuntu/.pixi/bin:$PATH \
    MOJARA_HOST=0.0.0.0 \
    MOJARA_PORT=8000

RUN curl -fsSL https://pixi.sh/install.sh | bash \
    && if [ "$MOJARA_PACKAGE_MODE" = "local" ]; then \
         package="$(find /tmp/mojara-package -type f -name 'mojara-*.conda' -print -quit)"; \
         test -s "$package"; \
         pixi global install --path "$package" \
           -c https://conda.modular.com/max/ -c conda-forge; \
       else \
         pixi global install "mojara==${MOJARA_VERSION}" \
           -c https://mojara.kasua.ng/conda/ \
           -c https://conda.modular.com/max/ -c conda-forge; \
       fi \
    && pixi global install 'watchexec>=2.7,<3' -c conda-forge \
    && mojara version | grep -F "Mojara ${MOJARA_VERSION}" \
    && mojara doctor \
    && watchexec --version

WORKDIR /workspace
EXPOSE 8000
ENTRYPOINT ["mojara"]
CMD ["version"]

FROM --platform=linux/amd64 ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       bash ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*

RUN useradd --create-home --uid 1000 --shell /bin/bash mojara \
    && mkdir -p /workspace \
    && chown mojara:mojara /workspace

USER mojara
ENV HOME=/home/mojara \
    PIXI_HOME=/home/mojara/.pixi \
    PATH=/home/mojara/.pixi/bin:$PATH \
    MOJARA_HOST=0.0.0.0 \
    MOJARA_PORT=8000

RUN curl -fsSL https://pixi.sh/install.sh | bash \
    && pixi global install 'mojara==1.2.7' \
       -c https://mojara.kasua.ng/conda/ \
       -c https://conda.modular.com/max/ \
       -c conda-forge \
    && mojara version \
    && mojara doctor

WORKDIR /workspace
EXPOSE 8000
ENTRYPOINT ["mojara"]
CMD ["version"]

FROM --platform=linux/amd64 ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       bash ca-certificates curl \
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

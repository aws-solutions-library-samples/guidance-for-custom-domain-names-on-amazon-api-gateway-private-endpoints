ARG PLATFORM
ARG IMAGE
FROM --platform=${PLATFORM} ${IMAGE}

RUN amazon-linux-extras install -y nginx1 \
    && yum update -y \
    && yum install -y openssl \
    && yum clean all && \
    rm -rf /var/cache/yum

COPY --chmod=500 entrypoint.sh /entrypoint.sh
COPY --chmod=400 openssl.cnf /openssl.cnf

USER daemon

HEALTHCHECK --interval=30s --timeout=30s --start-period=5s --retries=3 CMD [ "curl --fail --insecure https://localhost || exit 1" ]
ENTRYPOINT [ "/entrypoint.sh" ]
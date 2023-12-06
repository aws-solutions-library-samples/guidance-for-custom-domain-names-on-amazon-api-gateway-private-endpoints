ARG PLATFORM
ARG IMAGE
#checkov:skip=CKV_DOCKER_3: ECS doesn't run in privileged mode.
#checkov:skip=CKV_DOCKER_7: latest tag is disallowed at the cdk level
FROM --platform=${PLATFORM} ${IMAGE}

RUN yum update -y \
    && yum install -y nginx openssl \
    && yum clean all && \
    rm -rf /var/cache/yum

COPY --chmod=500 entrypoint.sh /entrypoint.sh
COPY --chmod=400 openssl.cnf /openssl.cnf

HEALTHCHECK --interval=30s --timeout=30s --start-period=5s --retries=3 CMD [ "/bin/sh", "-c", "curl", "--cacert", "/cert.pem", "https://localhost" ]

ENTRYPOINT [ "/entrypoint.sh" ]
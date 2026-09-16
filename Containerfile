FROM docker.io/library/alpine:latest AS strongswan-builder

COPY build-strongswan.sh /usr/local/sbin/build-strongswan

RUN /usr/local/sbin/build-strongswan

FROM docker.io/library/alpine:latest

RUN apk add --no-cache \
        bash \
        ca-certificates \
        gost \
        gmp \
        libcap \
        openssl \
    && update-ca-certificates

COPY --from=strongswan-builder /out/ /

RUN printf '%s\n' \
        '' \
        'charon {' \
        '    load_modular = yes' \
        '    port = 45000' \
        '    port_nat_t = 45001' \
        '    plugins {' \
        '        include strongswan.d/charon/*.conf' \
        '    }' \
        '}' \
    >> /etc/strongswan.conf

COPY --chmod=755 entrypoint.sh /entrypoint.sh

ENV TIMEOUT=120
ENV START_DELAY=1
ENV SOCKS_PORT=1082

EXPOSE 1082

ENTRYPOINT ["/entrypoint.sh"]

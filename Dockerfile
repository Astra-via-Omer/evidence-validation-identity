FROM alpine:3.22 AS download
ARG POCKETBASE_VERSION=0.40.4
ARG TARGETARCH=amd64
RUN apk add --no-cache ca-certificates curl unzip
RUN cd /tmp \
    && curl -fsSL "https://github.com/pocketbase/pocketbase/releases/download/v${POCKETBASE_VERSION}/pocketbase_${POCKETBASE_VERSION}_linux_${TARGETARCH}.zip" -o "pocketbase_${POCKETBASE_VERSION}_linux_${TARGETARCH}.zip" \
    && curl -fsSL "https://github.com/pocketbase/pocketbase/releases/download/v${POCKETBASE_VERSION}/checksums.txt" -o checksums.txt \
    && awk -v archive="pocketbase_${POCKETBASE_VERSION}_linux_${TARGETARCH}.zip" '$2 == archive { print }' checksums.txt > selected-checksum.txt \
    && test -s selected-checksum.txt && sha256sum -c selected-checksum.txt \
    && unzip "pocketbase_${POCKETBASE_VERSION}_linux_${TARGETARCH}.zip" pocketbase -d /out
FROM alpine:3.22
RUN apk add --no-cache ca-certificates && addgroup -S pocketbase && adduser -S -u 10001 pocketbase -G pocketbase
WORKDIR /pb
COPY --from=download /out/pocketbase /usr/local/bin/pocketbase
COPY pb_migrations ./pb_migrations
RUN mkdir pb_data && chown -R pocketbase:pocketbase /pb
USER pocketbase
EXPOSE 8090
VOLUME /pb/pb_data
ENTRYPOINT ["pocketbase"]
CMD ["serve", "--http=0.0.0.0:8090", "--dir=/pb/pb_data", "--migrationsDir=/pb/pb_migrations"]

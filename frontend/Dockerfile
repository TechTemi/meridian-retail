FROM debian:forky-slim AS busybox-builder

RUN apt-get update \
    && apt-get install -y --no-install-recommends busybox-static=1:1.38.0-3+b1 \
    && test "$(dpkg-query -W -f='${Version}' busybox-static)" = "1:1.38.0-3+b1" \
    && test -x /usr/bin/busybox \
    && /usr/bin/busybox --list | grep -qx httpd \
    && rm -rf /var/lib/apt/lists/*

FROM scratch

COPY --from=busybox-builder /usr/bin/busybox /busybox
COPY index.html /www/index.html

EXPOSE 80

ENTRYPOINT ["/busybox"]
CMD ["httpd", "-f", "-p", "80", "-h", "/www"]

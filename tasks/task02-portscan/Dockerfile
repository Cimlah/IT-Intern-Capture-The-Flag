FROM alpine:3.19

RUN apk add --no-cache busybox-extras bash coreutils

RUN mkdir -p /srv/www
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

CMD ["/entrypoint.sh"]

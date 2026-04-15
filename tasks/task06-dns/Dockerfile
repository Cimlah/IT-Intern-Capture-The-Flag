FROM alpine:3.19

RUN apk add --no-cache dnsmasq bash

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 53/udp
EXPOSE 53/tcp
CMD ["/entrypoint.sh"]

FROM alpine:3.19

RUN apk add --no-cache openssh-server bash shadow

RUN ssh-keygen -A
COPY sshd_config /etc/ssh/sshd_config
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 22
CMD ["/entrypoint.sh"]

FROM ubuntu:latest

RUN apt-get update && apt-get install -y \
    curl \
    jq \
    postgresql-common \
    tini \
    unzip \
    zstd

RUN /usr/share/postgresql-common/pgdg/apt.postgresql.org.sh -y
RUN apt-get update && apt-get install -y postgresql-client-15

RUN \
    export VERSION="2.55.0" && \
    curl -o /usr/local/bin/scw -L "https://github.com/scaleway/scaleway-cli/releases/download/v${VERSION}/scaleway-cli_${VERSION}_linux_amd64" && \
    chmod +x /usr/local/bin/scw

RUN curl https://rclone.org/install.sh | bash

COPY src /

ENTRYPOINT ["tini", "--"]

CMD [ "/backup.sh" ]

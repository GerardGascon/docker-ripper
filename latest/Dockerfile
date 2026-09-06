FROM ubuntu:noble

ENV DEBIAN_FRONTEND=noninteractive \
    LC_ALL=C.UTF-8 \
    LANG=en_US.UTF-8 \
    LANGUAGE=en_US.UTF-8

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        abcde \
        cdparanoia \
        eject \
        flac \
        glyrc \
        lame \
        sdparm \
        coreutils && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Writable fallback locations for arbitrary runtime UIDs
RUN mkdir -p /config/ripper && \
    chmod 1777 /config

COPY root/ /

RUN chmod +x /etc/my_init.d/ripper.sh

ENTRYPOINT ["/etc/my_init.d/ripper.sh"]

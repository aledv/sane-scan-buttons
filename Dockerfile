# Front-panel buttons of a SANE scanner -> scan to PDF -> folder / Paperless / email / printer.
# The scanner can be shared with a web UI (e.g. scanservjs) through saned on port 6566.
FROM debian:trixie-slim@sha256:a99cfc517144bc59b1978475ec53b46ecabec7e43635402ee5b77cc54cd1b20a

# hadolint ignore=DL3008
RUN apt-get update -qq \
 && apt-get install -y -qq --no-install-recommends python3-sane sane-utils libsane1 openbsd-inetd img2pdf \
      cups-client curl ca-certificates util-linux \
 && rm -rf /var/lib/apt/lists/* \
 && echo "sane-port stream tcp nowait root /app/saned-wrap.sh saned-wrap.sh" > /etc/inetd.conf

COPY app/ /app/
RUN chmod +x /app/*.sh /app/buttons.py

# Needs root: USB access to the scanner, chown of the output files, inetd on port 6566.
ENTRYPOINT ["/app/entrypoint.sh"]

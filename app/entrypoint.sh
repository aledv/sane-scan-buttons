#!/bin/sh
# SANE backend(s) and saned access list from the environment, then inetd in the background
# (SANE port 6566 -> saned-wrap.sh, to share the scanner) and the button watcher in the foreground.
set -e
# shellcheck disable=SC2086  # word splitting wanted: "a,b" or "a b"
printf '%s\n' ${SANE_BACKENDS:-genesys} | tr ',' '\n' > /etc/sane.d/dll.conf
{
    echo "data_portrange = 10000 - 10100"
    # shellcheck disable=SC2086
    printf '%s\n' ${SANED_ALLOW:-127.0.0.1} | tr ',' '\n'
} > /etc/sane.d/saned.conf
if [ "${SANED_ENABLE:-1}" = "1" ]; then
    /usr/sbin/inetd /etc/inetd.conf
fi
exec python3 -u /app/buttons.py

#!/bin/sh
# Started by inetd for every SANE network connection (e.g. from scanservjs): asks buttons.py to
# release the scanner, runs saned on this connection (stdin), then gives the scanner back.
PID=$(cat /run/scanner-buttons.pid 2>/dev/null)
[ -n "$PID" ] && kill -USR1 "$PID" 2>/dev/null
i=0
while [ ! -f /run/scanner-released ] && [ $i -lt 30 ]; do
    sleep 0.1
    i=$((i + 1))
done
/usr/sbin/saned
[ -n "$PID" ] && kill -USR2 "$PID" 2>/dev/null
exit 0

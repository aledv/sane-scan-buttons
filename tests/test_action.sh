#!/bin/bash
# Runs action.sh with fake scanimage/img2pdf/lp/curl/install on the PATH and checks what it does.
# Run: bash tests/test_action.sh
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/consume" "$work/output"
log="$work/calls.log"

cat > "$work/bin/scanimage" <<'S'
#!/bin/sh
echo "scanimage $*" >> "$CALLS"; while [ $# -gt 0 ]; do [ "$1" = "-o" ] && echo jpeg > "$2"; shift; done
S
cat > "$work/bin/img2pdf" <<'S'
#!/bin/sh
echo "img2pdf $*" >> "$CALLS"; while [ $# -gt 0 ]; do [ "$1" = "-o" ] && echo pdf > "$2"; shift; done
S
cat > "$work/bin/lp" <<'S'
#!/bin/sh
echo "lp $*" >> "$CALLS"
S
cat > "$work/bin/curl" <<'S'
#!/bin/sh
echo "curl $*" >> "$CALLS"
S
cat > "$work/bin/install" <<'S'
#!/bin/sh
echo "install $*" >> "$CALLS"; for last; do :; done; cp "$(eval echo \${$(($#-1))})" "$WORK$last"
S
cat > "$work/bin/flock" <<'S'
#!/bin/sh
exit 0
S
chmod +x "$work/bin/"*

# action.sh writes to /consume and /output: rewrite those paths into the temp dir
sed -e "s#/run/scanner-action.lock#$work/lock#" "$here/app/action.sh" > "$work/action.sh"
chmod +x "$work/action.sh"

run() {
    : > "$log"
    env PATH="$work/bin:$PATH" CALLS="$log" WORK="$work" CONSUME_OWNER=1000:1000 FOLDER_OWNER=33:33 \
        SCANBD_DEVICE=genesys:test NOTIFY_URL=http://relay:5000 "$@" "$work/action.sh" > /dev/null
}
fail() { echo "FAIL: $*"; cat "$log"; exit 1; }

run SCANBD_ACTION=scan
grep -q "install -o 1000 -g 1000 -m 664 .* /consume/Scan_" "$log" || fail "scan -> consume"
grep -q "curl .*message=📄 Scan sent to the consume folder" "$log" || fail "scan -> notification"

run SCANBD_ACTION=file FOLDER_FLAG="$work/flag" FILE_PREFIX=Scansione LANGUAGE=it
grep -q "install -o 33 -g 33 -m 644 .* /output/Scansione_" "$log" || fail "file -> folder"
[ -f "$work/flag" ] || fail "file -> flag"
grep -q "Scansione salvata" "$log" || fail "file -> italian message"

run SCANBD_ACTION=email EMAIL_SUBJECT="New scan" EMAIL_SENDER=scanner@example.com
grep -q "curl .*subject=New scan.*sender=scanner@example.com.*/notify/email" "$log" || fail "email"

run SCANBD_ACTION=copy PRINTER=office
grep -q "lp -d office -o media=A4" "$log" || fail "copy -> print"

run SCANBD_ACTION=copy ACTION_COPY=none
grep -q scanimage "$log" && fail "ACTION_COPY=none must not scan"

run SCANBD_ACTION=scan SCAN_RESOLUTION=150 SCAN_MODE=Gray
grep -q "scanimage -d genesys:test --mode Gray --resolution 150" "$log" || fail "scan settings"

echo "action.sh: all checks passed"

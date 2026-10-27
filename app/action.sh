#!/bin/bash
# Run by buttons.py for each button press (the scanner is already closed by the daemon).
# Scans one page to PDF, then does what ACTION_<BUTTON> says:
#   consume -> copy into /consume (e.g. the Paperless-ngx consume folder)
#   folder  -> copy into /output (e.g. a Nextcloud or Samba folder), optionally touch FOLDER_FLAG
#   email   -> send as attachment through a notify-relay compatible endpoint (NOTIFY_URL)
#   print   -> print with CUPS (PRINTER, or the default destination)
#   none    -> ignore the button
# Every result is also reported to NOTIFY_URL/notify/telegram when NOTIFY_URL is set.
set -uo pipefail
exec 9>/run/scanner-action.lock
flock 9

BUTTON="${SCANBD_ACTION:-}"
DEVICE="${SCANBD_DEVICE:-}"
upper=$(printf '%s' "$BUTTON" | tr '[:lower:]' '[:upper:]')
default_action() { case "$1" in scan) echo consume ;; file) echo folder ;; email) echo email ;; copy) echo print ;; *) echo none ;; esac; }
var="ACTION_$upper"
ACTION="${!var:-$(default_action "$BUTTON")}"

NOTIFY_URL="${NOTIFY_URL:-}"
LANGUAGE="${LANGUAGE:-en}"
FILE_PREFIX="${FILE_PREFIX:-Scan}"
TS=$(date +%Y-%m-%d_%H.%M.%S)
NAME="${FILE_PREFIX}_$TS.pdf"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# --- messages (en / it) ---
msg() {
    local key=$1 arg=${2:-}
    if [ "$LANGUAGE" = "it" ]; then
        case "$key" in
            scan_failed) echo "🖨️ Scanner: scansione fallita ($arg)" ;;
            consume_ok) echo "📄 Scansione inviata a Paperless: $arg" ;;
            consume_failed) echo "📄 Scanner: copia nella cartella consume fallita" ;;
            folder_ok) echo "📁 Scansione salvata: $arg" ;;
            folder_failed) echo "📁 Scanner: salvataggio nella cartella fallito" ;;
            email_ok) echo "✉️ Scansione inviata per email: $arg" ;;
            email_failed) echo "✉️ Scanner: invio email fallito" ;;
            email_body) echo "Scansione del $arg" ;;
            print_ok) echo "🖨️ Copia inviata alla stampante" ;;
            print_failed) echo "🖨️ Scanner: stampa fallita ($arg)" ;;
        esac
    else
        case "$key" in
            scan_failed) echo "🖨️ Scanner: scan failed ($arg)" ;;
            consume_ok) echo "📄 Scan sent to the consume folder: $arg" ;;
            consume_failed) echo "📄 Scanner: copy to the consume folder failed" ;;
            folder_ok) echo "📁 Scan saved: $arg" ;;
            folder_failed) echo "📁 Scanner: saving to the folder failed" ;;
            email_ok) echo "✉️ Scan sent by email: $arg" ;;
            email_failed) echo "✉️ Scanner: sending the email failed" ;;
            email_body) echo "Scan of $arg" ;;
            print_ok) echo "🖨️ Copy sent to the printer" ;;
            print_failed) echo "🖨️ Scanner: printing failed ($arg)" ;;
        esac
    fi
}
notify() { [ -n "$NOTIFY_URL" ] && curl -s -m 20 -X POST -F "message=$1" "$NOTIFY_URL/notify/telegram" >/dev/null; return 0; }
log() { echo "$(date "+%F %T") [$BUTTON/$ACTION] $*"; }

[ "$ACTION" = "none" ] && { log "button ignored"; exit 0; }

log "scanning: ${SCAN_MODE:-Color}, ${SCAN_RESOLUTION:-300} dpi, ${SCAN_WIDTH_MM:-210}x${SCAN_HEIGHT_MM:-297} mm"
if ! scanimage -d "$DEVICE" --mode "${SCAN_MODE:-Color}" --resolution "${SCAN_RESOLUTION:-300}" -l 0 -t 0 \
        -x "${SCAN_WIDTH_MM:-210}" -y "${SCAN_HEIGHT_MM:-297}" --format=jpeg -o "$TMP/scan.jpg" 2>"$TMP/err"; then
    err=$(tail -1 "$TMP/err")
    log "scan failed: $err"
    notify "$(msg scan_failed "$err")"
    exit 1
fi
img2pdf --pagesize "${PAGE_SIZE:-A4}" -o "$TMP/scan.pdf" "$TMP/scan.jpg"

case "$ACTION" in
    consume)
        if install -o "${CONSUME_OWNER%%:*}" -g "${CONSUME_OWNER##*:}" -m 664 "$TMP/scan.pdf" "/consume/$NAME" 2>"$TMP/err"; then
            log "copied to /consume/$NAME"
            notify "$(msg consume_ok "$NAME")"
        else
            log "copy to /consume failed: $(cat "$TMP/err")"
            notify "$(msg consume_failed)"
        fi
        ;;
    folder)
        if install -o "${FOLDER_OWNER%%:*}" -g "${FOLDER_OWNER##*:}" -m "${FOLDER_MODE:-644}" "$TMP/scan.pdf" "/output/$NAME" 2>"$TMP/err"; then
            [ -n "${FOLDER_FLAG:-}" ] && touch "$FOLDER_FLAG"
            log "saved to /output/$NAME"
            notify "$(msg folder_ok "$NAME")"
        else
            log "saving to /output failed: $(cat "$TMP/err")"
            notify "$(msg folder_failed)"
        fi
        ;;
    email)
        args=(-F "message=$(msg email_body "$TS")" -F "file=@$TMP/scan.pdf;filename=$NAME")
        [ -n "${EMAIL_SUBJECT:-}" ] && args+=(-F "subject=$EMAIL_SUBJECT")
        [ -n "${EMAIL_SENDER:-}" ] && args+=(-F "sender=$EMAIL_SENDER")
        [ -n "${EMAIL_SENDER_NAME:-}" ] && args+=(-F "sender_name=$EMAIL_SENDER_NAME")
        if [ -n "$NOTIFY_URL" ] && curl -s -f -m 60 -X POST "${args[@]}" "$NOTIFY_URL/notify/email" >/dev/null; then
            log "sent by email"
            notify "$(msg email_ok "$NAME")"
        else
            log "email failed (is NOTIFY_URL set?)"
            notify "$(msg email_failed)"
        fi
        ;;
    print)
        dest=()
        [ -n "${PRINTER:-}" ] && dest=(-d "$PRINTER")
        if lp "${dest[@]}" -o "media=${PAGE_SIZE:-A4}" -o fit-to-page -t "Copy $TS" "$TMP/scan.pdf" >/dev/null 2>"$TMP/err"; then
            log "printed"
            notify "$(msg print_ok)"
        else
            err=$(tail -1 "$TMP/err")
            log "printing failed: $err"
            notify "$(msg print_failed "$err")"
        fi
        ;;
    *)
        log "unknown action '$ACTION' (use consume, folder, email, print or none)"
        ;;
esac

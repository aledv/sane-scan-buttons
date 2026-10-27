# sane-scan-buttons

[![CI](https://github.com/aledv/sane-scan-buttons/actions/workflows/image.yml/badge.svg)](https://github.com/aledv/sane-scan-buttons/actions/workflows/image.yml) [![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE) [![Image](https://img.shields.io/badge/ghcr.io-sane--scan--buttons-2496ED?logo=docker&logoColor=white)](https://github.com/aledv/sane-scan-buttons/pkgs/container/sane-scan-buttons)

Make the physical buttons of a USB scanner do something useful again, on a Raspberry Pi or any
Linux box with Docker. Press a button, get a PDF:

| Button (example: Canon LiDE 100) | Default action |
|---|---|
| SCAN | into the **Paperless-ngx** consume folder |
| PDF (`file`) | into a **folder**, e.g. your Nextcloud `Scans` |
| EMAIL | sent by **email** as an attachment |
| COPY | **printed** on a CUPS printer, i.e. a photocopy |

Each result is confirmed on Telegram (or wherever your relay sends it). The scanner can still be
used from a web UI such as [scanservjs](https://github.com/sbs20/scanservjs) at the same time: the
button daemon hands the device over through `saned` and takes it back afterwards.

Any action can go on any button (`ACTION_<BUTTON>=consume|folder|email|print|none`), and the
button names, SANE backend, resolution, page size, file names and ownership are all set in `.env`.

## How it works

- `buttons.py` keeps the scanner open and polls its button "sensors" (most scanners report a
  button only while it is held down). On a press it closes the device and runs `action.sh`.
- `action.sh` scans one page with `scanimage`, makes a PDF with `img2pdf` and does the action.
- Email and notifications go through a [notify-relay](https://github.com/aledv/notify-relay)
  compatible HTTP endpoint (`NOTIFY_URL`), so this container holds no SMTP or bot credentials.
- `saned` runs from `inetd` on port 6566; on each connection `saned-wrap.sh` asks the daemon to
  release the scanner and gives it back when the session ends.

## Requirements

- A scanner supported by SANE whose buttons show up in `scanimage -A` (look for the "Sensors"
  section, e.g. `--scan[=(yes|no)] [no] [hardware]`). Tested with a Canon LiDE 100 (`genesys`).
- Docker with Compose. For COPY, CUPS on the host with your printer configured.
- Optional: Paperless-ngx, a folder to save into, a notify-relay for email and confirmations.

## Quick start

```bash
git clone https://github.com/aledv/sane-scan-buttons.git && cd sane-scan-buttons
cp .env.example .env          # backend, buttons, actions, NOTIFY_URL...
# edit the volumes in docker-compose.yml (consume / output folders)
docker compose up -d
docker logs -f scan-buttons   # "watching buttons [...] on genesys:libusb:..." then press a button
```

Find the backend and button names with `docker compose run --rm --entrypoint scanimage scan-buttons -L`
and `... scanimage -A`.

## Configuration (`.env`)

Names only, see `.env.example` for defaults and comments.

| Variable | Purpose |
|---|---|
| `SANE_BACKENDS`, `SANE_DEVICE_PREFIX` | SANE backend(s) to load and which device to use |
| `BUTTONS` | Button option names (`scanimage -A`) |
| `ACTION_<BUTTON>` | `consume`, `folder`, `email`, `print` or `none` |
| `SCAN_MODE`, `SCAN_RESOLUTION`, `SCAN_WIDTH_MM`, `SCAN_HEIGHT_MM`, `PAGE_SIZE` | Scan settings |
| `FILE_PREFIX` | PDF name: `<prefix>_YYYY-MM-DD_HH.MM.SS.pdf` |
| `CONSUME_OWNER`, `FOLDER_OWNER`, `FOLDER_MODE`, `FOLDER_FLAG` | Ownership of the files; optional flag file after a folder save |
| `NOTIFY_URL`, `EMAIL_SUBJECT`, `EMAIL_SENDER`, `EMAIL_SENDER_NAME` | Relay for confirmations and email |
| `PRINTER` | CUPS queue for COPY (empty = default) |
| `LANGUAGE` | Confirmation messages: `en` or `it` |
| `SANED_ENABLE`, `SANED_ALLOW` | Share the scanner over the network, and with whom |

### Nextcloud

Files written straight into a Nextcloud data folder only appear after a rescan. Set
`FOLDER_FLAG=/flags/rescan`, mount a flags folder, and let a host cron job run
`docker exec -u www-data nextcloud php occ files:scan --path="<user>/files/Scans"` when the flag exists.

## Development

```bash
python -m unittest discover -s tests -v          # button logic
bash tests/test_action.sh                        # action.sh with fake scanimage/lp/curl
ruff check . && ruff format --check .            # Python linter
shellcheck app/*.sh tests/*.sh                   # shell linter
hadolint --config .hadolint.yaml Dockerfile      # Dockerfile linter
```

CI runs the linters, then the tests, then publishes `ghcr.io/aledv/sane-scan-buttons`
(`linux/arm64`, `linux/amd64`).

## Contributing

Issues and pull requests are welcome. Please run the linters and tests (see [Development](#development)) before opening a pull request.

## License

MIT, see [LICENSE](LICENSE).

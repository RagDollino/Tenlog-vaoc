#!/usr/bin/env bash
# ============================================================
# VAOC - Virtual Auto Offset Calibration
# Automatic installer for IDEX Klipper printers
# Project: https://github.com/RagDollino/Tenlog-vaoc
#
# Usage (run as the Klipper user, NOT root):
#   bash <(curl -fsSL https://raw.githubusercontent.com/RagDollino/Tenlog-vaoc/main/install.sh)
# ============================================================

set -euo pipefail

# ── Colors ───────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()    { printf "${GREEN}==>${NC} %s\n" "$*"; }
warn()    { printf "${YELLOW}[!]${NC} %s\n" "$*"; }
error()   { printf "${RED}[ERROR]${NC} %s\n" "$*"; exit 1; }
step()    { printf "\n${CYAN}${BOLD}--- %s ---${NC}\n" "$*"; }
confirm() { printf "${BOLD}%s [y/N]: ${NC}" "$1"; read -r r; [[ "$r" =~ ^[Yy]$ ]]; }

# ── Config ───────────────────────────────────────────────────
REPO_RAW="https://raw.githubusercontent.com/RagDollino/Tenlog-vaoc/main"
PRINTER_DATA="${HOME}/printer_data"
CONFIG_DIR="${PRINTER_DATA}/config"
THEME_DIR="${CONFIG_DIR}/.theme"
NAVI_JSON="${THEME_DIR}/navi.json"
PRINTER_CFG="${CONFIG_DIR}/printer.cfg"
VAOC_CFG="${CONFIG_DIR}/vaoc.cfg"
TEMP_DIR="$(mktemp -d)"

# ── Cleanup on exit ──────────────────────────────────────────
cleanup() { rm -rf "$TEMP_DIR"; }
trap cleanup EXIT

# ── Header ───────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║     VAOC - Virtual Auto Offset Calibration       ║"
echo "║     IDEX Klipper Printer Installer               ║"
echo "║     https://github.com/RagDollino/Tenlog-vaoc    ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""

# ── Sanity checks ────────────────────────────────────────────
[ "$(id -u)" -eq 0 ] && error "Run this script as the Klipper user (e.g. biqu, pi), NOT as root."
command -v python3 &>/dev/null || error "python3 is required but not installed."
command -v curl   &>/dev/null || error "curl is required but not installed."
command -v nginx  &>/dev/null || warn "nginx not found — you may need to configure it manually."

[ -d "$CONFIG_DIR" ] || error "Klipper config directory not found at: $CONFIG_DIR"

# ── Detect Mainsail directory ────────────────────────────────
step "Detecting Mainsail installation"

MAINSAIL_DIR=""

# Try to detect from nginx config
for nginx_cfg in \
    /etc/nginx/sites-enabled/mainsail \
    /etc/nginx/sites-available/mainsail \
    /etc/nginx/conf.d/mainsail.conf \
    /etc/nginx/conf.d/upstreams.conf; do
    [ -f "$nginx_cfg" ] || continue
    detected=$(grep -oP 'root\s+\K[^\s;]+' "$nginx_cfg" 2>/dev/null | head -1 || true)
    if [ -n "$detected" ] && [ -d "$detected" ]; then
        MAINSAIL_DIR="$detected"
        info "Detected Mainsail directory: $MAINSAIL_DIR"
        break
    fi
done

# Fallback: common locations
if [ -z "$MAINSAIL_DIR" ]; then
    for candidate in "${HOME}/mainsail" "/var/www/mainsail" "/srv/mainsail"; do
        if [ -d "$candidate" ] && [ -f "$candidate/index.html" ]; then
            MAINSAIL_DIR="$candidate"
            info "Found Mainsail at: $MAINSAIL_DIR"
            break
        fi
    done
fi

# Ask user if still not found
if [ -z "$MAINSAIL_DIR" ]; then
    warn "Could not auto-detect Mainsail directory."
    printf "${BOLD}Enter Mainsail directory path [default: ${HOME}/mainsail]: ${NC}"
    read -r user_input
    MAINSAIL_DIR="${user_input:-${HOME}/mainsail}"
fi

[ -d "$MAINSAIL_DIR" ] || error "Mainsail directory not found: $MAINSAIL_DIR"

VAOC_HTML_DIR="${MAINSAIL_DIR}/vaoc"

# ── Detect nginx config ──────────────────────────────────────
step "Detecting nginx configuration"

NGINX_CFG=""
for candidate in \
    /etc/nginx/sites-enabled/mainsail \
    /etc/nginx/sites-available/mainsail \
    /etc/nginx/conf.d/mainsail.conf; do
    [ -f "$candidate" ] && { NGINX_CFG="$(readlink -f "$candidate")"; break; }
done

if [ -z "$NGINX_CFG" ]; then
    # Find config that listens on port 80
    for candidate in /etc/nginx/sites-enabled/*; do
        [ -f "$candidate" ] || continue
        grep -qE 'listen[[:space:]]+(80|443)' "$candidate" 2>/dev/null && {
            NGINX_CFG="$(readlink -f "$candidate")"; break
        }
    done
fi

if [ -z "$NGINX_CFG" ]; then
    warn "Could not auto-detect nginx config."
    printf "${BOLD}Enter nginx config file path [default: /etc/nginx/sites-enabled/mainsail]: ${NC}"
    read -r user_input
    NGINX_CFG="${user_input:-/etc/nginx/sites-enabled/mainsail}"
fi

[ -f "$NGINX_CFG" ] || warn "nginx config file not found: $NGINX_CFG — nginx step will be skipped."

# ── Summary ──────────────────────────────────────────────────
step "Installation plan"
echo ""
echo "  Klipper config dir : $CONFIG_DIR"
echo "  Mainsail dir       : $MAINSAIL_DIR"
echo "  VAOC web dir       : $VAOC_HTML_DIR"
echo "  nginx config       : ${NGINX_CFG:-not found}"
echo "  Mainsail navi.json : $NAVI_JSON"
echo ""
echo "  Files to install:"
echo "    $VAOC_CFG"
echo "    $VAOC_HTML_DIR/index.html"
echo ""
echo "  Files to modify:"
echo "    $PRINTER_CFG  (add [include vaoc.cfg])"
[ -f "$NGINX_CFG" ] && echo "    $NGINX_CFG    (add /vaoc/ location)"
echo "    $NAVI_JSON    (add VAOC sidebar entry)"
echo ""

confirm "Proceed with installation?" || { echo "Aborted."; exit 0; }

# ── Download files ───────────────────────────────────────────
step "Downloading files from GitHub"

info "Downloading vaoc.cfg..."
curl -fsSL "${REPO_RAW}/vaoc.cfg" -o "${TEMP_DIR}/vaoc.cfg"

info "Downloading vaoc/index.html..."
mkdir -p "${TEMP_DIR}/vaoc"
curl -fsSL "${REPO_RAW}/vaoc/index.html" -o "${TEMP_DIR}/vaoc/index.html"

# ── Install vaoc.cfg ─────────────────────────────────────────
step "Installing vaoc.cfg"

if [ -f "$VAOC_CFG" ]; then
    cp "$VAOC_CFG" "${VAOC_CFG}.bak.$(date +%s)"
    warn "Existing vaoc.cfg backed up."
fi
cp "${TEMP_DIR}/vaoc.cfg" "$VAOC_CFG"
info "Installed: $VAOC_CFG"

# ── Install HTML ─────────────────────────────────────────────
step "Installing web interface"

mkdir -p "$VAOC_HTML_DIR"
cp "${TEMP_DIR}/vaoc/index.html" "${VAOC_HTML_DIR}/index.html"
chmod o+rx "$VAOC_HTML_DIR" "$MAINSAIL_DIR" 2>/dev/null || true
info "Installed: $VAOC_HTML_DIR/index.html"

# ── Add include to printer.cfg ───────────────────────────────
step "Updating printer.cfg"

if [ -f "$PRINTER_CFG" ]; then
    if grep -q "vaoc.cfg" "$PRINTER_CFG"; then
        warn "[include vaoc.cfg] already exists in printer.cfg — skipping."
    else
        cp "$PRINTER_CFG" "${PRINTER_CFG}.bak.$(date +%s)"
        printf '\n[include vaoc.cfg]\n' >> "$PRINTER_CFG"
        info "Added [include vaoc.cfg] to printer.cfg"
    fi
else
    warn "printer.cfg not found at $PRINTER_CFG — add [include vaoc.cfg] manually."
fi

# ── Add nginx location /vaoc/ ────────────────────────────────
step "Configuring nginx"

if [ -z "$NGINX_CFG" ] || [ ! -f "$NGINX_CFG" ]; then
    warn "Skipping nginx configuration — config file not found."
else
    if grep -q "vaoc" "$NGINX_CFG" 2>/dev/null; then
        warn "VAOC location already exists in nginx config — skipping."
    else
        cp "$NGINX_CFG" "${NGINX_CFG}.bak.vaoc.$(date +%s)"

        python3 - "$NGINX_CFG" "$VAOC_HTML_DIR" << 'PY'
import sys, re

nginx_path = sys.argv[1]
vaoc_dir   = sys.argv[2]

src = open(nginx_path).read()

block = (
    "\n"
    "    # >>> VAOC - Virtual Auto Offset Calibration >>>\n"
    "    location /vaoc/ {\n"
    "        alias %s/;\n"
    "        index index.html;\n"
    "        try_files $uri $uri/ /vaoc/index.html;\n"
    "    }\n"
    "    # <<< VAOC <<<\n"
) % vaoc_dir

m = re.search(r'server\s*\{', src)
if not m:
    print("ERROR: Could not find 'server {' block in nginx config.")
    sys.exit(1)

out = src[:m.end()] + block + src[m.end():]
open(nginx_path, 'w').write(out)
print("   Location /vaoc/ added to nginx config.")
PY

        if sudo nginx -t 2>/dev/null; then
            sudo systemctl reload nginx
            info "nginx reloaded successfully."
        else
            # Revert on error
            latest_bak="$(ls -t "${NGINX_CFG}".bak.vaoc.* 2>/dev/null | head -1)"
            [ -n "$latest_bak" ] && sudo cp "$latest_bak" "$NGINX_CFG"
            warn "nginx config test failed — reverted. Check nginx config manually."
        fi
    fi
fi

# ── Add Mainsail sidebar entry (navi.json) ───────────────────
step "Adding VAOC to Mainsail sidebar"

mkdir -p "$THEME_DIR"

python3 - "$NAVI_JSON" << 'PY'
import json, os, sys

p = sys.argv[1]

data = []
if os.path.exists(p):
    try:
        with open(p) as f:
            data = json.load(f)
    except Exception:
        data = []

if not isinstance(data, list):
    data = []

# Remove any previous VAOC entry
data = [e for e in data if not (isinstance(e, dict) and e.get('title') == 'VAOC')]

# Camera SVG icon (MDI mdiCamera path)
camera_icon = (
    "M9,3L7.17,5H4A2,2 0 0,0 2,7V19A2,2 0 0,0 4,21H20A2,2 0 0,0 22,"
    "19V7A2,2 0 0,0 20,5H16.83L15,3H9M12,8A5,5 0 0,1 17,13A5,5 0 0,1 "
    "12,18A5,5 0 0,1 7,13A5,5 0 0,1 12,8M12,10A3,3 0 0,0 9,13A3,3 0 "
    "0,0 12,16A3,3 0 0,0 15,13A3,3 0 0,0 12,10Z"
)

data.append({
    "title": "VAOC",
    "href": "/vaoc/",
    "target": "_self",
    "icon": camera_icon,
    "position": 85,
})

with open(p, 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')

print("   VAOC entry added to: %s" % p)
PY

info "Mainsail sidebar updated."

# ── Done ─────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════╗"
printf "║  ${GREEN}${BOLD}VAOC installed successfully!${NC}                     ║\n"
echo "╠══════════════════════════════════════════════════╣"
echo "║                                                  ║"
echo "║  Next steps:                                     ║"
echo "║  1. Edit vaoc.cfg — set your camera position,   ║"
echo "║     T0/T1 park positions, and safe_z             ║"
echo "║  2. Reload Mainsail (F5) — VAOC appears in      ║"
echo "║     the sidebar                                  ║"
echo "║  3. Firmware Restart in Mainsail to load         ║"
echo "║     the new macros                               ║"
echo "║                                                  ║"
printf "║  Web interface: ${CYAN}http://YOUR_IP/vaoc/${NC}            ║\n"
echo "╚══════════════════════════════════════════════════╝"
echo ""
warn "Remember to adjust these variables in vaoc.cfg:"
echo "    variable_camera_x / variable_camera_y  -> camera position on bed"
echo "    variable_t0_park_x                     -> T0 park X position"
echo "    variable_t1_park_x                     -> T1 park X position"
echo "    variable_safe_z                        -> safe Z height"
echo ""

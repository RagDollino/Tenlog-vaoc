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

info()  { printf "${GREEN}==>${NC} %s\n" "$*"; }
warn()  { printf "${YELLOW}[!]${NC} %s\n" "$*"; }
error() { printf "${RED}[ERROR]${NC} %s\n" "$*"; exit 1; }
step()  { printf "\n${CYAN}${BOLD}--- %s ---${NC}\n" "$*"; }
ok()    { printf "${GREEN}[OK]${NC} %s\n" "$*"; }
skip()  { printf "${YELLOW}[SKIP]${NC} %s\n" "$*"; }

# ── Config ───────────────────────────────────────────────────
REPO_RAW="https://raw.githubusercontent.com/RagDollino/Tenlog-vaoc/main"
PRINTER_DATA="${HOME}/printer_data"
CONFIG_DIR="${PRINTER_DATA}/config"
THEME_DIR="${CONFIG_DIR}/.theme"
NAVI_JSON="${THEME_DIR}/navi.json"
PRINTER_CFG="${CONFIG_DIR}/printer.cfg"
VAOC_CFG="${CONFIG_DIR}/vaoc.cfg"
TEMP_DIR="$(mktemp -d)"

# Track results for final summary
INSTALLED=()
SKIPPED=()
MANUAL=()

# sudo password storage (in memory only, never written to disk)
SUDO_PASS=""

# ── Cleanup on exit ──────────────────────────────────────────
cleanup() { rm -rf "$TEMP_DIR"; }
trap cleanup EXIT

# ── sudo wrapper ─────────────────────────────────────────────
# Usage: run_sudo <command> [args...]
# Uses cached password if available, otherwise plain sudo
run_sudo() {
    if [ -n "$SUDO_PASS" ]; then
        echo "$SUDO_PASS" | sudo -S "$@" 2>/dev/null
    else
        sudo "$@"
    fi
}

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
[ -d "$CONFIG_DIR" ] || error "Klipper config directory not found at: $CONFIG_DIR"

# ── Detect sudo availability ─────────────────────────────────
step "Checking sudo access"

HAS_SUDO=false

if ! command -v sudo &>/dev/null; then
    warn "sudo is not installed — nginx steps will be skipped."
    MANUAL+=("nginx configuration")
else
    if sudo -n true 2>/dev/null; then
        # Works without password
        HAS_SUDO=true
        info "sudo available (no password required)."
    else
        # Needs password — ask the user
        echo ""
        printf "${BOLD}sudo requires a password to configure nginx.${NC}\n"
        printf "${BOLD}Enter your sudo password (or press Enter to skip nginx setup): ${NC}"
        read -rs SUDO_PASS
        echo ""

        if [ -z "$SUDO_PASS" ]; then
            warn "No password entered — nginx steps will be skipped."
            MANUAL+=("nginx configuration")
        else
            # Validate the password
            if echo "$SUDO_PASS" | sudo -S true 2>/dev/null; then
                HAS_SUDO=true
                ok "sudo password accepted."
            else
                warn "Incorrect sudo password — nginx steps will be skipped."
                SUDO_PASS=""
                MANUAL+=("nginx configuration")
            fi
        fi
    fi
fi

# ── Detect Mainsail directory ────────────────────────────────
step "Detecting Mainsail installation"

MAINSAIL_DIR=""

# Try to detect from nginx root directive
if $HAS_SUDO; then
    for nginx_cfg in \
        /etc/nginx/sites-enabled/mainsail \
        /etc/nginx/sites-available/mainsail \
        /etc/nginx/conf.d/mainsail.conf; do
        [ -f "$nginx_cfg" ] || continue
        detected=$(grep -oP 'root\s+\K[^\s;]+' "$nginx_cfg" 2>/dev/null | head -1 || true)
        if [ -n "$detected" ] && [ -d "$detected" ]; then
            MAINSAIL_DIR="$detected"
            info "Detected Mainsail directory from nginx: $MAINSAIL_DIR"
            break
        fi
    done
fi

# Fallback: common locations
if [ -z "$MAINSAIL_DIR" ]; then
    for candidate in \
        "${HOME}/mainsail" \
        "/var/www/mainsail" \
        "/srv/mainsail" \
        "/opt/mainsail"; do
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
if $HAS_SUDO; then
    for candidate in \
        /etc/nginx/sites-enabled/mainsail \
        /etc/nginx/sites-available/mainsail \
        /etc/nginx/conf.d/mainsail.conf; do
        [ -f "$candidate" ] && { NGINX_CFG="$(readlink -f "$candidate")"; break; }
    done

    # Fallback: find config that listens on port 80
    if [ -z "$NGINX_CFG" ]; then
        for candidate in /etc/nginx/sites-enabled/*; do
            [ -f "$candidate" ] || continue
            grep -qE 'listen[[:space:]]+(80|443)' "$candidate" 2>/dev/null && {
                NGINX_CFG="$(readlink -f "$candidate")"; break
            }
        done
    fi

    [ -n "$NGINX_CFG" ] \
        && info "Found nginx config: $NGINX_CFG" \
        || warn "Could not detect nginx config — nginx step will be skipped."
fi

# ── Summary ──────────────────────────────────────────────────
step "Installation plan"
echo ""
echo "  User home          : $HOME"
echo "  Klipper config     : $CONFIG_DIR"
echo "  Mainsail dir       : $MAINSAIL_DIR"
echo "  VAOC web dir       : $VAOC_HTML_DIR"
echo "  nginx config       : ${NGINX_CFG:-not found / will skip}"
echo "  Mainsail navi.json : $NAVI_JSON"
echo ""
echo "  Files to install:"
echo "    $VAOC_CFG"
echo "    $VAOC_HTML_DIR/index.html"
echo ""
echo "  Files to modify:"
echo "    $PRINTER_CFG  (add [include vaoc.cfg])"
[ -n "$NGINX_CFG" ] && echo "    $NGINX_CFG    (add /vaoc/ location)"
echo "    $NAVI_JSON    (add VAOC sidebar entry)"
echo ""

printf "${BOLD}Proceed with installation? [y/N]: ${NC}"
read -r confirm
[[ "$confirm" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }

# ── Download files ───────────────────────────────────────────
step "Downloading files from GitHub"

info "Downloading vaoc.cfg..."
curl -fsSL "${REPO_RAW}/vaoc.cfg" -o "${TEMP_DIR}/vaoc.cfg" \
    || error "Failed to download vaoc.cfg. Check your internet connection."

info "Downloading vaoc/index.html..."
mkdir -p "${TEMP_DIR}/vaoc"
curl -fsSL "${REPO_RAW}/vaoc/index.html" -o "${TEMP_DIR}/vaoc/index.html" \
    || error "Failed to download index.html. Check your internet connection."

ok "Files downloaded."

# ── Install vaoc.cfg ─────────────────────────────────────────
step "Installing vaoc.cfg"

if [ -f "$VAOC_CFG" ]; then
    cp "$VAOC_CFG" "${VAOC_CFG}.bak.$(date +%s)"
    warn "Existing vaoc.cfg backed up."
fi
cp "${TEMP_DIR}/vaoc.cfg" "$VAOC_CFG"
ok "Installed: $VAOC_CFG"
INSTALLED+=("vaoc.cfg")

# ── Install HTML ─────────────────────────────────────────────
step "Installing web interface"

mkdir -p "$VAOC_HTML_DIR"
cp "${TEMP_DIR}/vaoc/index.html" "${VAOC_HTML_DIR}/index.html"
chmod o+rx "$VAOC_HTML_DIR" 2>/dev/null || true
ok "Installed: $VAOC_HTML_DIR/index.html"
INSTALLED+=("vaoc/index.html")

# ── Add include to printer.cfg ───────────────────────────────
step "Updating printer.cfg"

if [ -f "$PRINTER_CFG" ]; then
    if grep -q "vaoc.cfg" "$PRINTER_CFG"; then
        skip "[include vaoc.cfg] already exists in printer.cfg."
        SKIPPED+=("printer.cfg include")
    else
        cp "$PRINTER_CFG" "${PRINTER_CFG}.bak.$(date +%s)"
        printf '\n[include vaoc.cfg]\n' >> "$PRINTER_CFG"
        ok "Added [include vaoc.cfg] to printer.cfg"
        INSTALLED+=("printer.cfg [include]")
    fi
else
    warn "printer.cfg not found — add [include vaoc.cfg] manually."
    MANUAL+=("Add [include vaoc.cfg] to printer.cfg")
fi

# ── Add nginx location /vaoc/ ────────────────────────────────
step "Configuring nginx"

if ! $HAS_SUDO || [ -z "$NGINX_CFG" ]; then
    skip "nginx configuration skipped."
    if [ -z "$NGINX_CFG" ]; then
        MANUAL+=("Add nginx location block for /vaoc/")
    fi
else
    if grep -q "vaoc" "$NGINX_CFG" 2>/dev/null; then
        skip "VAOC location already exists in nginx config."
        SKIPPED+=("nginx location")
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

# Prefer the server block that listens on port 80 or 443
m = re.search(r'server\s*\{(?:[^{}]*?)listen\s+(?:80|443)', src, re.DOTALL)
if not m:
    # Fallback: first server{} block
    m = re.search(r'server\s*\{', src)
    if not m:
        print("ERROR: Could not find server{} block in nginx config.")
        sys.exit(1)
    print("   Warning: No listen 80/443 found, inserting into first server{} block.")

# Insert right after the opening brace of the matched block
brace_pos = src.index('{', m.start())
out = src[:brace_pos + 1] + block + src[brace_pos + 1:]
open(nginx_path, 'w').write(out)
print("   Location /vaoc/ added successfully.")
PY

        if run_sudo nginx -t 2>/dev/null; then
            run_sudo systemctl reload nginx
            ok "nginx reloaded successfully."
            INSTALLED+=("nginx /vaoc/ location")
        else
            # Revert on error
            latest_bak="$(ls -t "${NGINX_CFG}".bak.vaoc.* 2>/dev/null | head -1)"
            [ -n "$latest_bak" ] && run_sudo cp "$latest_bak" "$NGINX_CFG"
            warn "nginx config test failed — change reverted."
            MANUAL+=("Add nginx location block for /vaoc/ manually")
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

# Camera SVG icon (MDI mdiCamera)
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

print("   VAOC entry written to: %s" % p)
PY

ok "navi.json updated."
INSTALLED+=("Mainsail sidebar entry")

# ── Final summary ────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════╗"
printf "║  ${GREEN}${BOLD} Installation complete!${NC}                          ║\n"
echo "╚══════════════════════════════════════════════════╝"
echo ""

if [ ${#INSTALLED[@]} -gt 0 ]; then
    printf "${GREEN}Installed:${NC}\n"
    for item in "${INSTALLED[@]}"; do printf "  ✓ %s\n" "$item"; done
    echo ""
fi

if [ ${#SKIPPED[@]} -gt 0 ]; then
    printf "${YELLOW}Skipped (already present):${NC}\n"
    for item in "${SKIPPED[@]}"; do printf "  - %s\n" "$item"; done
    echo ""
fi

if [ ${#MANUAL[@]} -gt 0 ]; then
    printf "${YELLOW}Manual steps required:${NC}\n"
    for item in "${MANUAL[@]}"; do printf "  ⚠ %s\n" "$item"; done
    echo ""

    if printf '%s\n' "${MANUAL[@]}" | grep -q "nginx"; then
        echo "  ── nginx location block ──────────────────────────"
        echo "  Add this inside the server { } block in your nginx"
        echo "  site config (usually /etc/nginx/sites-enabled/mainsail):"
        echo ""
        echo "      location /vaoc/ {"
        echo "          alias ${VAOC_HTML_DIR}/;"
        echo "          index index.html;"
        echo "          try_files \$uri \$uri/ /vaoc/index.html;"
        echo "      }"
        echo ""
        echo "  Then run:"
        echo "      sudo nginx -t && sudo systemctl reload nginx"
        echo "  ──────────────────────────────────────────────────"
        echo ""
    fi
fi

echo "  Next steps:"
echo "  1. Edit ~/printer_data/config/vaoc.cfg"
echo "     → Set camera_x/y, t0_park_x, t1_park_x, safe_z"
echo "  2. Firmware Restart in Mainsail to load the macros"
echo "  3. Reload Mainsail (F5) — VAOC appears in the sidebar"
echo ""
echo "  If the sidebar entry does not appear, open VAOC directly:"
printf "  ${CYAN}http://YOUR_PRINTER_IP/vaoc/${NC}\n"
echo ""
printf "  ${CYAN}https://github.com/RagDollino/Tenlog-vaoc${NC}\n"
echo ""

#!/usr/bin/env bash
# ==============================================================================
# CDNHUNTER LITE v1.0 - Optimizado para Termux (sin stack corruption)
# Busca subdominios, historial DNS y posibles fugas de IP de origen
# ==============================================================================
set -o pipefail
VERSION="1.0-LITE-TERMUX"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'

# 🔧 FIX TERMUX
if [[ -d "$PREFIX" ]]; then
    TMPDIR_CDH="$HOME/.cdnhunter_tmp_$$"
else
    TMPDIR_CDH=$(mktemp -d 2>/dev/null || echo "/data/local/tmp/cdh_$$")
fi
mkdir -p "$TMPDIR_CDH"
trap 'rm -rf "$TMPDIR_CDH"' EXIT

TARGET=""
VERBOSE=0

log() { echo -e "${CYAN}[•]${NC} $1" >&2; }
ok() { echo -e "${GREEN}[✓]${NC} $1" >&2; }
warn() { echo -e "${YELLOW}[!]${NC} $1" >&2; }
err() { echo -e "${RED}[✗]${NC} $1" >&2; }

# --- DEPENDECIAS ---
check_deps() {
  for cmd in curl dig grep awk sed jq whois; do
    command -v "$cmd" &>/dev/null || { warn "Falta $cmd, intentando instalar..."; pkg install -y "$cmd" &>/dev/null || true; }
  done
}

# --- DETECTAR SI ES CDN ---
is_cdn() {
  local ip=$1
  # Cloudflare ranges (cache local)
  if ! [[ -f "$TMPDIR_CDH/cf.txt" ]]; then
    curl -s https://www.cloudflare.com/ips-v4 -o "$TMPDIR_CDH/cf.txt" 2>/dev/null || touch "$TMPDIR_CDH/cf.txt"
  fi
  if grep -q "^$ip$" "$TMPDIR_CDH/cf.txt" 2>/dev/null; then echo "cloudflare"; return 0; fi
  # WHOIS fallback
  local w=$(timeout 4 whois "$ip" 2>/dev/null | tr '[:upper:]' '[:lower:]')
  echo "$w" | grep -qE 'cloudflare|akamai|fastly|amazon|azure|google' && echo "cdn" && return 0
  echo "origin"
}

# --- VALIDAR IP ---
check_ip() {
  local ip=$1 domain=$2
  local code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 -H "Host: $domain" "http://$ip" 2>/dev/null)
  [[ "$code" =~ ^[23] ]] && echo "✅" || echo "❌"
}

# --- MÉTODOS DE BÚSQUEDA ---
search_dns() {
  log "Buscando DNS directo..."
  dig +short +timeout=3 "$TARGET" A 2>/dev/null | sort -u | while read -r ip; do
    [[ -z "$ip" ]] && continue
    local t=$(is_cdn "$ip")
    [[ "$t" != "origin" ]] && continue
    local v=$(check_ip "$ip" "$TARGET")
    echo "  $ip [DNS] [$t] $v"
  done
}

search_crtsh() {
  log "Buscando subdominios en crt.sh..."
  local json=$(curl -s --max-time 25 "https://crt.sh/?q=%25.$TARGET&output=json" 2>/dev/null)
  [[ -z "$json" || "$json" == *"error"* ]] && { warn "crt.sh sin datos"; return; }
  echo "$json" | jq -r '.[].name_value' 2>/dev/null | sed 's/\*\.//g' | tr ',' '\n' | sort -u | grep -v "^$TARGET$" | head -30 | while read -r sub; do
    [[ -z "$sub" ]] && continue
    local sip=$(dig +short +timeout=3 "$sub" A 2>/dev/null | head -1)
    [[ -z "$sip" ]] && continue
    local t=$(is_cdn "$sip")
    [[ "$t" != "origin" ]] && continue
    local v=$(check_ip "$sip" "$TARGET")
    echo "  $sip [$sub] [$t] $v"
    sleep 1
  done
}

search_hackertarget() {
  log "Buscando en HackerTarget..."
  local res=$(curl -s --max-time 15 "https://api.hackertarget.com/dnslookup/?q=$TARGET" 2>/dev/null)
  echo "$res" | grep -oE '[0-9]{1,3}(\.[0-9]{1,3}){3}' | sort -u | while read -r ip; do
    [[ -z "$ip" ]] && continue
    local t=$(is_cdn "$ip")
    [[ "$t" != "origin" ]] && continue
    local v=$(check_ip "$ip" "$TARGET")
    echo "  $ip [HackerTarget] [$t] $v"
    sleep 1
  done
}

search_mx() {
  log "Buscando registros MX..."
  dig +short +timeout=3 "$TARGET" MX 2>/dev/null | awk '{print $2}' | sed 's/\.$//' | while read -r mx; do
    [[ -z "$mx" ]] && continue
    local mip=$(dig +short +timeout=3 "$mx" A 2>/dev/null | head -1)
    [[ -z "$mip" ]] && continue
    local t=$(is_cdn "$mip")
    [[ "$t" != "origin" ]] && continue
    local v=$(check_ip "$mip" "$TARGET")
    echo "  $mip [MX:$mx] [$t] $v"
  done
}

# --- MAIN ---
show_help() { echo "Uso: $0 -t dominio.com [-v]"; exit 0; }
[[ -z "$1" || "$1" != "-t" ]] && show_help
TARGET="$2"
[[ -z "$TARGET" ]] && show_help
TARGET=$(echo "$TARGET" | sed 's|http[s]*://||;s|/.*||;s|^www\.||')

echo -e "\n${BOLD}${CYAN}🕵️ CDNHUNTER LITE v$VERSION${NC}\n"
check_deps
log "Escaneando: $TARGET"
echo ""

# Ejecutar búsquedas
search_dns
search_crtsh
search_hackertarget
search_mx

echo -e "\n${GREEN}=== IPs de origen encontradas ===${NC}"
echo "${GRAY}Usa: curl -H \"Host: $TARGET\" http://<IP>${NC}"

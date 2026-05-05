#!/usr/bin/env bash
# ==============================================================================
# CDNHUNTER FREE MAX v2.0 - 100% GRATIS + Termux Optimizado
# Fuentes: crt.sh, DNSDumpster, AlienVault OTX, HackerTarget, brute-force ligero
# Sin arrays complejos = SIN stack corruption
# ==============================================================================
set -o pipefail
VERSION="2.0-FREE-MAX"
CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'

# 🔧 FIX TERMUX + limpieza automática
if [[ -d "$PREFIX" ]]; then
    TMPDIR_CDH="$HOME/.cdnhunter_$$"
else
    TMPDIR_CDH=$(mktemp -d 2>/dev/null || echo "/data/local/tmp/cdh_$$")
fi
mkdir -p "$TMPDIR_CDH"
trap 'rm -rf "$TMPDIR_CDH"' EXIT

TARGET=""
FOUND=0

log() { echo -e "${CYAN}[•]${NC} $1" >&2; }
ok() { echo -e "${GREEN}[✓]${NC} $1" >&2; ((FOUND++)); }
warn() { echo -e "${YELLOW}[!]${NC} $1" >&2; }

# --- DEPENDENCIAS ---
check_deps() {
  for cmd in curl dig grep awk sed jq; do
    command -v "$cmd" &>/dev/null || { warn "Instalando $cmd..."; pkg install -y "$cmd" &>/dev/null || true; }
  done
}

# --- ¿ES CDN? (Cloudflare + otros) ---
is_cdn() {
  local ip=$1
  # Cloudflare (cache local)
  if ! [[ -f "$TMPDIR_CDH/cf.txt" ]]; then
    curl -s https://www.cloudflare.com/ips-v4 -o "$TMPDIR_CDH/cf.txt" 2>/dev/null || touch "$TMPDIR_CDH/cf.txt"
  fi
  grep -q "^$ip$" "$TMPDIR_CDH/cf.txt" 2>/dev/null && { echo "CLOUDFLARE"; return 0; }
  # WHOIS ligero para otros CDN
  local w=$(timeout 3 whois "$ip" 2>/dev/null | tr '[:upper:]' '[:lower:]' | head -20)
  echo "$w" | grep -qE 'cloudflare|akamai|fastly|amazon|azure|google|edgecast' && { echo "CDN"; return 0; }
  echo "ORIGEN"
}

# --- VALIDAR IP como proxy potencial ---
check_proxy() {
  local ip=$1 domain=$2
  local code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 4 -H "Host: $domain" "http://$ip" 2>/dev/null)
  case "$code" in
    200|201|202|204|301|302|307) echo "✅ $code" ;;
    403|405|429) echo "⚠️ $code" ;;  # Bloqueado pero responde
    *) echo "❌ $code" ;;
  esac
}

# --- MÉTODOS DE BÚSQUEDA (todos free) ---

# 1. DNS Directo
search_dns() {
  log "DNS directo..."
  dig +short +timeout=3 "$TARGET" A 2>/dev/null | sort -u | while read -r ip; do
    [[ -z "$ip" ]] && continue
    local t=$(is_cdn "$ip")
    [[ "$t" != "ORIGEN" ]] && continue
    local v=$(check_proxy "$ip" "$TARGET")
    echo "  $ip [DNS] $v"
  done
}

# 2. crt.sh (certificados SSL - 100% free)
search_crtsh() {
  log "Subdominios en crt.sh..."
  local json=$(curl -s --max-time 30 "https://crt.sh/?q=%25.$TARGET&output=json" 2>/dev/null)
  [[ -z "$json" || "$json" == *"error"* ]] && { warn "crt.sh sin datos"; return; }
  echo "$json" | jq -r '.[].name_value' 2>/dev/null | sed 's/\*\.//g' | tr ',' '\n' | sort -u | grep -v "^$TARGET$" | head -50 | while read -r sub; do
    [[ -z "$sub" ]] && continue
    local sip=$(dig +short +timeout=3 "$sub" A 2>/dev/null | head -1)
    [[ -z "$sip" ]] && continue
    local t=$(is_cdn "$sip")
    [[ "$t" != "ORIGEN" ]] && continue
    local v=$(check_proxy "$sip" "$TARGET")
    echo "  $sip [$sub] $v"
    sleep 1  # Rate-limit amigable
  done
}

# 3. DNSDumpster (free, sin API key)
search_dnsdumpster() {
  log "DNSDumpster..."
  local html=$(curl -s --max-time 25 -X POST \
    -H "Referer: https://dnsdumpster.com" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    "https://dnsdumpster.com/" -d "targetip=$TARGET&user=free" 2>/dev/null)
  [[ -z "$html" ]] && { warn "DNSDumpster bloqueado"; return; }
  echo "$html" | grep -oE '[0-9]{1,3}(\.[0-9]{1,3}){3}' | sort -u | while read -r ip; do
    [[ -z "$ip" ]] && continue
    local t=$(is_cdn "$ip")
    [[ "$t" != "ORIGEN" ]] && continue
    local v=$(check_proxy "$ip" "$TARGET")
    echo "  $ip [DNSDumpster] $v"
    sleep 1
  done
}

# 4. AlienVault OTX (free, sin registro para consultas básicas)
search_otx() {
  log "AlienVault OTX..."
  local json=$(curl -s --max-time 20 "https://otx.alienvault.com/api/v1/indicators/domain/$TARGET/passive_dns" 2>/dev/null)
  [[ -z "$json" || "$json" == *"error"* ]] && { warn "OTX sin datos"; return; }
  echo "$json" | jq -r '.passive_dns[].address' 2>/dev/null | grep -E '^[0-9]{1,3}(\.[0-9]{1,3}){3}$' | sort -u | while read -r ip; do
    [[ -z "$ip" ]] && continue
    local t=$(is_cdn "$ip")
    [[ "$t" != "ORIGEN" ]] && continue
    local v=$(check_proxy "$ip" "$TARGET")
    echo "  $ip [OTX] $v"
    sleep 1
  done
}

# 5. Brute-force ligero con subdominios comunes (wordlist mínima)
search_brute() {
  log "Brute-force ligero..."
  local subs="www mail ftp api admin dev staging test blog shop store app mobile m m1 dev1 api1"
  for s in $subs; do
    local sub="$s.$TARGET"
    local sip=$(dig +short +timeout=2 "$sub" A 2>/dev/null | head -1)
    [[ -z "$sip" ]] && continue
    local t=$(is_cdn "$sip")
    [[ "$t" != "ORIGEN" ]] && continue
    local v=$(check_proxy "$sip" "$TARGET")
    echo "  $sip [$sub] $v"
    sleep 1
  done
}

# 6. HackerTarget (free API)
search_hackertarget() {
  log "HackerTarget..."
  local res=$(curl -s --max-time 15 "https://api.hackertarget.com/dnslookup/?q=$TARGET" 2>/dev/null)
  echo "$res" | grep -oE '[0-9]{1,3}(\.[0-9]{1,3}){3}' | sort -u | while read -r ip; do
    [[ -z "$ip" ]] && continue
    local t=$(is_cdn "$ip")
    [[ "$t" != "ORIGEN" ]] && continue
    local v=$(check_proxy "$ip" "$TARGET")
    echo "  $ip [HackerTarget] $v"
    sleep 1
  done
}

# --- MAIN ---
[[ -z "$1" || "$1" != "-t" ]] && { echo "Uso: $0 -t dominio.com"; exit 1; }
TARGET="$2"
[[ -z "$TARGET" ]] && { echo "Uso: $0 -t dominio.com"; exit 1; }
TARGET=$(echo "$TARGET" | sed 's|http[s]*://||;s|/.*||;s|^www\.||')

echo -e "\n${GREEN}${BOLD}🕵️ CDNHUNTER FREE MAX v$VERSION${NC}"
echo -e "${CYAN}100% GRATIS | Termux Optimizado | Sin stack corruption${NC}\n"
check_deps
log "Escaneando: $TARGET"
echo ""

# Ejecutar búsquedas (ordenadas por efectividad)
search_dns
search_crtsh
search_dnsdumpster
search_otx
search_hackertarget
search_brute

# Resumen final
echo -e "\n${GREEN}=== POSIBLES PROXYS (IPs de origen) ===${NC}"
if [[ $FOUND -eq 0 ]]; then
  echo "${RED}⚠️  No se encontraron IPs de origen públicas.${NC}"
  echo "${YELLOW}💡 Consejos:${NC}"
  echo "   • Prueba con subdominios menos protegidos: api.$TARGET, dev.$TARGET"
  echo "   • Intenta en otro horario (algunas APIs bloquean por rate-limit)"
  echo "   • Algunos dominios están 100% detrás de CDN sin fugas conocidas"
else
  echo "${GRAY}Usa: curl -H \"Host: $TARGET\" http://<IP>${NC}"
  echo "${GRAY}O como proxy: curl -x http://<IP>:80 \"http://$TARGET\"${NC}"
fi
echo ""

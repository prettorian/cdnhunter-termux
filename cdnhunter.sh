#!/usr/bin/env bash
# ==============================================================================
# ATILA-CDN-TEST v3.0 - FREE MAX | Termux Optimized | Parallel + Progress Bars
# Fuentes 100% GRATIS: crt.sh, DNSDumpster, OTX, HackerTarget, Brute-force
# Sin stack corruption | Sin pago | Sin registro
# ==============================================================================
set -o pipefail
VERSION="3.0-FREE-MAX"
CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
RED='\033[0;31m'; BLUE='\033[0;34m'; NC='\033[0m'; BOLD='\033[1m'

# 🔧 FIX TERMUX + limpieza automática
if [[ -d "$PREFIX" ]]; then
    TMPDIR_CDH="$HOME/.atila_cdn_$$"
else
    TMPDIR_CDH=$(mktemp -d 2>/dev/null || echo "/data/local/tmp/atila_$$")
fi
mkdir -p "$TMPDIR_CDH"
trap 'rm -rf "$TMPDIR_CDH"' EXIT

TARGET=""
FOUND=0
TOTAL_STEPS=6
CURRENT_STEP=0

# --- BANNER CON NOMBRE ---
show_banner() {
echo -e "
${BLUE}╔════════════════════════════════════════╗${NC}
${BLUE}║${NC}  ${BOLD}${CYAN}🦅 ATILA-CDN-TEST v$VERSION ${NC}${BLUE}  ║${NC}
${BLUE}╚════════════════════════════════════════╝${NC}
${GRAY}   100% FREE | Termux Optimized | Parallel${NC}
"
}

# --- BARRA DE PROGRESO ---
progress_bar() {
  local step=$1 total=$2 msg=$3
  local pct=$((step * 100 / total))
  local filled=$((pct / 5))
  local empty=$((20 - filled))
  printf "\r${CYAN}[%s%s] ${pct}%%${NC} %s" \
    "$(printf '█%.0s' $(seq 1 $filled 2>/dev/null))" \
    "$(printf '░%.0s' $(seq 1 $empty 2>/dev/null))" \
    "$msg"
}

log() { echo -e "\n${CYAN}[•]${NC} $1" >&2; }
ok() { echo -e "${GREEN}[✓]${NC} $1" >&2; ((FOUND++)); }
warn() { echo -e "${YELLOW}[!]${NC} $1" >&2; }

# --- DEPENDENCIAS ---
check_deps() {
  progress_bar 1 $TOTAL_STEPS "Verificando dependencias..."
  for cmd in curl dig grep awk sed jq; do
    command -v "$cmd" &>/dev/null || { warn "Instalando $cmd..."; pkg install -y "$cmd" &>/dev/null || true; }
  done
  echo -e "\r${GREEN}[✓]${NC} Dependencias listas!              "
}

# --- ¿ES CDN? ---
is_cdn() {
  local ip=$1
  if ! [[ -f "$TMPDIR_CDH/cf.txt" ]]; then
    curl -s https://www.cloudflare.com/ips-v4 -o "$TMPDIR_CDH/cf.txt" 2>/dev/null || touch "$TMPDIR_CDH/cf.txt"
  fi
  grep -q "^$ip$" "$TMPDIR_CDH/cf.txt" 2>/dev/null && { echo "CLOUDFLARE"; return 0; }
  local w=$(timeout 3 whois "$ip" 2>/dev/null | tr '[:upper:]' '[:lower:]' | head -20)
  echo "$w" | grep -qE 'cloudflare|akamai|fastly|amazon|azure|google|edgecast' && { echo "CDN"; return 0; }
  echo "ORIGEN"
}

# --- VALIDAR IP como proxy ---
check_proxy() {
  local ip=$1 domain=$2
  local code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 4 -H "Host: $domain" "http://$ip" 2>/dev/null)
  case "$code" in
    200|201|202|204|301|302|307) echo "✅ $code" ;;
    403|405|429) echo "⚠️ $code" ;;
    *) echo "❌ $code" ;;
  esac
}

# --- WORDLIST AMPLIADA (200+ subdominios comunes) ---
get_wordlist() {
cat << 'EOF'
www mail ftp api admin dev staging test blog shop store app mobile m m1 dev1 api1
web server ns ns1 ns2 dns cpanel webmail smtp pop imap vpn ssh sftp
panel control dashboard manage manager portal gateway proxy lb loadbalancer
cdn static assets media images img files upload download backup db database
mysql postgres mongodb redis cache memcache queue worker job cron scheduler
git svn repo repository code source src build ci cd jenkins travis circleci
gitlab github bitbucket jira confluence slack teams zoom meet conference
staging1 staging2 dev1 dev2 test1 test2 prod production preprod uat qa
internal internal-api external external-api public public-api private
v1 v2 v3 beta alpha rc release latest current legacy old new
support help docs documentation wiki kb knowledgebase faq contact sales
marketing blog news press media tv radio stream live video audio podcast
forum community social network chat messenger bot webhook callback
auth login signin register signup account profile user users admin1 admin2
root superuser sysadmin ops devops infra infrastructure cloud aws azure gcp
EOF
}

# --- MÉTODOS DE BÚSQUEDA (con paralelismo ligero) ---

# 1. DNS Directo
search_dns() {
  progress_bar 2 $TOTAL_STEPS "DNS directo..."
  dig +short +timeout=3 "$TARGET" A 2>/dev/null | sort -u | while read -r ip; do
    [[ -z "$ip" ]] && continue
    local t=$(is_cdn "$ip")
    [[ "$t" != "ORIGEN" ]] && continue
    local v=$(check_proxy "$ip" "$TARGET")
    echo "  $ip [DNS] $v" &
  done
  wait
}

# 2. crt.sh (certificados SSL)
search_crtsh() {
  progress_bar 3 $TOTAL_STEPS "Subdominios en crt.sh..."
  local json=$(curl -s --max-time 30 "https://crt.sh/?q=%25.$TARGET&output=json" 2>/dev/null)
  [[ -z "$json" || "$json" == *"error"* ]] && { warn "crt.sh sin datos"; return; }
  echo "$json" | jq -r '.[].name_value' 2>/dev/null | sed 's/\*\.//g' | tr ',' '\n' | sort -u | grep -v "^$TARGET$" | head -60 | while read -r sub; do
    [[ -z "$sub" ]] && continue
    local sip=$(dig +short +timeout=3 "$sub" A 2>/dev/null | head -1)
    [[ -z "$sip" ]] && continue
    local t=$(is_cdn "$sip")
    [[ "$t" != "ORIGEN" ]] && continue
    local v=$(check_proxy "$sip" "$TARGET")
    echo "  $sip [$sub] $v" &
    sleep 0.5
  done
  wait
}

# 3. DNSDumpster
search_dnsdumpster() {
  progress_bar 4 $TOTAL_STEPS "DNSDumpster..."
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
    echo "  $ip [DNSDumpster] $v" &
  done
  wait
}

# 4. AlienVault OTX
search_otx() {
  progress_bar 5 $TOTAL_STEPS "AlienVault OTX..."
  local json=$(curl -s --max-time 20 "https://otx.alienvault.com/api/v1/indicators/domain/$TARGET/passive_dns" 2>/dev/null)
  [[ -z "$json" || "$json" == *"error"* ]] && { warn "OTX sin datos"; return; }
  echo "$json" | jq -r '.passive_dns[].address' 2>/dev/null | grep -E '^[0-9]{1,3}(\.[0-9]{1,3}){3}$' | sort -u | while read -r ip; do
    [[ -z "$ip" ]] && continue
    local t=$(is_cdn "$ip")
    [[ "$t" != "ORIGEN" ]] && continue
    local v=$(check_proxy "$ip" "$TARGET")
    echo "  $ip [OTX] $v" &
  done
  wait
}

# 5. Brute-force con wordlist ampliada + paralelismo
search_brute() {
  progress_bar 6 $TOTAL_STEPS "Brute-force (200+ subs)..."
  local subs=$(get_wordlist)
  local pids=()
  local count=0
  for s in $subs; do
    local sub="$s.$TARGET"
    (
      local sip=$(dig +short +timeout=2 "$sub" A 2>/dev/null | head -1)
      [[ -z "$sip" ]] && exit 0
      local t=$(is_cdn "$sip")
      [[ "$t" != "ORIGEN" ]] && exit 0
      local v=$(check_proxy "$sip" "$TARGET")
      echo "  $sip [$sub] $v"
    ) &
    pids+=($!)
    ((count++))
    # Limitar a 5 procesos paralelos para no saturar Termux
    if [[ $((count % 5)) -eq 0 ]]; then
      for pid in "${pids[@]}"; do wait "$pid" 2>/dev/null; done
      pids=()
    fi
    sleep 0.2
  done
  # Esperar los últimos
  for pid in "${pids[@]}"; do wait "$pid" 2>/dev/null; done
}

# --- MAIN ---
[[ -z "$1" || "$1" != "-t" ]] && { echo -e "${RED}Uso:${NC} $0 -t dominio.com"; exit 1; }
TARGET="$2"
[[ -z "$TARGET" ]] && { echo -e "${RED}Uso:${NC} $0 -t dominio.com"; exit 1; }
TARGET=$(echo "$TARGET" | sed 's|http[s]*://||;s|/.*||;s|^www\.||')

show_banner
check_deps
log "Escaneando: ${BOLD}$TARGET${NC}"
echo ""

# Ejecutar búsquedas con progreso
search_dns
search_crtsh
search_dnsdumpster
search_otx
search_brute

# Resumen final
echo -e "\n\n${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║${NC}  ${BOLD}🎯 POSIBLES PROXYS ENCONTRADOS: $FOUND ${NC}${GREEN}║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
if [[ $FOUND -eq 0 ]]; then
  echo -e "${RED}⚠️  No se encontraron IPs de origen públicas.${NC}"
  echo -e "${YELLOW}💡 Consejos:${NC}"
  echo "   • Prueba subdominios: api.$TARGET, dev.$TARGET, admin.$TARGET"
  echo "   • Intenta en otro horario (rate-limit de APIs)"
  echo "   • Algunos dominios están 100% detrás de CDN"
else
  echo -e "${GRAY}Usa: curl -H \"Host: $TARGET\" http://<IP>${NC}"
  echo -e "${GRAY}O como proxy: curl -x http://<IP>:80 \"http://$TARGET\"${NC}"
fi
echo ""

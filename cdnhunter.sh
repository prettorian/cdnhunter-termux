#!/usr/bin/env bash
# ==============================================================================
# CDNHUNTER PRO v5.2 - Edición "Free & Robust" (TERMUX COMPATIBLE + LF)
# ==============================================================================
set -o pipefail
VERSION="5.2-FREE-ENHANCED-TERMUX"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; PURPLE='\033[0;35m'; CYAN='\033[0;36m'
WHITE='\033[1;37m'; GRAY='\033[0;90m'; NC='\033[0m'; BOLD='\033[1m'

# 🔧 FIX TERMUX: /tmp no existe por defecto
if [[ -d "$PREFIX" ]]; then
    TMPDIR_CDH="$HOME/.cdnhunter_tmp_$$"
else
    TMPDIR_CDH=$(mktemp -d /tmp/cdhunter.XXXXXX 2>/dev/null || mktemp -d -t cdnhunter)
fi
mkdir -p "$TMPDIR_CDH"
trap 'rm -rf "$TMPDIR_CDH"' EXIT

declare -a RESULTS=()
VERBOSE=0
OUTPUT_FILE=""
TARGET=""

log() {
  local level=$1; shift
  local color="${NC}"
  [[ "$level" == "INFO" ]] && color="${BLUE}"
  [[ "$level" == "OK" ]] && color="${GREEN}"
  [[ "$level" == "WARN" ]] && color="${YELLOW}"
  [[ "$level" == "ERR" ]] && color="${RED}"
  [[ "$level" == "DEBUG" && $VERBOSE -eq 1 ]] && color="${GRAY}" || return 0
  echo -e "${color}[$level]${NC} $*" >&2
}

random_ua() {
  local agents=(
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.2 Safari/605.1.15"
    "Mozilla/5.0 (X11; Linux x86_64; rv:109.0) Gecko/20100101 Firefox/115.0"
    "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
  )
  echo "${agents[$RANDOM % ${#agents[@]}]}"
}

sleep_api() { sleep $(( (RANDOM % 3) + 1 )); }

check_deps() {
  local deps=("curl" "dig" "grep" "awk" "sed" "sort" "uniq" "jq" "whois")
  local missing=()
  for cmd in "${deps[@]}"; do command -v "$cmd" &>/dev/null || missing+=("$cmd"); done
  if [[ ${#missing[@]} -gt 0 ]]; then
    log "WARN" "Faltan herramientas: ${missing[*]}. Intentando instalar..."
    if command -v pkg &>/dev/null; then
      pkg install -y "${missing[@]}" &>/dev/null
    elif command -v apt &>/dev/null; then
      sudo apt update -qq &>/dev/null && sudo apt install -y -qq "${missing[@]}" &>/dev/null
    else
      log "ERR" "Instala manualmente: ${missing[*]}"; exit 1
    fi
    log "OK" "Dependencias resueltas."
  fi
}

init_cdn_cache() {
  log "INFO" "Cargando rangos CDN oficiales..."
  curl -s --max-time 10 https://www.cloudflare.com/ips-v4 -o "$TMPDIR_CDH/cf_v4.txt" 2>/dev/null || touch "$TMPDIR_CDH/cf_v4.txt"
  curl -s --max-time 10 https://www.cloudflare.com/ips-v6 -o "$TMPDIR_CDH/cf_v6.txt" 2>/dev/null || touch "$TMPDIR_CDH/cf_v6.txt"
}

is_cdn_ip() {
  local ip=$1
  if command -v ipcalc &>/dev/null && ipcalc -n "$ip" &>/dev/null; then
    local net=$(ipcalc -n "$ip" 2>/dev/null | awk '{print $2}')
    if grep -q "$net" "$TMPDIR_CDH/cf_v4.txt" 2>/dev/null || grep -q "$net" "$TMPDIR_CDH/cf_v6.txt" 2>/dev/null; then
      echo "☁️  Cloudflare"; return 0
    fi
  fi
  local whois_out
  whois_out=$(timeout 5 whois "$ip" 2>/dev/null) || { echo "⏱️ Timeout WHOIS"; return 2; }
  if echo "$whois_out" | grep -qiE 'cloudflare|amazon|akamai|fastly|google cloud|azure|microsoft|edgecast|limelight|incapsula'; then
    local provider=$(echo "$whois_out" | grep -iE 'orgname|owner|descr' | head -1 | sed 's/.*://;s/^ *//')
    echo "📦 CDN Detectado (${provider})"; return 1
  fi
  echo "🎯 Posible Origen"; return 0
}

verify_origin() {
  local ip=$1 domain=$2
  local code
  code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 6 -H "Host: $domain" -A "$(random_ua)" "http://$ip" 2>/dev/null) || code="000"
  [[ "$code" =~ ^[23] ]] && return 0 || return 1
}

store_result() { RESULTS+=("$1|$2|$3|$4"); }

method_dns_direct() {
  local domain=$1
  log "INFO" "[1] Resolución DNS directa..."
  local ips=$(dig +short +timeout=3 "$domain" A 2>/dev/null | sort -u)
  [[ -z "$ips" ]] && { log "WARN" "Sin registros A."; return; }
  while read -r ip; do
    [[ -z "$ip" ]] && continue
    local prov=$(is_cdn_ip "$ip")
    local status="DNS_ACTUAL"
    verify_origin "$ip" "$domain" && status+="✅" || status+="❌"
    log "OK" "$ip -> $prov [$status]"
    store_result "$ip" "DNS_DIRECT" "A" "$prov|$status"
  done <<< "$ips"
}

method_crt_sh() {
  local domain=$1
  log "INFO" "[2] Certificados SSL (crt.sh)..."
  local json=$(curl -s --max-time 20 -A "$(random_ua)" "https://crt.sh/?q=%25.${domain}&output=json" 2>/dev/null)
  [[ -z "$json" || "$json" == *"[]"* || "$json" == *"error"* ]] && { log "WARN" "Sin datos en crt.sh."; return; }
  local subs=$(echo "$json" | jq -r '.[].name_value' 2>/dev/null | sed 's/\*\.//g' | tr ',' '\n' | sort -u | grep -v "^${domain}$" | head -n 40)
  [[ -z "$subs" ]] && { log "WARN" "No hay subdominios útiles."; return; }
  while read -r sub; do
    [[ -z "$sub" ]] && continue
    local sip=$(dig +short +timeout=3 "$sub" A 2>/dev/null | head -1)
    [[ -z "$sip" ]] && continue
    local prov=$(is_cdn_ip "$sip")
    if [[ "$prov" == *"Origen"* || "$prov" == *"Desconocido"* ]]; then
      local status="FUGA_CANDIDATA"
      verify_origin "$sip" "$domain" && status+="✅" || status+="⚠️"
      log "OK" "[FUGA] $sub -> $sip ($prov) [$status]"
      store_result "$sip" "CRT_SH" "SUBDOMAIN" "$prov|$status"
    fi
    sleep_api
  done <<< "$subs"
}

method_hackertarget() {
  local domain=$1
  log "INFO" "[3] Historial & Zona DNS (HackerTarget)..."
  local res1=$(curl -s --max-time 15 "https://api.hackertarget.com/dnslookup/?q=${domain}" 2>/dev/null) || true
  sleep_api
  local res3=$(curl -s --max-time 15 "https://api.hackertarget.com/zonedns/?q=${domain}" 2>/dev/null) || true
  local all_ips=$(echo -e "$res1"$'\n'"$res3" | grep -oE '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$' | sort -u)
  [[ -z "$all_ips" ]] && { log "WARN" "Sin historial en HackerTarget."; return; }
  while read -r ip; do
    [[ -z "$ip" ]] && continue
    local prov=$(is_cdn_ip "$ip")
    if [[ "$prov" == *"Origen"* || "$prov" == *"Desconocido"* ]]; then
      local status="HISTORICO_POSIBLE"
      verify_origin "$ip" "$domain" && status+="✅" || status+="❌"
      log "OK" "$ip -> $prov [$status]"
      store_result "$ip" "HACKERTARGET" "HISTORY" "$prov|$status"
    fi
    sleep_api
  done <<< "$all_ips"
}

method_viewdns() {
  local domain=$1
  log "INFO" "[4] Historial IP (ViewDNS.info)..."
  local html=$(curl -s --max-time 25 -A "$(random_ua)" "https://viewdns.info/iphistory/?domain=${domain}" 2>/dev/null)
  [[ -z "$html" || "$html" == *"captcha"* || "$html" == *"blocked"* ]] && { log "WARN" "ViewDNS bloqueó."; return; }
  local ips=$(echo "$html" | grep -oE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | sort -u)
  [[ -z "$ips" ]] && { log "WARN" "Sin historial en ViewDNS."; return; }
  while read -r ip; do
    [[ -z "$ip" ]] && continue
    local prov=$(is_cdn_ip "$ip")
    if [[ "$prov" == *"Origen"* || "$prov" == *"Desconocido"* ]]; then
      local status="ORIGEN_ANTIGUO"
      verify_origin "$ip" "$domain" && status+="✅" || status+="⚠️"
      log "OK" "$ip -> $prov [$status]"
      store_result "$ip" "VIEWDNS" "IP_HISTORY" "$prov|$status"
    fi
    sleep_api
  done <<< "$ips"
}

method_mx() {
  local domain=$1
  log "INFO" "[5] Registros MX..."
  local mx=$(dig +short +timeout=3 "$domain" MX 2>/dev/null | awk '{print $2}' | sed 's/\.$//')
  [[ -z "$mx" ]] && { log "WARN" "Sin registros MX."; return; }
  for m in $mx; do
    local mip=$(dig +short +timeout=3 "$m" A 2>/dev/null | head -1)
    [[ -z "$mip" ]] && continue
    local prov=$(is_cdn_ip "$mip")
    if [[ "$prov" == *"Origen"* || "$prov" == *"Desconocido"* ]]; then
      local status="INFRA_MAIL"
      verify_origin "$mip" "$domain" && status+="✅" || status+="❌"
      log "OK" "$m -> $mip ($prov) [$status]"
      store_result "$mip" "MX_CHECK" "MAIL" "$prov|$status"
    fi
  done
}

export_results() {
  echo -e "\n${CYAN}=== RESULTADOS FINALES ===${NC}"
  echo "TARGET: $TARGET | DATE: $(date)"
  echo "----------------------------------------"
  printf "%-18s | %-15s | %-12s | %-30s\n" "IP" "FUENTE" "TIPO" "ESTADO"
  echo "----------------------------------------"
  for res in "${RESULTS[@]}"; do
    IFS='|' read -r ip src tp st <<< "$res"
    printf "%-18s | %-15s | %-12s | %-30s\n" "$ip" "$src" "$tp" "$st"
  done
  echo "----------------------------------------"
}

show_help() {
  echo -e "${BOLD}Uso:${NC} $0 -t dominio.com [-v] [-h]"
  echo -e "  -t  Dominio (requerido)"
  echo -e "  -v  Verbose"
  echo -e "  -h  Ayuda"
  exit 0
}

parse_args() {
  while getopts "t:vh" opt; do
    case $opt in
      t) TARGET="$OPTARG" ;;
      v) VERBOSE=1 ;;
      h) show_help ;;
      *) show_help ;;
    esac
  done
  [[ -z "$TARGET" ]] && { log "ERR" "Falta dominio (-t)"; show_help; }
  TARGET=$(echo "$TARGET" | sed -e 's|http[s]*://||' -e 's|/.*||' -e 's|^www\.||' -e 's|:.*||' | xargs)
  [[ ! "$TARGET" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]] && { log "ERR" "Dominio inválido."; exit 1; }
}

main() {
  parse_args "$@"
  check_deps
  init_cdn_cache
  echo -e "\n${CYAN}${BOLD}  _______  _______  _______  _        _______ ${NC}"
  echo -e "${CYAN} (  ____ )(  ___  )(  ____ \( (    /|(  ____ \\${NC}"
  echo -e "${CYAN} | (    )|| (   ) || (    \/|  \  ( || (    \\/${NC}"
  echo -e "${CYAN} | (____)|| |   | || |      |   \ | || |      ${NC}"
  echo -e "${CYAN} |  _____)| |   | || |      | (\ \) || |      ${NC}"
  echo -e "${CYAN} | (      | |   | || |      | | \   || |      ${NC}"
  echo -e "${CYAN} | )      | (___) || (____/\| )  \  || (____/\\${NC}"
  echo -e "${CYAN} |/       (_______)(_______/|/    )_)(_______/${NC}"
  echo -e "${WHITE}   CDNHUNTER PRO v${VERSION} - Free & Robust${NC}\n"
  log "INFO" "Iniciando escaneo sobre: ${BOLD}$TARGET${NC}"
  method_dns_direct "$TARGET"
  method_mx "$TARGET"
  method_crt_sh "$TARGET"
  method_hackertarget "$TARGET"
  method_viewdns "$TARGET"
  export_results
  echo -e "\n${CYAN}========================================${NC}\n${GREEN}[+] Escaneo finalizado.${NC}\n${GRAY}Prueba: curl -H \"Host: $TARGET\" http://<IP>${NC}\n${CYAN}========================================${NC}"
}

main "$@"

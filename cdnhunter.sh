#!/usr/bin/env bash
# ==============================================================================
# CDNHUNTER PRO v5.2 - Edición "Pantalla + HTML Opcional"
# Compatible: Termux, Linux, macOS
# ==============================================================================
set -o pipefail
VERSION="5.2-SCREEN-HTML"
# --- CONFIGURACIÓN & GLOBALES ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; PURPLE='\033[0;35m'; CYAN='\033[0;36m'
WHITE='\033[1;37m'; GRAY='\033[0;90m'; NC='\033[0m'
BOLD='\033[1m'

# 🔧 FIX TERMUX
if [[ -d "$PREFIX" ]]; then
    TMPDIR_CDH="$HOME/.cdnhunter_tmp_$$"
else
    TMPDIR_CDH=$(mktemp -d /tmp/cdhunter.XXXXXX 2>/dev/null || mktemp -d -t cdnhunter)
fi
mkdir -p "$TMPDIR_CDH"
trap 'rm -rf "$TMPDIR_CDH"' EXIT

declare -a RESULTS=()
VERBOSE=0
TARGET=""
OPEN_HTML=0

# --- UTILIDADES ---
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

# --- DEPENDENCIAS ---
check_deps() {
local deps=("curl" "dig" "grep" "awk" "sed" "sort" "uniq" "jq" "whois")
local missing=()
for cmd in "${deps[@]}"; do command -v "$cmd" &>/dev/null || missing+=("$cmd"); done
if [[ ${#missing[@]} -gt 0 ]]; then
log "WARN" "Faltan herramientas: ${missing[*]}. Intentando instalar..."
if command -v pkg &>/dev/null; then
pkg install -y ${missing[*]} &>/dev/null
elif command -v apt &>/dev/null; then
sudo apt update -qq &>/dev/null && sudo apt install -y -qq ${missing[*]} &>/dev/null
else
log "ERR" "Instala manualmente: ${missing[*]}"; exit 1
fi
log "OK" "Dependencias resueltas."
fi
}

# --- DETECCIÓN CDN ---
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

# --- VALIDACIÓN ---
verify_origin() {
local ip=$1 domain=$2
local code
code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 6 \
-H "Host: $domain" -A "$(random_ua)" "http://$ip" 2>/dev/null) || code="000"
[[ "$code" =~ ^[23] ]] && return 0 || return 1
}

# --- RECOLECCIÓN ---
store_result() { RESULTS+=("$1|$2|$3|$4"); }
method_dns_direct() {
local domain=$1; log "INFO" "[1] Resolución DNS directa..."
local ips=$(dig +short +timeout=3 "$domain" A 2>/dev/null | sort -u)
[[ -z "$ips" ]] && { log "WARN" "Sin registros A."; return; }
while read -r ip; do [[ -z "$ip" ]] && continue
local prov=$(is_cdn_ip "$ip"); local status="DNS_ACTUAL"
verify_origin "$ip" "$domain" && status+="✅" || status+="❌"
log "OK" "$ip -> $prov [$status]"; store_result "$ip" "DNS_DIRECT" "A" "$prov|$status"
done <<< "$ips"
}
method_crt_sh() {
local domain=$1; log "INFO" "[2] Certificados SSL (crt.sh)..."
local json=$(curl -s --max-time 20 -A "$(random_ua)" "https://crt.sh/?q=%25.${domain}&output=json" 2>/dev/null)
[[ -z "$json" || "$json" == *"[]"* || "$json" == *"error"* ]] && { log "WARN" "Sin datos en crt.sh."; return; }
local subs=$(echo "$json" | jq -r '.[].name_value' 2>/dev/null | sed 's/\*\.//g' | tr ',' '\n' | sort -u | grep -v "^${domain}$" | head -n 40)
[[ -z "$subs" ]] && { log "WARN" "No hay subdominios útiles."; return; }
while read -r sub; do [[ -z "$sub" ]] && continue
local sip=$(dig +short +timeout=3 "$sub" A 2>/dev/null | head -1); [[ -z "$sip" ]] && continue
local prov=$(is_cdn_ip "$sip")
if [[ "$prov" == *"Origen"* || "$prov" == *"Desconocido"* ]]; then
local status="FUGA_CANDIDATA"; verify_origin "$sip" "$domain" && status+="✅" || status+="⚠️"
log "OK" "[FUGA] $sub -> $sip ($prov) [$status]"; store_result "$sip" "CRT_SH" "SUBDOMAIN" "$prov|$status"
fi; sleep_api; done <<< "$subs"
}
method_hackertarget() {
local domain=$1; log "INFO" "[3] Historial & Zona DNS (HackerTarget)..."
local res1=$(curl -s --max-time 15 "https://api.hackertarget.com/dnslookup/?q=${domain}" 2>/dev/null) || true
sleep_api; local res3=$(curl -s --max-time 15 "https://api.hackertarget.com/zonedns/?q=${domain}" 2>/dev/null) || true
local all_ips=$(echo -e "$res1\n$res3" | grep -oE '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$' | sort -u)
[[ -z "$all_ips" ]] && { log "WARN" "Sin historial en HackerTarget."; return; }
while read -r ip; do [[ -z "$ip" ]] && continue
local prov=$(is_cdn_ip "$ip")
if [[ "$prov" == *"Origen"* || "$prov" == *"Desconocido"* ]]; then
local status="HISTORICO_POSIBLE"; verify_origin "$ip" "$domain" && status+="✅" || status+="❌"
log "OK" "$ip -> $prov [$status]"; store_result "$ip" "HACKERTARGET" "HISTORY" "$prov|$status"
fi; sleep_api; done <<< "$all_ips"
}
method_viewdns() {
local domain=$1; log "INFO" "[4] Historial IP (ViewDNS.info)..."
local html=$(curl -s --max-time 25 -A "$(random_ua)" "https://viewdns.info/iphistory/?domain=${domain}" 2>/dev/null)
[[ -z "$html" || "$html" == *"captcha"* || "$html" == *"blocked"* ]] && { log "WARN" "ViewDNS bloqueó."; return; }
local ips=$(echo "$html" | grep -oE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | sort -u)
[[ -z "$ips" ]] && { log "WARN" "Sin historial en ViewDNS."; return; }
while read -r ip; do [[ -z "$ip" ]] && continue
local prov=$(is_cdn_ip "$ip")
if [[ "$prov" == *"Origen"* || "$prov" == *"Desconocido"* ]]; then
local status="ORIGEN_ANTIGUO"; verify_origin "$ip" "$domain" && status+="✅" || status+="⚠️"
log "OK" "$ip -> $prov [$status]"; store_result "$ip" "VIEWDNS" "IP_HISTORY" "$prov|$status"
fi; sleep_api; done <<< "$ips"
}
method_mx() {
local domain=$1; log "INFO" "[5] Registros MX..."
local mx=$(dig +short +timeout=3 "$domain" MX 2>/dev/null | awk '{print $2}' | sed 's/\.$//')
[[ -z "$mx" ]] && { log "WARN" "Sin registros MX."; return; }
for m in $mx; do
local mip=$(dig +short +timeout=3 "$m" A 2>/dev/null | head -1); [[ -z "$mip" ]] && continue
local prov=$(is_cdn_ip "$mip")
if [[ "$prov" == *"Origen"* || "$prov" == *"Desconocido"* ]]; then
local status="INFRA_MAIL"; verify_origin "$mip" "$domain" && status+="✅" || status+="❌"
log "OK" "$m -> $mip ($prov) [$status]"; store_result "$mip" "MX_CHECK" "MAIL" "$prov|$status"
fi; done
}

# --- EXPORTACIÓN PANTALLA ---
export_results_screen() {
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

# --- EXPORTACIÓN HTML (AUTO-ABRIR) ---
export_results_html() {
local html="$TMPDIR_CDH/report_$(date +%s).html"
cat > "$html" << 'EOF'
<!DOCTYPE html><html lang="es"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>CDNHUNTER Report</title><style>body{font-family:system-ui,-apple-system,sans-serif;background:#0d1117;color:#c9d1d9;margin:0;padding:20px}
h1{color:#58a6ff;text-align:center}.meta{text-align:center;color:#8b949e;margin-bottom:20px;font-size:0.9em}
table{width:100%;border-collapse:collapse;background:#161b22;border-radius:8px;overflow:hidden}
th{background:#21262d;color:#58a6ff;padding:12px;text-align:left;font-size:0.9em}td{padding:10px;border-bottom:1px solid #30363d;font-size:0.9em}
tr:hover{background:#1c2128}.ok{color:#3fb950;font-weight:bold}.warn{color:#d29922}.err{color:#f85149}
.legend{margin-top:20px;text-align:center;font-size:0.85em;color:#8b949e}
@media(max-width:600px){table{font-size:0.8em}th,td{padding:8px}}</style></head><body>
EOF
echo "<h1>🕵️‍♂️ CDNHUNTER PRO Report</h1><div class='meta'><b>Target:</b> $TARGET | <b>Date:</b> $(date) | <b>Ver:</b> $VERSION</div>" >> "$html"
echo "<table><tr><th>IP</th><th>Fuente</th><th>Tipo</th><th>Estado</th></tr>" >> "$html"
for res in "${RESULTS[@]}"; do
IFS='|' read -r ip src tp st <<< "$res"
local cls=""; [[ "$st" == *"✅"* ]] && cls="ok"; [[ "$st" == *"⚠️"* ]] && cls="warn"; [[ "$st" == *"❌"* ]] && cls="err"
echo "<tr><td>$ip</td><td>$src</td><td>$tp</td><td class='$cls'>$st</td></tr>" >> "$html"
done
cat >> "$html" << 'EOF'
</table><div class='legend'>✅ Posible Origen | ⚠️ Verificar | ❌ CDN/Bloqueado</div></body></html>
EOF
if command -v termux-open &>/dev/null; then termux-open "$html"; log "OK" "Reporte HTML abierto en el navegador."; else log "INFO" "Guardado en: $html"; fi
}

# --- CLI & MAIN ---
show_help() { echo -e "${BOLD}Uso:${NC} $0 -t dominio.com [-v] [-html] [-h]\n  -t     Dominio (requerido)\n  -v     Verbose\n  -html  Genera y abre reporte visual\n  -h     Ayuda"; exit 0; }
parse_args() {
while getopts "t:vh-:" opt; do
case $opt in
t) TARGET="$OPTARG" ;; v) VERBOSE=1 ;; h) show_help ;;
-) [[ "$OPTARG" == "html" ]] && OPEN_HTML=1 ;; *) show_help ;;
esac; done
[[ -z "$TARGET" ]] && { log "ERR" "Falta dominio (-t)"; show_help; }
TARGET=$(echo "$TARGET" | sed -e 's|http[s]*://||' -e 's|/.*||' -e 's|^www\.||' -e 's|:.*||' | xargs)
[[ ! "$TARGET" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]] && { log "ERR" "Dominio inválido."; exit 1; }
}
main() {
parse_args "$@"; check_deps; init_cdn_cache
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
method_dns_direct "$TARGET"; method_mx "$TARGET"; method_crt_sh "$TARGET"; method_hackertarget "$TARGET"; method_viewdns "$TARGET"
if [[ $OPEN_HTML -eq 1 ]]; then export_results_html; else export_results_screen; fi
echo -e "\n${CYAN}========================================${NC}\n${GREEN}[+] Escaneo finalizado.${NC}\n${GRAY}Prueba manual: curl -H \"Host: $TARGET\" http://<IP>${NC}\n${CYAN}========================================${NC}"
}
main "$@"

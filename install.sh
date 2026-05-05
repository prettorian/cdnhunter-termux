#!/usr/bin/env bash
# ==============================================================================
# CDNHUNTER INSTALLER - Instalador automático para Termux/Linux
# Uso: curl -sL https://raw.githubusercontent.com/prettorian/cdnhunter-termux/main/install.sh | bash
# ==============================================================================
set -e

# Colores
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'

# Configuración
REPO_URL="https://raw.githubusercontent.com/prettorian/cdnhunter-termux/main"
INSTALL_DIR="$HOME/cdnhunter"
SCRIPT_NAME="cdnhunter.sh"
ALIAS_NAME="cdnhunter"

log() { echo -e "${BLUE}[+]${NC} $1"; }
ok() { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err() { echo -e "${RED}[✗]${NC} $1" >&2; }

# Detectar entorno
is_termux() { [[ -n "$PREFIX" ]]; }
is_root() { [[ $EUID -eq 0 ]]; }

# Instalar dependencias según entorno
install_deps() {
log "Verificando dependencias..."
local deps=("curl" "jq" "whois" "dnsutils" "ipcalc")
local missing=()

for cmd in "${deps[@]}"; do
    command -v "$cmd" &>/dev/null || missing+=("$cmd")
done

if [[ ${#missing[@]} -gt 0 ]]; then
    log "Instalando: ${missing[*]}"
    if is_termux; then
        pkg update -y &>/dev/null
        pkg install -y "${missing[@]}" &>/dev/null
    elif command -v apt &>/dev/null; then
        if is_root; then
            apt update -qq &>/dev/null && apt install -y -qq "${missing[@]}" &>/dev/null
        else
            warn "Se requiere sudo para instalar paquetes. Intentando con sudo..."
            sudo apt update -qq &>/dev/null && sudo apt install -y -qq "${missing[@]}" &>/dev/null || \
            { err "No se pudieron instalar dependencias. Instálalas manualmente: ${missing[*]}"; return 1; }
        fi
    elif command -v dnf &>/dev/null; then
        sudo dnf install -y "${missing[@]}" &>/dev/null
    elif command -v pacman &>/dev/null; then
        sudo pacman -S --noconfirm "${missing[@]}" &>/dev/null
    else
        warn "Gestor de paquetes no detectado. Verifica que tengas: ${missing[*]}"
    fi
    ok "Dependencias listas."
else
    ok "Todas las dependencias ya están instaladas."
fi
}

# Descargar script principal
download_script() {
log "Descargando $SCRIPT_NAME..."
mkdir -p "$INSTALL_DIR"
curl -sL "$REPO_URL/$SCRIPT_NAME" -o "$INSTALL_DIR/$SCRIPT_NAME" || {
    err "No se pudo descargar el script. Verifica la URL: $REPO_URL/$SCRIPT_NAME"
    return 1
}
chmod +x "$INSTALL_DIR/$SCRIPT_NAME"
ok "Script descargado en: $INSTALL_DIR/$SCRIPT_NAME"
}

# Configurar alias global
setup_alias() {
log "Configurando alias '$ALIAS_NAME'..."
local shell_rc=""

# Detectar shell y archivo de configuración
if [[ -n "$ZSH_VERSION" ]] || grep -q "zsh" /etc/shells 2>/dev/null; then
    shell_rc="$HOME/.zshrc"
elif [[ -n "$BASH_VERSION" ]] || grep -q "bash" /etc/shells 2>/dev/null; then
    shell_rc="$HOME/.bashrc"
else
    shell_rc="$HOME/.profile"
fi

# Crear alias seguro que funcione en Termux y Linux
local alias_cmd="alias $ALIAS_NAME='bash $INSTALL_DIR/$SCRIPT_NAME'"

# Evitar duplicados
if ! grep -q "alias $ALIAS_NAME=" "$shell_rc" 2>/dev/null; then
    echo -e "\n# CDNHUNTER ALIAS (auto-generado)\n$alias_cmd" >> "$shell_rc"
    ok "Alias añadido a $shell_rc"
else
    warn "El alias ya existe en $shell_rc"
fi

# Aplicar alias en la sesión actual
eval "$alias_cmd" 2>/dev/null || true
ok "Alias '$ALIAS_NAME' disponible en esta sesión."
}

# Limpieza de temporales al cerrar (opcional pero recomendado)
setup_cleanup() {
log "Configurando limpieza automática de temporales..."
local cleanup_hook="
# Limpieza CDNHUNTER al cerrar sesión
clean_cdhunter_tmp() {
    rm -rf \"$HOME/.cdnhunter_tmp_\"* 2>/dev/null || true
}
# Ejecutar al cerrar terminal
if [[ -n \"\$BASH_VERSION\" ]] || [[ -n \"\$ZSH_VERSION\" ]]; then
    trap clean_cdhunter_tmp EXIT
fi
"

local shell_rc="${ZDOTDIR:-$HOME}/.zshrc"
[[ ! -f "$shell_rc" ]] && shell_rc="$HOME/.bashrc"

if ! grep -q "clean_cdhunter_tmp" "$shell_rc" 2>/dev/null; then
    echo -e "\n# CDNHUNTER CLEANUP\n$cleanup_hook" >> "$shell_rc"
    ok "Limpieza automática configurada."
fi
}

# Mostrar mensaje final
show_finish() {
echo -e "
${CYAN}${BOLD}╔════════════════════════════════════════╗${NC}
${CYAN}${BOLD}║  ✅ CDNHUNTER INSTALADO CORRECTAMENTE  ║${NC}
${CYAN}${BOLD}╚════════════════════════════════════════╝${NC}

${GREEN}📍 Ubicación:${NC} $INSTALL_DIR/$SCRIPT_NAME
${GREEN}🚀 Alias:${NC} $ALIAS_NAME
${GREEN}📦 Versión:${NC} $(grep -oP 'VERSION=\"\K[^\"]+' \"$INSTALL_DIR/$SCRIPT_NAME\" 2>/dev/null || echo 'N/A')

${BOLD}📋 USO RÁPIDO:${NC}
  ${CYAN}$ $ALIAS_NAME -t ejemplo.com${NC}          # Escanear dominio
  ${CYAN}$ $ALIAS_NAME -t ejemplo.com -o salida.txt${NC}  # Guardar resultados
  ${CYAN}$ $ALIAS_NAME -h${NC}                      # Ver ayuda

${YELLOW}💡 TIP:${NC} Si el alias no funciona, reinicia la terminal o ejecuta:
  ${CYAN}source $HOME/.bashrc${NC}  (o ${CYAN}source $HOME/.zshrc${NC})

${GRAY}🔗 Repo: $REPO_URL${NC}
"
}

# MAIN
main() {
echo -e "${BOLD}${CYAN}
  ╔══════════════════════════════╗
  ║  🛠️  CDNHUNTER INSTALLER v1.0 ║
  ╚══════════════════════════════╝${NC}
"

# Verificaciones iniciales
if is_termux; then
    log "Entorno detectado: ${YELLOW}Termux${NC}"
    # En Termux, asegurar permisos de almacenamiento si se necesita
    termux-setup-storage &>/dev/null || true
else
    log "Entorno detectado: ${YELLOW}Linux/macOS${NC}"
fi

# Ejecutar pasos
install_deps || { warn "Continuando sin algunas dependencias..."; }
download_script || exit 1
setup_alias
setup_cleanup
show_finish
}

# Ejecutar
main "$@"

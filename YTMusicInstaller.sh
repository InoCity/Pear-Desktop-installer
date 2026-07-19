#!/bin/bash
set -euo pipefail

# =====================
# Cores
# =====================
GREEN='\033[1;32m'
RED='\033[1;31m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
BLUE='\033[1;34m'
NC='\033[0m'

ok()   { echo -e "${GREEN}✔ $1${NC}"; }
warn() { echo -e "${YELLOW}⚠ $1${NC}"; }
err()  { echo -e "${RED}✖ $1${NC}"; exit 1; }
info() { echo -e "${CYAN}➜ $1${NC}"; }

# =====================
# Header
# =====================
clear
echo -e "${BLUE}"
echo "╔══════════════════════════════╗"
echo "║   YT Music Installer 🎵      ║"
echo "╚══════════════════════════════╝"
echo -e "${NC}"

# =====================
# Spinner
# =====================
spinner() {
    local pid=$1
    local msg="$2"
    local spin='⠋⠙⠸⠴⠦⠇'
    local i=0

    while kill -0 "$pid" 2>/dev/null; do
        printf "\r\033[K${CYAN}%s${NC} %s" "${spin:i++%${#spin}:1}" "$msg"
        sleep 0.08
    done

    printf "\r\033[K"
}

# =====================
# Arquitetura
# =====================
ARCH_RAW="$(uname -m)"
case "$ARCH_RAW" in
    x86_64) ARCH="x86_64" ;;
    aarch64|arm64) ARCH="aarch64" ;;
    *) err "Arquitetura não suportada: $ARCH_RAW" ;;
esac
ok "Arquitetura: $ARCH"

# =====================
# Dependências
# =====================
DEPS=(curl jq pv)
missing=()

for d in "${DEPS[@]}"; do
    command -v "$d" &>/dev/null || missing+=("$d")
done

if [ "${#missing[@]}" -ne 0 ]; then
    warn "Instalando dependências..."
    (sudo dnf install -y curl jq pv >/dev/null 2>&1) &
    spinner $! "Instalando pacotes..."
    ok "Dependências prontas"
else
    ok "Dependências OK"
fi

# =====================
# Diretório
# =====================
YTM_DIR="$HOME/YTMusic"
mkdir -p "$YTM_DIR"

# =====================
# API
# =====================
info "Buscando versão..."

TMP=$(mktemp)
(
curl -sL https://api.github.com/repos/pear-devs/pear-desktop/releases/latest > "$TMP"
) &
spinner $! "Consultando GitHub..."

API=$(cat "$TMP")
rm -f "$TMP"

VERSION=$(echo "$API" | jq -r '.tag_name // "latest"')
VERSION_NUM="${VERSION#v}"
ok "Versão: $VERSION"

APPIMAGE="$YTM_DIR/YouTube-Music-$VERSION_NUM.AppImage"

# =====================
# Reinstalar
# =====================
if [[ -f "$APPIMAGE" ]]; then
    warn "Já instalado"
    read -p "Reinstalar? (y/n) " r
    [[ ! "$r" =~ ^[Yy]$ ]] && exit 0
fi

# =====================
# URL (x86_64 não tem sufixo, aarch64 usa -arm64)
# =====================
if [[ "$ARCH" == "aarch64" ]]; then
    URL=$(echo "$API" | jq -r '
      .assets[]
      | select(.name | endswith(".AppImage") and contains("arm64"))
      | .browser_download_url
    ' | head -n1)
else
    URL=$(echo "$API" | jq -r '
      .assets[]
      | select(.name | endswith(".AppImage") and (contains("arm") | not))
      | .browser_download_url
    ' | head -n1)
fi

[[ -z "$URL" ]] && err "Download não encontrado"
ok "Download encontrado"

# =====================
# Download
# =====================
echo
info "Baixando YouTube Music..."

curl -Ls "$URL" -o - \
| pv -w 60 -p -t -e -r -b -F "%b %t [%r] [%40b]" \
> "$APPIMAGE"

chmod +x "$APPIMAGE"
echo
ok "Download concluído"

# =====================
# Ícone
# =====================
info "Baixando ícone..."

ICON_DIR="$HOME/.local/share/icons/hicolor/256x256/apps"
mkdir -p "$ICON_DIR"

ICON_RAW_URL="https://github.com/InoCity/Pear-Desktop-installer/blob/main/ytmusicicon.png?raw=true"
ICON_DEST="$ICON_DIR/ytmusic.png"

if curl -sL "$ICON_RAW_URL" -o "$ICON_DEST" && [[ -s "$ICON_DEST" ]]; then
    ok "Ícone baixado e instalado"
else
    warn "Não foi possível baixar o ícone"
    rm -f "$ICON_DEST"
fi

# =====================
# Desktop
# =====================
mkdir -p "$HOME/.local/share/applications"

# Remove .desktop de instalações anteriores deste script (nomes/WM class antigos)
rm -f "$HOME/.local/share/applications/ytmusic.desktop"
rm -f "$HOME/.local/share/applications/com.github.th_ch.youtube_music.desktop"

if [[ -f "$ICON_DEST" ]]; then
    ICON_VALUE="ytmusic"
else
    ICON_VALUE="application-x-executable"
fi

DESKTOP_FILE="$HOME/.local/share/applications/com.github.th-ch.youtube-music.desktop"

cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Name=YouTube Music
Exec=$APPIMAGE
Type=Application
Categories=AudioVideo;Music;
Terminal=false
Icon=$ICON_VALUE
StartupWMClass=com.github.th-ch.youtube-music
EOF

chmod +x "$DESKTOP_FILE"

# Atualiza os caches para o ícone/atalho aparecerem imediatamente
command -v update-desktop-database &>/dev/null && update-desktop-database "$HOME/.local/share/applications" >/dev/null 2>&1 || true
command -v gtk-update-icon-cache &>/dev/null && gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" >/dev/null 2>&1 || true

ok "Atalho criado"

# =====================
# Final
# =====================
echo
echo -e "${GREEN}╔══════════════════════════════╗${NC}"
echo -e "${GREEN}║   Instalação concluída 🎉    ║${NC}"
echo -e "${GREEN}╚══════════════════════════════╝${NC}"
echo
echo "Se ainda assim o ícone não pegar na taskbar/dock, feche o app completamente"
echo "(inclusive o processo em segundo plano) e abra de novo — o cache de ícones"
echo "às vezes só atualiza depois de reiniciar o app ou a sessão."
echo

read -p "Executar agora? (y/n) " r
[[ "$r" =~ ^[Yy]$ ]] && "$APPIMAGE" &

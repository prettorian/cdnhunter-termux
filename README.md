# 🕵️‍♂️ CDNHUNTER PRO v5.2
![Version](https://img.shields.io/badge/version-5.2--FREE--ENHANCED--TERMUX-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![Platform](https://img.shields.io/badge/platform-Termux%20%7C%20Linux%20%7C%20macOS-orange)
![Shell](https://img.shields.io/badge/Shell-Bash%204.0%2B-yellow)

> Herramienta avanzada de reconocimiento para descubrir la IP real (origen) detrás de un CDN. Automatiza la enumeración de subdominios, historial DNS, certificados SSL y registros MX con validación activa.

## ✨ Características
- 🔍 **5 métodos de recolección**: DNS directo, crt.sh (certificados), HackerTarget, ViewDNS, Registros MX
- ☁️ **Detección CDN dinámica**: Descarga rangos oficiales de Cloudflare + fallback WHOIS
- ✅ **Validación HTTP activa**: Verifica si la IP responde correctamente con el `Host` del dominio
- 🔄 **Rate-limit & Rotación de User-Agent**: Evita bloqueos automáticos por rate-limit
- 📊 **Exportación profesional**: Resultados en tabla legible con estados `✅`/`⚠️`/`❌`
- 📱 **100% compatible con Termux**: Fix nativo para `/tmp`, detección automática de entorno

## 📦 Instalación Rápida

### 🚀 Opción 1: Instalador Automático (Recomendado)
```bash
curl -sL https://raw.githubusercontent.com/prettorian/cdnhunter-termux/main/install.sh | bash

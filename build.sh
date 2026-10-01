#!/bin/bash
# Compila o MacTranscribe.app sem Xcode — só Command Line Tools.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/MacTranscribe.app"
IDENTITY="MacTranscribe Local Dev"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "→ compilando…"
swiftc \
    -swift-version 5 \
    -O \
    -target arm64-apple-macos13.0 \
    -o "$APP/Contents/MacOS/MacTranscribe" \
    Sources/*.swift \
    -framework AppKit \
    -framework AVFoundation \
    -framework Carbon \
    -framework Security

cp Info.plist "$APP/Contents/Info.plist"

# Assinatura estável mantém a permissão de Acessibilidade entre rebuilds;
# ad-hoc faz o macOS esquecê-la a cada build.
# Resolve pelo SHA-1 da identidade VÁLIDA: assinar pelo nome quebra com
# "ambiguous (matches ... and ...)" se houver certificados homônimos, e pode acabar
# pegando um não confiável — o que reiniciaria o problema de permissão.
IDENTITY_HASH="$(security find-identity -v -p codesigning 2>/dev/null \
                 | awk -v name="$IDENTITY" 'index($0, name) { print $2; exit }')"

if [[ -n "$IDENTITY_HASH" ]]; then
    echo "→ assinando com \"$IDENTITY\" ($IDENTITY_HASH)…"
    /usr/libexec/PlistBuddy -c "Add :MTSigningMode string identity" "$APP/Contents/Info.plist" >/dev/null
    codesign --force --sign "$IDENTITY_HASH" "$APP"   # sem hardened runtime: exigiria entitlement de microfone
else
    echo "→ assinando ad-hoc (rode ./setup-signing.sh para parar de reautorizar a cada build)…"
    /usr/libexec/PlistBuddy -c "Add :MTSigningMode string adhoc" "$APP/Contents/Info.plist" >/dev/null
    codesign --force --sign - --identifier com.allan.mactranscribe "$APP"
fi

echo "✅ pronto: $APP"

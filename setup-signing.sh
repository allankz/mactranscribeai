#!/bin/bash
# Cria uma identidade de assinatura local e estável para o MacTranscribe.
#
# POR QUÊ: assinado ad-hoc, o macOS amarra a permissão de Acessibilidade ao hash do
# binário. Todo rebuild gera um hash novo e a autorização que você deu vira órfã — daí
# o app fica pedindo permissão toda hora. Com um certificado fixo, o TCC passa a chavear
# pelo certificado, e a autorização sobrevive a quantos rebuilds você fizer.
#
# O QUE ELE MUDA NA SUA MÁQUINA:
#   1. cria um certificado auto-assinado "MacTranscribe Local Dev" (validade 10 anos)
#      no seu keychain de login;
#   2. marca esse certificado como confiável APENAS para code signing (-p codeSign);
#   3. o passo 2 abre um diálogo do macOS pedindo sua senha.
#
# O certificado só pode assinar código localmente. Ele não é uma autoridade para TLS,
# não afeta navegação, e não sai da sua máquina.
#
# PARA DESFAZER:  ./setup-signing.sh --remove

set -euo pipefail
cd "$(dirname "$0")"

NAME="MacTranscribe Local Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if [[ "${1:-}" == "--remove" ]]; then
    echo "→ removendo trust e certificado…"
    security remove-trusted-cert "$HOME/.mactranscribe-signing/cert.pem" 2>/dev/null || true
    security delete-identity -c "$NAME" "$KEYCHAIN" 2>/dev/null || true
    rm -rf "$HOME/.mactranscribe-signing"
    echo "✅ removido. Os próximos builds voltam a ser ad-hoc."
    exit 0
fi

if security find-identity -v -p codesigning | grep -q "$NAME"; then
    echo "✅ a identidade \"$NAME\" já existe — nada a fazer."
    echo "   Rode ./build.sh; ele vai usá-la automaticamente."
    exit 0
fi

DIR="$HOME/.mactranscribe-signing"
mkdir -p "$DIR"
chmod 700 "$DIR"

echo "→ gerando certificado auto-assinado…"
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$DIR/key.pem" -out "$DIR/cert.pem" \
    -subj "/CN=$NAME" \
    -addext "basicConstraints=critical,CA:false" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null
[[ -s "$DIR/cert.pem" ]] || { echo "❌ falha ao gerar o certificado"; exit 1; }
chmod 600 "$DIR/key.pem"

# Senha temporária: o `security` do macOS rejeita p12 de senha vazia ("MAC verification
# failed"). O p12 é apagado logo depois do import.
P12PASS="$(openssl rand -hex 16)"
openssl pkcs12 -export -out "$DIR/id.p12" \
    -inkey "$DIR/key.pem" -in "$DIR/cert.pem" \
    -passout "pass:$P12PASS" -name "$NAME"
[[ -s "$DIR/id.p12" ]] || { echo "❌ falha ao empacotar o certificado"; exit 1; }

echo "→ importando no keychain de login…"
security import "$DIR/id.p12" -k "$KEYCHAIN" -P "$P12PASS" -T /usr/bin/codesign >/dev/null
rm -f "$DIR/id.p12"
security set-key-partition-list -S apple-tool:,apple: -s "$KEYCHAIN" >/dev/null 2>&1 || true

echo "→ marcando como confiável para code signing (o macOS vai pedir sua senha)…"
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$DIR/cert.pem"

if security find-identity -v -p codesigning | grep -q "$NAME"; then
    echo
    echo "✅ identidade pronta."
    echo
    echo "Agora, para limpar as autorizações órfãs dos builds ad-hoc antigos:"
    echo "    tccutil reset Accessibility com.allan.mactranscribe"
    echo "    tccutil reset Microphone    com.allan.mactranscribe"
    echo
    echo "Depois rode ./build.sh e autorize UMA vez. Não pergunta mais."
else
    echo "❌ a identidade não ficou válida. Confira em Acesso às Chaves se o certificado"
    echo "   \"$NAME\" está com 'Assinatura de código: Sempre Confiar'."
    exit 1
fi

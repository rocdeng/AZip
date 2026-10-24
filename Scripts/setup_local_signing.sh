#!/usr/bin/env bash
set -euo pipefail

identity="AZip Local Code Signing"
keychain="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning "$keychain" | grep -Fq "\"$identity\""; then
  echo "固定签名身份已存在：$identity"
  exit 0
fi

temp_dir="$(mktemp -d /private/tmp/azip-signing.XXXXXX)"

cleanup() {
  if [[ -d "$temp_dir" ]]; then
    mkdir -p "$HOME/.Trash"
    mv "$temp_dir" "$HOME/.Trash/azip-signing-$(date +%Y%m%d-%H%M%S)"
  fi
}
trap cleanup EXIT

openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout "$temp_dir/azip.key" \
  -out "$temp_dir/azip.crt" \
  -days 3650 \
  -subj "/CN=$identity/O=AZip Local Development" \
  -addext "keyUsage=digitalSignature" \
  -addext "extendedKeyUsage=codeSigning" \
  -addext "basicConstraints=critical,CA:false" \
  >/dev/null 2>&1

openssl pkcs12 -export -legacy \
  -out "$temp_dir/azip.p12" \
  -inkey "$temp_dir/azip.key" \
  -in "$temp_dir/azip.crt" \
  -passout pass:azip \
  >/dev/null 2>&1

security import "$temp_dir/azip.p12" \
  -k "$keychain" \
  -P azip \
  -T /usr/bin/codesign \
  -T /usr/bin/security \
  >/dev/null

# 仅信任「代码签名」用途，不影响系统对 TLS 等其他证书的信任。
security add-trusted-cert -d -r trustRoot -p codeSign -k "$keychain" "$temp_dir/azip.crt"

if ! security find-identity -v -p codesigning "$keychain" | grep -Fq "\"$identity\""; then
  echo "固定签名身份创建失败：$identity" >&2
  exit 1
fi

echo "固定签名身份已创建：$identity"

#!/bin/sh
#
# validate-supabase-config.sh
# pitgo
#
# Run Script Build Phase — executa ANTES de "Compile Sources" no alvo principal. Valida
# `supabaseUrl`/`supabaseKey` (Build Settings, expostas automaticamente como variáveis de ambiente
# pelo Xcode) e interrompe o build com código de saída != 0 se qualquer regra falhar. Nunca ecoa o
# valor recebido — mensagens citam somente o nome do campo e a regra violada
# (ver contracts/supabase-configuration.md).

set -eu

fail() {
    echo "error: Supabase config — $1"
    exit 1
}

trim() {
    # Remove espaços externos (início/fim), preservando o conteúdo interno.
    printf '%s' "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

# --- supabaseUrl ------------------------------------------------------------------------------

url_trimmed=$(trim "${supabaseUrl:-}")

if [ -z "$url_trimmed" ]; then
    fail "supabaseUrl está ausente ou contém apenas espaços."
fi

case "$url_trimmed" in
    https://*) ;;
    http://*) fail "supabaseUrl usa esquema http:// — apenas https:// é aceito." ;;
    *) fail "supabaseUrl não é uma URI HTTPS absoluta." ;;
esac

# host = tudo depois de "https://" até a primeira "/", "?" ou "#" (ou o fim da string).
url_authority=$(printf '%s' "$url_trimmed" | sed -E 's#^https://##' | sed -E 's#[/?#].*$##')

if [ -z "$url_authority" ]; then
    fail "supabaseUrl não possui host."
fi

case "$url_authority" in
    *@*) fail "supabaseUrl não deve conter user-info (usuário@host)." ;;
esac

url_host=$(printf '%s' "$url_authority" | sed -E 's/:[0-9]+$//')
if [ -z "$url_host" ]; then
    fail "supabaseUrl não possui host."
fi

# --- supabaseKey -------------------------------------------------------------------------------

key_trimmed=$(trim "${supabaseKey:-}")

if [ -z "$key_trimmed" ]; then
    fail "supabaseKey está ausente ou contém apenas espaços."
fi

case "$key_trimmed" in
    sb_secret_*)
        fail "supabaseKey usa um prefixo administrativo (sb_secret_) e não pode ser embutida no app."
        ;;
    sb_publishable_?*)
        # Chave publishable atual com sufixo não vazio — aceita.
        exit 0
        ;;
esac

# Não é sb_publishable_/sb_secret_: só resta o formato de JWT legado (3 segmentos Base64URL).
segment_count=$(printf '%s' "$key_trimmed" | awk -F'.' '{ print NF }')
if [ "$segment_count" -ne 3 ]; then
    fail "supabaseKey não corresponde a nenhum formato aceito (sb_publishable_... ou JWT anon de 3 segmentos)."
fi

jwt_payload_b64url=$(printf '%s' "$key_trimmed" | awk -F'.' '{ print $2 }')
if [ -z "$jwt_payload_b64url" ]; then
    fail "supabaseKey é um JWT malformado (payload ausente)."
fi

# Base64URL -> Base64 padrão, com padding até múltiplo de 4.
b64=$(printf '%s' "$jwt_payload_b64url" | tr '_-' '/+')
remainder=$((${#b64} % 4))
if [ "$remainder" -eq 2 ]; then
    b64="${b64}=="
elif [ "$remainder" -eq 3 ]; then
    b64="${b64}="
elif [ "$remainder" -eq 1 ]; then
    fail "supabaseKey é um JWT malformado (payload com tamanho inválido)."
fi

payload_json=$(printf '%s' "$b64" | base64 -D 2>/dev/null) || fail "supabaseKey é um JWT malformado (payload não decodifica em Base64)."

if [ -z "$payload_json" ]; then
    fail "supabaseKey é um JWT malformado (payload vazio)."
fi

# Extrai todos os valores do claim "role" presentes no payload (sem validar assinatura — só forma).
roles=$(printf '%s' "$payload_json" | grep -Eo '"role"[[:space:]]*:[[:space:]]*"[^"]*"' | sed -E 's/.*:[[:space:]]*"([^"]*)"/\1/')

if [ -z "$roles" ]; then
    fail "supabaseKey é um JWT sem claim 'role' reconhecível."
fi

role_count=$(printf '%s\n' "$roles" | sort -u | wc -l | tr -d '[:space:]')
if [ "$role_count" -gt 1 ]; then
    fail "supabaseKey é um JWT com múltiplos papéis — apenas 'anon' isolado é aceito."
fi

single_role=$(printf '%s\n' "$roles" | head -n 1)
case "$single_role" in
    anon)
        exit 0
        ;;
    service_role)
        fail "supabaseKey é um JWT com role=service_role e não pode ser embutida no app."
        ;;
    *)
        fail "supabaseKey é um JWT com role não reconhecido para uso em cliente."
        ;;
esac

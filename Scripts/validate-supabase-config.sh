#!/bin/sh
#
# validate-supabase-config.sh
# pitgo
#
# Run Script Build Phase — executa ANTES de "Compile Sources" no alvo principal. Valida
# `supabaseUrl`/`supabaseKey` e, desde `019`, também os quatro campos de configuração do mapa
# (`mapStyleUrl`/`mapStyleProviderName`/`mapStyleAttribution`/`mapStyleAttributionUrl`) — todos
# Build Settings expostas automaticamente como variáveis de ambiente pelo Xcode — e interrompe o
# build com código de saída != 0 se qualquer regra falhar. Nunca ecoa o valor recebido; mensagens
# citam somente o nome do campo e a regra violada (ver contracts/supabase-configuration.md e
# specs/019-map-production-tiles/contracts/map-style-build-validation.md). Duas funções, um só
# script/Run Script Build Phase — mesma estrutura de `validateSupabaseConfiguration`/
# `validateMapStyleConfiguration` já usada no `build.gradle.kts` do app Android.

set -eu

fail() {
    echo "error: Supabase config — $1"
    exit 1
}

trim() {
    # Remove espaços externos (início/fim), preservando o conteúdo interno.
    printf '%s' "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

validate_supabase_config() {

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
        return 0
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
        return 0
        ;;
    service_role)
        fail "supabaseKey é um JWT com role=service_role e não pode ser embutida no app."
        ;;
    *)
        fail "supabaseKey é um JWT com role não reconhecido para uso em cliente."
        ;;
esac

}

# --- supabaseProjectRef (027) ------------------------------------------------------------------
#
# Mesma checagem do build.gradle.kts do Android (`loadEnvironment`): a URL deve ser derivável
# exatamente do project ref — evita uma URL copiada de outro ambiente por engano.

validate_project_ref_config() {

ref_trimmed=$(trim "${supabaseProjectRef:-}")

if [ -z "$ref_trimmed" ]; then
    fail "supabaseProjectRef está ausente ou contém apenas espaços."
fi

case "$ref_trimmed" in
    *[!a-z0-9]*) fail "supabaseProjectRef deve conter apenas letras minúsculas e dígitos." ;;
esac

if [ "${#ref_trimmed}" -ne 20 ]; then
    fail "supabaseProjectRef deve ter 20 caracteres."
fi

expected_url="https://${ref_trimmed}.supabase.co"
if [ "${url_trimmed:-}" != "$expected_url" ]; then
    fail "supabaseUrl não corresponde a supabaseProjectRef (esperado $expected_url)."
fi

}

# --- Isolamento Dev x Prod (027) -----------------------------------------------------------------
#
# Só roda quando ENVIRONMENT_ID=DEV: lê supabaseProjectRef diretamente de Prod.secrets.xcconfig no
# disco (não passa pelas Build Settings do alvo atual) e falha se Dev apontar para o mesmo projeto
# de Prod — mesmo espírito de `validateEnvironmentIsolation` no build.gradle.kts do Android.
# Arquivo ausente (clone novo sem Prod.secrets.xcconfig) não é um erro aqui — SRCROOT pode não ter
# sido provisionado ainda; cada ambiente valida sua própria ausência de config via as funções acima.

validate_dev_prod_isolation() {

[ "${ENVIRONMENT_ID:-}" = "DEV" ] || return 0

prod_secrets_file="${SRCROOT:-.}/Config/Prod.secrets.xcconfig"
[ -f "$prod_secrets_file" ] || return 0

prod_ref=$(grep -E '^[[:space:]]*supabaseProjectRef[[:space:]]*=' "$prod_secrets_file" | tail -n 1 | sed -E 's/^[^=]*=[[:space:]]*//' | tr -d '[:space:]')

if [ -n "$prod_ref" ] && [ "$prod_ref" = "${ref_trimmed:-}" ]; then
    fail "Dev (environmentId=DEV) não pode usar o mesmo supabaseProjectRef de Prod ($prod_ref)."
fi

}

validate_map_style_config() {

# --- mapStyleUrl -------------------------------------------------------------------------------

style_url_trimmed=$(trim "${mapStyleUrl:-}")

if [ -z "$style_url_trimmed" ]; then
    fail "mapStyleUrl está ausente ou contém apenas espaços."
fi

case "$style_url_trimmed" in
    https://*) ;;
    http://*) fail "mapStyleUrl usa esquema http:// — apenas https:// é aceito." ;;
    *) fail "mapStyleUrl não é uma URI HTTPS absoluta." ;;
esac

style_url_authority=$(printf '%s' "$style_url_trimmed" | sed -E 's#^https://##' | sed -E 's#[/?#].*$##')

if [ -z "$style_url_authority" ]; then
    fail "mapStyleUrl não possui host."
fi

case "$style_url_authority" in
    *@*) fail "mapStyleUrl não deve conter user-info (usuário@host)." ;;
esac

style_url_host=$(printf '%s' "$style_url_authority" | sed -E 's/:[0-9]+$//')
if [ -z "$style_url_host" ]; then
    fail "mapStyleUrl não possui host."
fi

# Hosts de demonstração/públicos conhecidos — nunca aceitos como provedor de produção (mesma
# allowlist negativa de `validateMapStyleConfiguration` no build.gradle.kts do app Android).
case "$style_url_host" in
    demotiles.maplibre.org|tile.openstreetmap.org|*.tile.openstreetmap.org)
        fail "mapStyleUrl aponta para um host de demonstração/público conhecido ($style_url_host) — configure um provedor de tiles gerenciado real."
        ;;
esac

# --- mapStyleProviderName -----------------------------------------------------------------------

provider_name_trimmed=$(trim "${mapStyleProviderName:-}")

if [ -z "$provider_name_trimmed" ]; then
    fail "mapStyleProviderName está ausente ou contém apenas espaços."
fi

# --- mapStyleAttribution -------------------------------------------------------------------------

attribution_trimmed=$(trim "${mapStyleAttribution:-}")

if [ -z "$attribution_trimmed" ]; then
    fail "mapStyleAttribution está ausente ou contém apenas espaços."
fi

# --- mapStyleAttributionUrl ----------------------------------------------------------------------

attribution_url_trimmed=$(trim "${mapStyleAttributionUrl:-}")

if [ -z "$attribution_url_trimmed" ]; then
    fail "mapStyleAttributionUrl está ausente ou contém apenas espaços."
fi

case "$attribution_url_trimmed" in
    https://*) ;;
    http://*) fail "mapStyleAttributionUrl usa esquema http:// — apenas https:// é aceito." ;;
    *) fail "mapStyleAttributionUrl não é uma URI HTTPS absoluta." ;;
esac

attribution_url_authority=$(printf '%s' "$attribution_url_trimmed" | sed -E 's#^https://##' | sed -E 's#[/?#].*$##')

if [ -z "$attribution_url_authority" ]; then
    fail "mapStyleAttributionUrl não possui host."
fi

case "$attribution_url_authority" in
    *@*) fail "mapStyleAttributionUrl não deve conter user-info (usuário@host)." ;;
esac

attribution_url_host=$(printf '%s' "$attribution_url_authority" | sed -E 's/:[0-9]+$//')
if [ -z "$attribution_url_host" ]; then
    fail "mapStyleAttributionUrl não possui host."
fi

}

validate_supabase_config
validate_project_ref_config
validate_dev_prod_isolation
validate_map_style_config

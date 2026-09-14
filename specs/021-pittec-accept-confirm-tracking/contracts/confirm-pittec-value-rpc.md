# Contract: RPC de confirmação de valor do PitTec — SUPERSEDIDO

**Status**: ⚠️ Este contrato descrevia uma RPC (`confirm_pittec_appointment`) e um modelo
(cobrança antes da busca, card pós-aceite só informativo) que **nunca chegaram a ser implementados**
— foram substituídos ainda durante a implementação desta mesma spec, nesta sessão (2026-09-13),
quando uma migration mais ampla do backend compartilhado
(`20260913010000_pittec_call_tracking.sql`, já escrita pelo time Android) foi encontrada, corrigida
(tinha um `end` de `case` faltando, por isso nunca havia sido aplicada) e aplicada à nuvem.

**O design real, já implantado**, está documentado em
[pittec-quote-payment-real.md](./pittec-quote-payment-real.md). Este arquivo é mantido apenas como
registro histórico da decisão original (Opção A da clarificação desta sessão), que foi revertida
quando o design real do backend compartilhado veio à tona — ver a nota de implementação em FR-002
do `spec.md`.

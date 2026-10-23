# Porte iOS — vistoria fotográfica do Guincho

## Base Android e limite do porte

A spec Android 030 e os commits `7a64603` e posteriores definem uma vistoria versionada, aprovação explícita do cliente, correção sem apagar versões, início explícito do transporte e consulta histórica. As migrations e contratos desse fluxo já existem no workspace Android e são compartilhados pelo mesmo projeto Supabase; o iOS deve consumir os RPCs e o bucket privado existentes, sem duplicar alterações remotas.

O porte usa SwiftUI/UIKit, `UIImagePickerController` somente para captura da câmera, armazenamento privado local para retomar uploads, Supabase Storage com upload sem `upsert` e RPCs autenticadas para reservar/confirmar/submeter fotos e decidir a versão.

## Entrega em etapas

1. Modelos/DTOs e repository tipado para vistoria, leitura, fotos, decisões e transporte.
2. Captura da câmera para os quatro pontos obrigatórios, revisão/refazer e upload retomável.
3. Revisão do cliente, aprovação/correção e guarda visual do início do transporte.
4. Consulta histórica das versões e fotos, sem mutações após encerramento.
5. Builds Dev/Homol/Prod e validação manual em duas contas; qualquer cenário não executado permanece aberto.

## Compatibilidade

Atendimentos sem vistoria obrigatória preservam o comportamento legado. A regra final de autorização para iniciar/concluir transporte continua no backend compartilhado; o cliente iOS nunca interpreta erro ou timeout como aprovação.

# Cadastro e validação documental no iOS

Referência: `../../../../android/pitgo/specs/035-validacao-documental/spec.md` e respectivos contratos `registration-api.md` e `access-and-android.md`, consultados no checkout Android de 05/11/2026 (incluindo implementação local ainda não commitada).

- Cadastro inicial comum de CLIENT/PROVIDER: nome, sobrenome, e-mail, telefone, CPF, senha e confirmação. Metadados compatíveis com o trigger compartilhado; nenhuma ativação local.
- Contexto v2 autoritativo, com modalidade selecionada e memberships. Novas contas pendentes chegam ao cadastro, antes do carregamento dos agregados operacionais. Dispensa de contas legadas vem do servidor; falha de leitura não libera acesso.
- Complementos usam os formulários existentes e `sync_my_registration_complement`. Dados de empresa restaurados do snapshot privado; veículo inicial do guincho integra a lista documental com referência estável.
- CNH frente/verso, selfie, selfie com documento e documento de cada veículo de atendimento. Captura, revisão, upload privado imutável e confirmação na Edge Function. Imagens sem EXIF, limitadas a 2000 pontos e 10 MiB; documentos em memória, com transporte Storage sem cache em disco.
- Submissão, análise, motivos de correção, abertura de nova versão e reenvio. Revisões e chaves idempotentes protegem retries. Fotos reservadas não contam como recebidas.
- Cliente aprovado pode iniciar cadastro de prestador e voltar a CLIENT. Menu permite escolher modalidade sem aprovar outra implicitamente.
- Recuperação de senha com PKCE via Auth, retorno `com.trustarx.pitgo.auth://auth/recovery`, tela exclusiva e nova leitura de contexto depois da alteração. Reiniciar durante recuperação exige novo link ou saída, sem abrir marketplace.

O iOS consome o backend compartilhado; esta mudança não publica migrations/Functions nem implementa telas administrativas. A aprovação continua pertencendo ao dashboard.

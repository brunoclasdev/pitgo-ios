# Porte iOS — avisos e recuperação da vistoria

Adapta a spec Android 032 ao shell SwiftUI e à captura privada introduzida em 030. O contrato vigente passou a usar aviso interno autenticado, sem Firebase/FCM nem notificação do sistema.

1. Consultar as pendências do próprio cliente e ambiente por RPC, em todas as abas autenticadas, ao voltar ao primeiro plano e a cada cinco segundos enquanto visível.
2. Exibir aviso sem alterar o layout, permitir dispensar por atendimento/versão e revalidar a pendência antes de abrir a vistoria.
3. Manter a imagem capturada disponível para repetir o salvamento, incluindo quando a gravação local inicial falhar por falta de espaço.
4. Persistir a identidade idempotente do envio e reconhecer replay confirmado antes de fechar a vistoria.
5. Depois do envio confirmado, voltar ao atendimento do prestador com mapa de retirada/destino e estado de aprovação; aprovação continua sem iniciar o transporte.
6. Validar builds Dev/Homol/Prod e deixar os ensaios de duas contas, rede e aparelho real como validação manual.

# haos-mac-mini

Instalador de **Home Assistant OS** numa VM VirtualBox em **Mac Apple Silicon**.

> **Estado: em construção.** O `haos-install.sh` **ainda não existe**. O que está publicado
> aqui é a base sobre a qual ele será escrito — catálogo, sonda do hospedeiro, contrato de
> API verificado e os packages de custo. Nada aqui instala nada ainda.

## Por que existe

A documentação oficial do Home Assistant descreve a instalação em macOS como uma sequência
de cliques no assistente do VirtualBox. Funciona, e não é automatizável nem reproduzível.
Não existe hoje um instalador mantido para HAOS + Mac: o único script público é Linux/Intel
com versão fixada em 2021, e o guia de Mac que circula está marcado como *dormant* pelo
próprio autor.

## O que já está aqui

| Caminho | O que é |
|---|---|
| `catalog/catalog.bash` | **Fonte de verdade** do catálogo — categorias, itens, perfis de VM. O instalador embutirá uma cópia e o CI comparará as duas |
| `lib/probe-host.sh` | Sonda do hospedeiro. Emite só pares chave=valor: sem cor, sem animação, sem decisão. Compatível com o bash 3.2 do macOS |
| `lib/haos-ui.sh` | Camada visual. Degrada para texto puro fora de TTY e com `NO_COLOR` |
| `docs/API-REFERENCE_20260823_verificado.md` | **Contrato de API**, com semântica de evidência explícita: `PUBLIC-DOC`, `SOURCE-PINNED`, `EMPÍRICO`, `DOC-GAP` |
| `docs/homeassistant_installer_tiers_curadoria_2026-08-23.md` | Como o catálogo decide o que ofertar, e por que popularidade não é critério suficiente |
| `packages/` | Custo de energia, gás e água com regras brasileiras — cascata por faixa, tributos por dentro, volume corrigido |
| `extras/` | Overlay PTZ para câmeras Tapo C210. **Roda dentro do HAOS, à parte** — não faz parte do instalador |

## O que foi medido, não suposto

Contra uma instância real de **Home Assistant 2026.8.3**:

- **O proxy REST `/api/hassio/*` não serve para instalar app.** Com token de usuário
  confirmado administrador, **9 caminhos testados devolveram 401** — inclusive os de leitura
  pura (`supervisor/info`, `os/info`, `store`).
- **O comando WebSocket `supervisor/api` funciona** com esse mesmo token. É a rota, e é a
  única — `hassio/addons` devolve `unknown_command`. Como bash não fala WebSocket, isso
  torna `python3` uma dependência real do instalador, não um detalhe.
- **Slug de app é `<repositório>_<app>`**, não o nome curto: `core_samba`, `core_ssh`,
  `core_configurator`. O prefixo de um repositório de terceiro é **hash da URL** — tem de
  ser descoberto depois de adicionar o repositório, nunca fixado no código.

## Princípios que o código segue

- **Probe, não enum fixo.** `--ostype` sai de `VBoxManage list ostypes`; `storagectl --add
  virtio-scsi` é validado com `--help` antes de usar. Rótulo de tela nunca vira argumento de
  CLI por semelhança textual.
- **Verificar depois de escrever.** Status HTTP 200 não é prova; a pós-condição é.
- **Falha de um item não aborta os demais.** Contrato de retorno: `0` instalado agora ·
  `100` já estava · `1` falhou.
- **`--dry-run` mostra o plano inteiro antes de tocar em qualquer coisa.**
- **bash 3.2** — é o que o macOS traz. Sem arrays associativos, sem namerefs.

## Requisitos

macOS em Apple Silicon · VirtualBox · `python3` · `curl`

## Licença

MIT — ver [LICENSE](LICENSE).

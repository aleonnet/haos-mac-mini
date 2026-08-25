# HANDOFF — cofre com voz e princípios, doctor de storage · 2026-08-25 (tarde)

> **SUPERADO por `HANDOFF-2026-08-25-a-algema-do-apfs.md`** — abra aquele
> primeiro; as lições daqui seguem válidas como referência.
> Supersede
> `HANDOFF-2026-08-25-noite-das-tres-mortes.md` (as lições de lá seguem
> válidas; este cobre a tarde seguinte: análise externa absorvida, cofre
> endurecido, bancada de energia em curso).

## 0. ESTADO — confira no git, não neste parágrafo

- main = origin/main, árvore limpa, portão limpo. Versão 0.3.0+unreleased
  (CHANGELOG gordo — o rito 0.4.0 aguarda ordem do dono).
- Instância da casa no ar, doctor `0 com problema`, cofre com 7 backups no
  Mac e 2 dentro da VM. **Bancada física em curso**: o dono está testando
  reboot + duas quedas de energia reais (puxar o plug), com backup-âncora
  criado e validado antes.

## 1. O que nasceu nesta tarde (tudo com cerca e mutação)

| Entrega | Commit | Prova |
|---|---|---|
| `--doctor` § Armazenamento: controller REAL + `IgnoreFlush` efetivo + versão do VBox validada (T5 documental via `vbox_validada` no manifesto) | `986e1ac` | rodado contra a VM real; 3 mutantes mortos |
| README fact-checkado (perda de /data = fato medido, não profecia; savestate banido com justificativa Oracle 7.1→7.2) | `986e1ac` | fonte Oracle relida na data |
| Toolkit pessoal de transferência raw cercado no `.gitignore` (carrega dados da casa; é do operador, não do produto) | `41ed7f8` | `git check-ignore` |
| Flag `--backup` — backup imediato com voz (o agente 04:10 é mudo por design; a flag diz onde o tar ficou, tamanho, contagem; falha explica com rc≠0) | `1f8bc48` | provado no mini; 3 mutantes mortos |
| Cofre recusa tar CRIPTOGRAFADO (`protected: true` → exit 4 com aviso citando o Emergency Kit) — o cofre restaura sem chave, aceitar seria guardar backup irrestaurável | `ef51532` | cerca contra o puxador ESCRITO |
| Poda do `/backup` DENTRO da VM (mantém 2; sem isso ~18 MB/dia até encher o disco) + `ha backups reload` | `ef51532`/`95cd58f` | medido: VM ficou com exatamente 2 |
| `--backup` converge o artefato (desired-state): cópia antiga/artesanal ganha as cercas novas sozinha — generalidade provada no mini (IP fixo saiu do script local) | `ef51532` | grep no artefato convergido |
| **Poda só toca `auto-*` — nos DOIS lados** (princípio do --uninstall: só se remove o que se criou) | `95cd58f` | cenário "tar do dono sobrevive"; 3 mutantes mortos |

## 2. Lições que custaram (ou quase custaram) — NÃO reaprender

1. **A poda cega levou um tar do dono.** A primeira versão podava `*.tar`
   por contagem e apagou o backup histórico do transplante (o dono tinha
   cópia; perda funcional zero — os 7 restantes eram mais novos). Regra
   selada em código e cerca: **tesoura só alcança nome `auto-*`**.
2. **`getextradata` devolve rc=0 MESMO sem valor** ("No value set!") — todo
   veredito sobre extradata sai do TEXTO da resposta, nunca do rc.
3. **O Emergency Kit da UI do HA é de OUTRA rotina.** O gerenciador de
   backup da interface (se ligado) cifra com chave própria; nossa rotina
   CLI cria `protected: false` e restaura sem chave. Na instância da casa
   o automático da UI está DESLIGADO e não há chave em `.storage` (o kit
   que o dono guardou é relíquia da instância pré-transplante). O cofre é
   a autoridade única — e agora recusa tar cifrado em vez de guardá-lo mudo.
4. **Customização de entidade da UI mora no `.storage`, não em YAML.**
   Nome/ícone/área que o dono deu às entidades SmartIR vivem em
   `core.entity_registry`, casados por `unique_id`+plataforma. Consequência
   dura: **os `unique_id` de `clima_ac.yaml`/`media_ir.yaml` (no /config da
   instância) são INTOCÁVEIS** — trocá-los órfãna as customizações. O cofre
   carrega o `.storage`, então `--restore` devolve tudo.
5. **Máquina que nasceu fora do produto pode não ter `vm-guard.env`** — o
   mini (setup da noite da crise) não tinha, e o puxador genérico sai 3 sem
   ele. Escrito à mão lá uma vez; instalação normal escreve na fase de boot.
   Dívida menor: `--doctor` não confere a existência do env.

## 3. Análise externa (Downloads/HAOS_VM_MAC_M4_2026_ANALISE_INSTALADOR.md)

Lida integral (871 linhas), fontes centrais reverificadas. Veredito: valida
nossa implementação (AHCI é onde IgnoreFlush é documentado; VirtioSCSI do
guia oficial é experimental, sem IgnoreFlush e — só nós medimos — recusado
pelo VBoxManage ARM). Absorvido dela: doctor de storage (§8.3), par
`--backup`/`--restore` (§11), T5 documental. Backend alternativo: se um dia
houver, é UTM/QEMU (flush documentado), NÃO Fusion (download atrás de login
Broadcom mata `curl | bash`; HAOS fora da lista de guests ARM; flush não
documentado). Avaliações completas nas mensagens da sessão de 25/08.

## 4. O que falta (ordem do dono manda)

1. **Bancada física** (EM CURSO): reboot + 2 puxadas de plug + conferência
   + doctor final. Prompts prontos entregues para os dois desfechos.
2. Rito 0.4.0: CHANGELOG → release, plano F11 → `planos_concluidos/`,
   re-medir bench. **Só sob ordem.**
3. Issue upstream para a doc oficial do HA (IgnoreFlush ausente +
   VirtioSCSI/ARM inválido) — rascunho para revisão do dono.
4. Tag pública v1 — **só sob ordem.**
5. Dívidas menores: doctor não confere `vm-guard.env`; Extension Pack/USB;
   mensagens longas sob locale C; `--upgrade`.

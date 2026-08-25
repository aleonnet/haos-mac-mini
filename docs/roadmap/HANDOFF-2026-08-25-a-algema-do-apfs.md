# HANDOFF — a 4ª morte, a autópsia e a algema do APFS · 2026-08-25 (noite)

> ## ⚠️ ERRATA (mesma noite, 0.4.1) — o assassino verdadeiro era OUTRO
>
> A causa da 4ª morte **não foi** a reversão do APFS descrita abaixo: foi a
> **própria fase de imagem** do instalador. O "já está" comparava o tamanho
> atual do `.vdi` com o da criação; disco dinâmico cresce, então **todo
> rerun reprovava o disco vivo e movia a imagem de fábrica por cima** — a
> VM seguia no inode antigo e a troca só aparecia no boot seguinte, como
> instância virgem. Flagrado em flagrante no rerun do dono (lsof: VBox
> segurando 7,8 GB deletados; no disco, os 469 MB de fábrica). O rerun das
> ~14:55 armou a bomba; o plug das 18:20 só a revelou. **Corrigido no
> 0.4.1**: "já está" = versão+SHA do `.origem`; **disco de VM registrada é
> INTOCÁVEL** (nem `--force`; recriar = `--uninstall` primeiro); cerca com
> o cenário exato + 2 mutantes mortos.
>
> O que PERMANECE válido da autópsia abaixo: o fato do `fsync()` sem
> `F_FULLFSYNC` (provado no fonte) e o **apfs-pin como
> defesa-em-profundidade**. O que CAI: a atribuição causal ao APFS, e a
> alegação de que o pin "salvou" o 3º corte (aquele boot sobreviveu porque
> nenhum rerun havia trocado o arquivo desde o restore). Lição-mestra:
> **inferência forte não é prova — o dono recusou aceitá-la duas vezes, e
> nas duas a recusa dele estava certa.**

> **LEIA-ME PRIMEIRO.** Porta de entrada da frente do instalador. Supersede
> `HANDOFF-2026-08-25-cofre-com-voz-e-principios.md` (lições preservadas lá
> e no anterior; este cobre a noite: a quarta morte do `/data`, a autópsia
> em nível de código-fonte e a contramedida que virou produto).

## 0. ESTADO — confira no git, não neste parágrafo

- main = origin/main, árvore limpa, portão limpo. **Versão 0.4.0 fechada
  no CHANGELOG** (release/tag público segue SÓ sob ordem do dono).
- Instância da casa no ar, íntegra, **restaurada pela 2ª vez em produção
  pelo cofre** e **sobrevivente do 1º corte real de tomada com o vigia
  apfs-pin armado**.

## 1. A QUARTA MORTE — e por que ela mudou tudo

Corte REAL de tomada (o 2º do dia; o 1º sobreviveu) com `IgnoreFlush=0`
armado e conferido → a VM voltou **VIRGEM**. A autópsia, sem inferência:

1. **Não houve corrupção**: o guest montou a partição de dados LIMPA, com
   `condition-first-boot=true` e o filesystem **em tamanho de fábrica**
   (resize de ~222 MB → 32 GiB no boot) — assinatura de imagem recém-
   gravada, não de fsck/reformat.
2. **O disco virtual reverteu no APFS**: mapa interno do VDI com 448 MB
   alocados (= fábrica) convivendo com 7,2 GB físicos órfãos do dia de
   uso. O arquivo voltou a apontar para os extents originais.
3. **A causa, PROVADA no código-fonte do VirtualBox** (`Runtime/r3/posix/
   fileio-posix.cpp`): `RTFileFlush` é `fsync()` puro — sem `F_FULLFSYNC`,
   sem caso especial Darwin. No macOS, `fsync()` não descarrega o cache do
   SSD; num corte de tomada as transações COW do APFS que apontavam para
   os blocos novos evaporam, e o arquivo **reverte**.
4. **Fronteira do `IgnoreFlush=0` corrigida**: ele protege contra morte da
   VM/hypervisor (5 quedas simuladas provaram — o host sobrevive e o cache
   chega ao disco depois). Contra TOMADA, sozinho, não protege.

## 2. A ALGEMA — apfs-pin (produto desde 0.4.0)

Vigia (`apfs-pin.py` + LaunchAgent `com.haos-mac-mini.apfs-pin`) que abre
o MESMO `.vdi` e chama `fcntl F_FULLFSYNC` — o flush que desce até a mídia
— a cada 5 s (custo medido: 0–5 ms). Janela de reversão: de ilimitada para
≤5 s, que o journal do ext4 do guest cobre — a física do Raspberry Pi,
reconstruída sobre o macOS. Desired-state, VDI por argv (sem `sh -c`),
KeepAlive, `--uninstall` remove (`rm-pin`), `--doctor` confere
(ativo/ausente/PARADO = fail). Cerca com mutação (que pegou a própria
cerca cega 2×: F_FULLFSYNC no comentário mascarava o do código; `-c` do
plist fica em tag própria).

**Validação de campo**: 1º corte real com o vigia → instância íntegra,
partição em tamanho pleno (`resizing from 8210171 to 8210171`). Placar
honesto: sem pin 1 morte em 2 cortes; com pin 0 em 1. Cada corte futuro
engorda o n.

## 3. O resto da noite (tudo entregue, cercado onde é produto)

- Dashboard **Casa** (só da instância; slug de dashboard EXIGE hífen — o
  core check reprova sem) · aba Luzes na visão por tecla · modelo
  **"parede manda"**: power-on das Hue = ligar ao receber energia
  (configurado na bridge), guardas de religamento aposentadas (.bak no
  /config), teclas renomeadas pelo mapa REAL (painel numera de BAIXO para
  cima — o dono corrigiu o próprio mapa) · 12 luzes Hue renomeadas NA
  BRIDGE com prefixo de plataforma · entradas-fantasma de automação limpas
  do registro.
- Lições novas: card de área agrupa switch às cegas (varrer `switch.*` da
  área antes de `area-controls`); Tuya não expõe relight de lâmpada no HA
  (o painel sim: `select.*_power_on_behavior`); entidade some do registro
  quando o dono a remove da plataforma.

## 4. O que falta / propostas em aberto

1. **UPS no mini** — na lista de compras do dono; única defesa total
   contra tomada.
2. **Cofre horário** (agente de 1 em 1 h) — proposto, sem ordem ainda.
3. Release/tag público v1 — só sob ordem.
4. Issue upstream (doc oficial HA: IgnoreFlush + VirtioSCSI/ARM + agora o
   fsync do macOS) — rascunho para revisão do dono.
5. Dívidas menores anteriores seguem (doctor não confere vm-guard.env;
   Extension Pack/USB; `--upgrade`).

## 5. Nota operacional

O HANDOVER para colegas LLM (acesso e disciplina da instância) vive na
RAIZ do monorepo — fora deste repositório público, de propósito. Consulte-o
antes de tocar na instância da casa.

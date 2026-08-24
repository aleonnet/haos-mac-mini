> Movido da raiz em 2026-08-24 e limpo de identificadores da casa (repo público).
> O papel deste documento — cardápio para o catálogo — está CUMPRIDO; fica como registro.
> O dump cru da instância (`inventario/`) permanece fora do versionamento.

# Inventário classificado da instância atual — lido da API em 23/08/2026 04:0x

> **Medido, não estimado.** Fonte: `GET /api/config`, `/api/config/config_entries/entry`,
> `/api/states`, `/api/services` em `a instância local`, autenticado pelo login flow.
> JSON bruto em `inventario/`. **[FATO]** = veio da API · **[CONFIRMAR]** = classificação minha,
> a validar na doc oficial da integração.

## O número "22 integrações" estava errado nos dois sentidos

| | |
|---|---|
| **HA** | 2026.8.3 · local `ABHOME` · `America/Sao_Paulo` · **272 componentes carregados** |
| **Config entries** | **46** em **28 domínios** — não 22 |
| ↳ carregadas | **29** |
| ↳ `source: ignore` | **17** — descobertas dispensadas, não integrações. **É daqui que vinha o 22.** |
| **Entidades** | **385** em 25 domínios |
| **Fora de config entry** | 4 automações · **75 cenas** · 4 helpers `input_number` · 1 zona · 1 pessoa |

**As 17 ignoradas importam.** Se não forem migradas, o HAOS novo vai **re-sugerir as 17** — sete
`samsungtv`, seis `dlna_dmr`, `spotify`, `upnp` e outras. São triviais (ignorar de novo), mas
precisam estar no roteiro, senão a instância nova nasce com 17 notificações pendentes.

## As tarifas RJ do Shelly — confirmado que NÃO são integração  **[FATO]**

São **4 helpers + 1 automação + ~12 sensores template**, e nenhum vem em config entry:

```
input_number.peak = 1.78789   ·  input_number.shoulder = 1.22638
input_number.offpeak = 0.91791 ·  input_number.regular  = 1.02204
automation.tarifa_branca (on) · automation.tarifa_ponta · automation.tarifa_fora_ponta
sensor.{daily,weekly,monthly}_energy_{peak,shoulder,offpeak}[_cost]
sensor.custo_mensal_tarifa_{branca,residencial} · sensor.tarifa_energia_jul_22
```

⚠️ **`automation.tarifa_ponta` e `automation.tarifa_fora_ponta` estão `unavailable`** — as duas
que de fato chaveiam a tarifa. Só `tarifa_branca` está `on`. **[CONFIRMAR] com ele:** quebrado, ou
desativado de propósito? Migrar defeito é pior que não migrar.

## Classificação por como o script conduz

| # | Domínio | N | `source` | Classe | Como o script conduz |
|---|---|---|---|---|---|
| 1 | `analytics` `backup` `go2rtc` `hassio` `raspberry_pi` | 5 | `system` | **A** | nascem com o core |
| 2 | `sun` `systemmonitor` | 2 | `import` | **A** | YAML/import, vêm no backup |
| 3 | `met` | 1 | `onboarding` | **A** | recriar no onboarding |
| 4 | `local_ip` `speedtestdotnet` | 2 | `user` | **A** | sem credencial |
| 5 | **17 entries `ignore`** | 17 | `ignore` | **A** | restauram por backup; senão, re-ignorar |
| 6 | `tuya` | 2 | `user`,`dhcp` | **B** | conta Tuya do dono + região · config flow API |
| 7 | `tplink` | 2 | `user`,`discovery` | **B** | credencial TP-Link Cloud · as 2 Tapo C210 |
| 8 | `smartthings` | 1 | `dhcp` | **B/C** | **[CONFIRMAR]** PAT ou OAuth na 2026.8 |
| 9 | `hue` | 1 | `user` | **C** | **apertar o botão da bridge** — ação física |
| 10 | `hacs` | 1 | `user` | **C** | device flow do GitHub, no navegador |
| 11 | `cast` `androidtv_remote` | 3 | `zeroconf` | **C** | código de pareamento **na TV** |
| 12 | `mobile_app` `ios` | 3 | `registration` | **C** | **re-registrar dos aparelhos** — o script não faz |
| 13 | `matter` | 1 | `zeroconf` | **C/E** | 🔴 **fabric único** — re-comissionar é destrutivo |
| 14 | `shelly` `broadlink` | 5 | `zeroconf`,`dhcp` | **A/B** | descoberta; guardam IP no entry |
| 15 | `bluetooth` | 1 | `discovery` | **D** | adaptador **do Raspberry Pi**; a VM não terá |
| 16 | `raspberry_pi` `rpi_power` | 2 | `system`,`onboarding` | **D** | específicos do CM4 |
| 17 | `upnp` (ignorada) | 1 | `ignore` | **E** | aponta para **a HGU do provedor**, que sai no cutover |

## Achados que mudam o escopo

1. **`bluetooth` é (D), não (A).** O entry é *"Raspberry Pi Trading Ltd bluetooth"* — o rádio do
   Pi. Uma VM no Mac mini não tem esse adaptador, e passthrough de Bluetooth para VM é frágil.
   **Decidir com ele:** dongle USB, ou abrir mão? Há dispositivos BLE em uso? **[CONFIRMAR]**
2. **`matter` tem fabric único.** Não é "reconfigurar": é **re-comissionar cada dispositivo**, e
   remover do fabric antigo. É o item mais caro da migração e o único verdadeiramente destrutivo.
3. **75 cenas** não vêm em config entry nenhum. Estão em `.storage`/YAML — **backup é a única via**.
4. **`upnp` aponta para a HGU.** As duas frentes se cruzam aqui: o cutover remove a HGU.

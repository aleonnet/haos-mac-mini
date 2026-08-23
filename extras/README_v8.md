# Tapo C210 + Home Assistant — README v8: integração oficial, Live View, PTZ overlay e workaround TLS

> Guia reproduzível para integrar câmeras **TP-Link Tapo C210** ao **Home Assistant** usando a integração oficial **Tapo / TP-Link Smart Home**, habilitar **Live View**, diagnosticar um problema TLS observado em firmwares recentes e adicionar um **joystick PTZ (`▲ ◀ ● ▶ ▼`) sobre o stream** sem recompilar o frontend.
>
> **Validado em 21/08/2026** com:
>
> - Home Assistant OS **18.2**
> - Home Assistant Core **2026.8.2**
> - Home Assistant Frontend **20260729.6**
> - `python-kasa` **0.10.2**
> - duas câmeras **Tapo C210**
>
> Este projeto **não é oficial** do Home Assistant nem da TP-Link. A integração das câmeras é oficial; o overlay PTZ é uma customização local carregada pelo mecanismo oficial `frontend.extra_module_url`.

---

## 1. Resultado final

A solução mantém a integração oficial do Home Assistant e acrescenta uma camada de UI.

### Visão compacta da câmera

- Live View nativo;
- somente o joystick PTZ;
- joystick proporcionalmente menor e mantido no canto inferior direito;
- escala configurável apenas para o modo compacto.

```text
       ▲
    ◀  ●  ▶
       ▼
```

Na v8, a escala compacta padrão é `0.72`, resultando em botões de aproximadamente **24 px** (com mínimo de 24 px). A visão expandida mantém controles maiores para facilitar a interação.

### Visão expandida

- Live View nativo;
- joystick PTZ;
- ajuste do **passo de Pan**;
- ajuste do **passo de Tilt**;
- **Motion**;
- **Person**;
- **LED**;
- **Tamper**.

> **O que esses campos são:** eles editam `number.*pan_step` / `number.*tilt_step` — o **tamanho
> do passo em graus a cada clique** no D-pad, **não** a posição absoluta da câmera. Digitar `30`
> significa "cada seta gira 30°", não "vá para 30°". A C210 não expõe posicionamento absoluto
> pela integração oficial.

Na **v8**, os campos numéricos de passo de Pan/Tilt também aceitam entrada pelo teclado de forma confiável. O valor é confirmado por **Enter**, por **blur** (sair do campo) e pelas setas nativas do `input[type=number]`. A correção evita que o refresh periódico do painel sobrescreva o valor enquanto o campo está focado/editado dentro do Shadow DOM do Home Assistant.

O mesmo módulo funciona para múltiplas C210. As entidades são associadas automaticamente por `device_id`, plataforma `tplink` e `translation_key`; não há `entity_id` de câmera hardcoded.

---

## 2. Arquivos deste projeto

```text
extras/
├── README_v8.md                            este documento
├── install_tapo_c210_ptz_overlay_ha_v8.sh  instalador do overlay PTZ
└── fix_tapo_tls_ecdhe_ha.sh                workaround TLS do python-kasa (condicional)
```

> **Estes dois scripts são executados à parte, fora do `haos-install.sh`.** Eles rodam
> **dentro** do Home Assistant OS (add-on de terminal), não no macOS.

> Este README usa `homeassistant.local:8123` (mDNS) nos exemplos. Se a sua rede tiver um nome
> DNS interno para o Home Assistant, use-o no lugar — o overlay não depende de endereço:
> ele **descobre as entidades pelo `device_id` da câmera**, nunca por IP ou nome fixo.

O instalador v8 cria/atualiza:

```text
/config/www/tapo-ptz-home.js
/config/configuration.yaml
/config/backups/tapo-ptz-overlay/
```

Arquivo esperado no mesmo repositório:

[`install_tapo_c210_ptz_overlay_ha_v8.sh`](./install_tapo_c210_ptz_overlay_ha_v8.sh)

SHA-256 do instalador de overlay v8:

```text
4a5f995cb68dcecfb3ec0155a055f4cdff65222a65e414def3fc17c5d5c46317
```

O workaround TLS foi separado propositalmente em outro script:

[`fix_tapo_tls_ecdhe_ha.sh`](./fix_tapo_tls_ecdhe_ha.sh)

SHA-256:

```text
8e1ad8415c25a38529a9f0b1628f8f14ddee0b26d987a476757b26b9e55ea614
```

Essa separação é importante: o **overlay** é persistente em `/config`, enquanto o patch TLS atua no runtime/container do Core e pode deixar de ser necessário quando o `python-kasa` for corrigido upstream.

---

## 3. Por que usar a integração oficial

O Home Assistant suporta oficialmente a **Tapo C210** pela integração **TP-Link Smart Home**. A documentação atual lista a C210 entre as câmeras Tapo suportadas e documenta Live View, configurações da câmera e pan/tilt conforme as capabilities expostas pelo dispositivo.

A integração é classificada como **Platinum** e a operação normal com o dispositivo é local.

**HACS não é necessário** para esta solução. Também não é necessário instalar `Tapo: Cameras Control`.

Referências:

- Home Assistant — TP-Link Smart Home:  
  https://www.home-assistant.io/integrations/tplink/
- Home Assistant — Tapo:  
  https://www.home-assistant.io/integrations/tplink_tapo/

---

# Instalação do zero

## Fluxo recomendado

Para uma instalação nova, siga esta ordem:

```text
1. Instalar/atualizar Home Assistant
2. Configurar cada C210 no app Tapo
3. Criar Camera Account
4. Adicionar pela integração oficial TP-Link/Tapo
5. Se houver SSLV3_ALERT_HANDSHAKE_FAILURE:
      executar fix_tapo_tls_ecdhe_ha.sh
6. Confirmar Live View + entidades PTZ nativas
7. Executar install_tapo_c210_ptz_overlay_ha_v8.sh
8. Fazer hard refresh no navegador
9. Testar as duas câmeras:
      compacto + expandido + Pan/Tilt digitado
```

Após **qualquer atualização do Core**, se uma C210 voltar a apresentar o mesmo erro TLS, rode primeiro:

```bash
/config/fix_tapo_tls_ecdhe_ha.sh --dry-run
```

O script decidirá se o workaround ainda é necessário.



## 4. Instalar e preparar o Home Assistant

Instale o Home Assistant conforme a plataforma escolhida. Este procedimento foi validado em **Home Assistant OS**.

Documentação oficial:

https://www.home-assistant.io/installation/

Para executar os comandos deste README no HAOS, é útil ter um terminal como:

- **Advanced SSH & Web Terminal**; ou
- terminal do **Studio Code Server**.

O overlay PTZ em si **não requer acesso Docker**.

---

## 5. Preparar cada Tapo C210 no aplicativo Tapo

### 5.1 Adicionar a câmera à rede

Primeiro configure normalmente a C210 no aplicativo oficial Tapo e confirme que ela está acessível pela rede local.

É recomendável manter o endereço IP previsível — por exemplo, usando uma reserva DHCP no roteador — especialmente se a câmera precisar ser adicionada manualmente por IP.

A documentação do Home Assistant observa que, em sub-redes diferentes, a descoberta automática pode não funcionar e recomenda IP estável para configuração manual.

### 5.2 Criar a `Camera Account`

Para o **Live View**, o Home Assistant exige as credenciais da **Camera Account** configurada dentro da câmera.

No app Tapo:

```text
Câmera
→ Settings / Configurações
→ Advanced Settings / Configurações Avançadas
→ Camera Account / Conta da Câmera
```

Crie um usuário e uma senha exclusivos para a câmera.

**Atenção:** esta conta é diferente da conta TP-Link/Tapo usada para login no aplicativo.

Referências:

- Home Assistant:  
  https://www.home-assistant.io/integrations/tplink/
- TP-Link Brasil — Conta da Câmera:  
  https://www.tp-link.com/br/support/faq/2790/
- TP-Link Brasil — RTSP/ONVIF:  
  https://www.tp-link.com/br/support/faq/2680/

### 5.3 Third-Party Compatibility

Alguns firmwares Tapo exigem ativação explícita de compatibilidade com integrações de terceiros.

Se houver erro de autenticação, verifique no app Tapo:

```text
Tapo Lab
→ Third-Party Compatibility
```

A própria documentação do Home Assistant recomenda verificar essa opção para firmwares que exigem ativação explícita.

---

## 6. Adicionar a C210 ao Home Assistant

No Home Assistant:

```text
Settings
→ Devices & services
→ Add integration
→ Tapo
```

Dependendo da versão/interface, a integração também pode aparecer associada a **TP-Link Smart Home**. O suporte Tapo é fornecido por essa integração oficial.

Informe:

- IP/hostname da câmera, se necessário;
- usuário da conta TP-Link Cloud;
- senha da conta TP-Link Cloud;
- habilite **Live view**;
- usuário da **Camera Account**;
- senha da **Camera Account**.

Repita para cada C210.

---

## 7. Verificar as entidades antes do overlay

**Não instale o overlay antes de confirmar que o PTZ nativo funciona.**

Abra o dispositivo da C210 no Home Assistant e verifique se existem, conforme as capabilities do firmware:

### PTZ

```text
button.*pan_left
button.*pan_right
button.*tilt_up
button.*tilt_down
```

O Core 2026.8.2 define explicitamente essas quatro actions na integração TP-Link:

https://github.com/home-assistant/core/blob/2026.8.2/homeassistant/components/tplink/button.py

### Tamanho do movimento

```text
number.*pan_step
number.*tilt_step
```

Fonte:

https://github.com/home-assistant/core/blob/2026.8.2/homeassistant/components/tplink/number.py

### Controles usados pela visão expandida

```text
switch.*motion_detection
switch.*person_detection
switch.*led
switch.*tamper_detection
```

Fonte:

https://github.com/home-assistant/core/blob/2026.8.2/homeassistant/components/tplink/switch.py

Nem toda câmera/firmware precisa expor todos os controles opcionais. O instalador mostra apenas as entidades encontradas.

---

# Problema TLS em alguns firmwares

## 8. Sintoma: `SSLV3_ALERT_HANDSHAKE_FAILURE`

Em alguns firmwares recentes, a câmera pode funcionar normalmente:

- no app Tapo;
- via RTSP;

mas falhar ao ser adicionada à integração oficial com erro semelhante a:

```text
Cannot connect to host <IP>:443
[SSL: SSLV3_ALERT_HANDSHAKE_FAILURE]
ssl/tls alert handshake failure
```

Há um issue específico do Home Assistant para **C210 HW 2.0 / firmware 1.5.2 Build 251217 Rel.60225n** com exatamente esse comportamento:

https://github.com/home-assistant/core/issues/164045

No Core 2026.8.2, o `manifest.json` da integração TP-Link fixa:

```text
python-kasa[speedups]==0.10.2
```

Fonte:

https://github.com/home-assistant/core/blob/2026.8.2/homeassistant/components/tplink/manifest.json

O issue upstream do `python-kasa` documenta que o `SslAesTransport` 0.10.2 oferece somente cifras RSA estáticas, enquanto alguns firmwares recentes aceitam apenas ECDHE:

https://github.com/python-kasa/python-kasa/issues/1724

### Importante

**Não aplique o workaround abaixo preventivamente.**

Primeiro tente a integração oficial sem alterações. A correção só faz sentido se:

1. o erro for realmente `SSLV3_ALERT_HANDSHAKE_FAILURE`;
2. a versão instalada ainda tiver a lista antiga de cifras;
3. o problema ainda não tiver sido corrigido upstream.

O issue `python-kasa #1724` ainda estava aberto quando este README foi validado em 21/08/2026.

---

## 9. Diagnosticar o `python-kasa`

Para inspecionar o pacote dentro do container do Core no HAOS, o **Advanced SSH & Web Terminal** precisa temporariamente estar sem `Protection mode`.

No Home Assistant:

```text
Settings
→ Apps
→ Advanced SSH & Web Terminal
→ Protection mode: OFF
→ Restart
```

Depois:

```bash
docker exec -it homeassistant bash
```

Dentro do container:

```bash
python3 - <<'PY'
import importlib.metadata
import kasa
from pathlib import Path

print("python-kasa:", importlib.metadata.version("python-kasa"))

p = Path(kasa.__file__).resolve().parent / "transports" / "sslaestransport.py"

print("arquivo:", p)
print("existe:", p.exists())

for i, line in enumerate(p.read_text().splitlines(), 1):
    if "CIPHER" in line or "ECDHE" in line or "AES256" in line or "AES128" in line:
        print(f"{i:4}: {line}")
PY
```

No caso que motivou este guia, apareciam apenas:

```text
AES256-GCM-SHA384
AES256-SHA256
AES128-GCM-SHA256
AES128-SHA256
AES256-SHA
```

sem ECDHE.

---

## 10. Workaround TLS usado e validado

**Somente se o diagnóstico confirmar `SSLV3_ALERT_HANDSHAKE_FAILURE` e ausência das cifras ECDHE**, use o script dedicado.

Coloque `fix_tapo_tls_ecdhe_ha.sh` em `/config/` — do mesmo modo descrito na seção 13 para o
instalador do overlay (arrastar para a raiz `CONFIG` do Studio Code Server ou usar **Upload**).
O caminho final é:

```text
/config/fix_tapo_tls_ecdhe_ha.sh
```

Com **Protection mode OFF** no Advanced SSH & Web Terminal:

```bash
chmod +x /config/fix_tapo_tls_ecdhe_ha.sh
/config/fix_tapo_tls_ecdhe_ha.sh --dry-run
```

Se o diagnóstico indicar que o patch é necessário:

```bash
/config/fix_tapo_tls_ecdhe_ha.sh
```

O script:

- descobre dinamicamente a versão instalada do `python-kasa`;
- localiza `sslaestransport.py` sem assumir a versão do Python;
- verifica se estas cifras já existem:

```text
ECDHE-RSA-AES256-GCM-SHA384
ECDHE-RSA-AES128-GCM-SHA256
```

- não toca no arquivo se o upstream já estiver corrigido;
- aborta sem editar se a estrutura de `SslAesTransport.CIPHERS` tiver mudado;
- valida sintaxe Python antes e depois;
- valida a lista de ciphers com o OpenSSL do container;
- cria backup persistente e deduplicado em:

```text
/config/backups/tapo-tls-ecdhe/
```

- grava atomicamente;
- abre um novo processo Python para confirmar que `SslAesTransport.CIPHERS` enxerga ECDHE;
- reinicia o Core somente quando necessário;
- é idempotente.

Opções:

```bash
/config/fix_tapo_tls_ecdhe_ha.sh --dry-run
/config/fix_tapo_tls_ecdhe_ha.sh --no-restart
/config/fix_tapo_tls_ecdhe_ha.sh --force-restart
```

### Por que esse script é separado do overlay

O patch TLS vive no **writable layer do container do Home Assistant Core**. Uma atualização/recriação do Core pode substituí-lo — e isso foi reproduzido na prática: após uma atualização do Home Assistant, o mesmo erro TLS voltou e o script separado restaurou o funcionamento.

Já o overlay v8 fica em `/config/www` e a referência em `/config/configuration.yaml`, portanto tem ciclo de persistência diferente.

Essa separação também evita aplicar cegamente um workaround antigo quando uma futura versão do `python-kasa` já trouxer a correção upstream.

Depois de concluir, reative o **Protection mode** do Advanced SSH & Web Terminal.

---

# Overlay PTZ

## 11. Por que o overlay precisa de uma customização

No frontend **20260729.6**, a strategy das áreas do Home Dashboard gera câmeras como:

```text
type: picture-entity
```

Fonte:

https://github.com/home-assistant/frontend/blob/20260729.6/src/panels/lovelace/strategies/areas/helpers/areas-strategy-helper.ts

O card compacto é implementado por:

```text
hui-picture-entity-card
```

Fonte:

https://github.com/home-assistant/frontend/blob/20260729.6/src/panels/lovelace/cards/hui-picture-entity-card.ts

Já a visão expandida da câmera é outro componente:

```text
more-info-camera
```

que renderiza diretamente:

```text
ha-camera-stream
```

Fonte:

https://github.com/home-assistant/frontend/blob/20260729.6/src/dialogs/more-info/controls/more-info-camera.ts

Foi justamente essa separação entre **compacto** e **expandido** que exigiu tratar os dois componentes.

---

## 12. Como a v8 funciona

O Home Assistant documenta oficialmente:

```yaml
frontend:
  extra_module_url:
    - /local/my_module.js
```

como mecanismo para carregar módulos JavaScript adicionais.

Fonte:

https://www.home-assistant.io/integrations/frontend/#loading-extra-javascript

A v8 usa esse mecanismo oficial para carregar:

```text
/local/tapo-ptz-home.js?v=8
```

O JavaScript então acrescenta comportamento aos componentes internos já existentes:

```text
hui-picture-entity-card
more-info-camera
```

**Não recompila o Home Assistant**, não substitui o bundle principal e não cria outro dashboard.

### Associação automática das câmeras

Para cada `camera.*`, o módulo procura entidades:

```text
mesmo device_id
+
platform == "tplink"
+
translation_key correspondente
```

Assim duas ou mais C210 podem coexistir sem hardcode de nomes ou IPs.

### Escala parametrizada do joystick compacto — mantida na v8

A v8 mantém explicitamente o tamanho do D-pad compacto (joystick virtual) desacoplado do tamanho dos controles da visão expandida: `COMPACT_SCALE` escala os elementos do D-pad e o próprio conjunto.

Os parâmetros ficam no JavaScript gerado:

```javascript
const COMPACT_SCALE = 0.72;
const COMPACT_BASE_BUTTON_PX = 34;
const COMPACT_MIN_BUTTON_PX = 24;
const COMPACT_BASE_OFFSET_PX = 10;
```

Com a configuração padrão:

```text
COMPACT_SCALE = 0.72
34 px × 0.72 ≈ 24 px
```

O mínimo de `24 px` impede que os botões encolham abaixo desse valor. A escala afeta apenas:

- diâmetro dos botões do D-pad compacto;
- tamanho dos símbolos;
- espaçamento entre os controles;
- afastamento do canto inferior direito.

A visão expandida **não é reduzida** pela `COMPACT_SCALE`; seus controles permanecem maiores.

Exemplos:

| `COMPACT_SCALE` | Resultado aproximado |
| ---: | --- |
| `1.00` | tamanho visual equivalente ao da v6 (`34 px`) |
| `0.85` | `29 px` |
| `0.72` | `24 px` — padrão da v8 |
| `< 0.72` | permanece em `24 px` por causa do mínimo |

Para tornar outra escala permanente e reaplicável, altere `COMPACT_SCALE` **no próprio instalador v8** antes de executá-lo. Editar somente `/config/www/tapo-ptz-home.js` funciona para teste, mas uma nova execução do instalador restaurará o conteúdo definido pelo instalador.

> Se o instalador for alterado, seu SHA-256 naturalmente deixará de ser o SHA publicado neste README.

---

## 12.1. Correção da v8: edição por teclado de Pan/Tilt

Na v7, os campos `Pan` e `Tilt` funcionavam pelas setas do `input[type=number]`, mas um valor digitado podia ser restaurado para o estado anterior antes de persistir.

A causa estava na detecção de foco durante o refresh do painel expandido: os inputs vivem em **Shadow DOM aninhado**, e usar apenas `document.activeElement === input` não representa corretamente esse foco.

A v8 protege o ciclo de edição com estados locais:

```text
dirty
committing
pendingUntil
```

e considera diretamente:

```javascript
input.matches(":focus")
```

O fluxo de commit da v8 é:

```text
digitar valor
   ├─ Enter  ────────┐
   ├─ blur ──────────┼─> number.set_value
   └─ setas/change ──┘
                         ↓
                 pequena janela de proteção
                         ↓
                  estado atualizado pelo HA
```

Isso evita que um estado antigo recebido durante o commit substitua visualmente o valor recém-digitado.

---

## 13. Instalar a v8

Coloque:

```text
install_tapo_c210_ptz_overlay_ha_v8.sh
```

em:

```text
/config/
```

### Pelo Studio Code Server

Você pode arrastar o `.sh` do Finder para a raiz `CONFIG` do Explorer ou usar a opção **Upload**.

Depois, no terminal:

```bash
chmod +x /config/install_tapo_c210_ptz_overlay_ha_v8.sh
```

Opcionalmente, faça primeiro um dry-run:

```bash
/config/install_tapo_c210_ptz_overlay_ha_v8.sh --dry-run
```

Instale:

```bash
/config/install_tapo_c210_ptz_overlay_ha_v8.sh
```

O script:

- cria/atualiza `/config/www/tapo-ptz-home.js`;
- preserva opções existentes do bloco `frontend:`, incluindo `themes` e outros módulos;
- remove referências antigas do próprio `tapo-ptz-home.js`;
- mantém exatamente uma URL `tapo-ptz-home.js?v=8`;
- cria backups somente quando um arquivo realmente será alterado;
- executa `ha core check`;
- restaura `configuration.yaml` e o JS anterior se a validação falhar;
- reinicia o Core somente quando houver alteração, salvo `--force-restart`;
- suporta `--dry-run` e `--no-restart`;
- pode ser executado repetidamente sem regravar arquivos ou criar backups desnecessários quando o estado já está convergido.

Depois que o Core voltar, faça um **hard refresh** no navegador:

```text
Firefox/macOS: Cmd + Shift + R
```

---

## 14. Confirmar que a instalação está ativa

Verifique o YAML:

```bash
grep -nE "extra_module_url|tapo-ptz" /config/configuration.yaml
```

Deve existir:

```yaml
frontend:
  ...
  extra_module_url:
    - /local/tapo-ptz-home.js?v=8
```

Teste o arquivo:

```bash
curl -I http://homeassistant.local:8123/local/tapo-ptz-home.js
```

Esperado:

```text
HTTP/1.1 200 OK
```

Valide o Core:

```bash
ha core check
```

No Console do navegador, filtre por:

```text
[Tapo PTZ]
```

Mensagens esperadas incluem:

```text
[Tapo PTZ] v8 carregado
[Tapo PTZ] compacto instalado: camera....
[Tapo PTZ] expandido instalado: camera....
```

---

## 15. Direção do PTZ

No ambiente validado com duas C210, o comportamento físico exigiu:

```javascript
const INVERT_PAN = true;
const INVERT_TILT = false;
```

Ou seja:

```text
▲ → tilt_up
▼ → tilt_down

◀ → pan_right
▶ → pan_left
```

Esse mapeamento foi **validado empiricamente neste ambiente**, não deve ser assumido como universal para todo hardware/firmware/orientação de montagem.

A v8 mantém a correção observada durante os testes: **pan permanece invertido**, mas **tilt usa o sentido nominal** (`INVERT_TILT = false`).

Se a sua câmera se mover no sentido errado, altere:

```javascript
const INVERT_PAN = true;
const INVERT_TILT = false;
```

**no próprio instalador `install_tapo_c210_ptz_overlay_ha_v8.sh`** e execute-o de novo — mesma
regra da §12: o instalador é a fonte da verdade e sobrescreve o JS a cada execução.

Para um teste rápido dá para editar direto `/config/www/tapo-ptz-home.js`, mas a mudança é
**temporária**. Nesse caso, altere também o query-string da URL em `configuration.yaml` ou faça
hard refresh para evitar cache — e lembre que alterar o instalador invalida o SHA-256 publicado na §2.

---

## 16. Idempotência

A v8 foi desenhada para convergir sempre ao mesmo estado.

Primeira execução:

```bash
/config/install_tapo_c210_ptz_overlay_ha_v8.sh
```

Se houver diferenças, o script altera os arquivos, valida e reinicia o Core.

Execute novamente:

```bash
/config/install_tapo_c210_ptz_overlay_ha_v8.sh
```

Se tudo já estiver correto, o esperado é:

```text
[OK] ...tapo-ptz-home.js já está exatamente na v8.
[OK] configuration.yaml já contém exatamente uma referência PTZ v8.

RESULTADO: nenhuma alteração necessária — instalação já estava convergida para a v8.
Core não reiniciado: nada mudou.
```

Opções disponíveis:

```bash
/config/install_tapo_c210_ptz_overlay_ha_v8.sh --dry-run
/config/install_tapo_c210_ptz_overlay_ha_v8.sh --no-restart
/config/install_tapo_c210_ptz_overlay_ha_v8.sh --force-restart
```

---

# Troubleshooting

## 17. O overlay não aparece

Verifique, nesta ordem:

```bash
grep -n "tapo-ptz-home" /config/configuration.yaml
```

```bash
curl -I http://homeassistant.local:8123/local/tapo-ptz-home.js
```

```bash
ha core check
```

Depois faça:

```text
Cmd + Shift + R
```

e abra o Console do browser filtrando:

```text
Tapo PTZ
```

Se o módulo carregar mas nenhuma câmera receber overlay, confirme primeiro que a câmera expõe os quatro botões PTZ nativos.

---

## 18. Funciona no compacto, mas não no expandido

Isso normalmente indica mudança no componente interno do frontend.

A versão validada trata separadamente:

```text
hui-picture-entity-card
more-info-camera
```

Se uma atualização do Home Assistant alterar esses componentes, será necessário revisar o módulo.

---

## 19. O Live View não aparece

Confirme:

1. que **Live view** está habilitado na entrada da integração;
2. que a **Camera Account** está correta;
3. que a câmera está online;
4. que a entidade de Live View foi criada.

O card padrão `picture-entity` usa `camera_view: "auto"`; a v8 força `camera_view: "live"` na visão compacta.

---

## 20. Uma câmera move a outra?

Não deve acontecer.

A v8 não usa nomes globais ou IDs fixos. Cada câmera é associada aos próprios controles pelo `device_id` correspondente.

Se ocorrer movimento cruzado, interrompa o uso e verifique os registros de entidades/dispositivos antes de continuar.

---

# Remoção

## 21. Desinstalar somente o overlay

Remova de `configuration.yaml`:

```yaml
- /local/tapo-ptz-home.js?v=8
```

Depois:

```bash
rm -f /config/www/tapo-ptz-home.js
ha core check
ha core restart
```

Faça um hard refresh no browser.

Os backups do instalador ficam em:

```text
/config/backups/tapo-ptz-overlay/
```

A remoção do overlay **não remove a integração oficial TP-Link/Tapo nem as câmeras**.

---

# Upgrade e manutenção

## 22. Antes de atualizar o Home Assistant

A distinção mais importante deste projeto é:

### Parte oficialmente suportada

- integração TP-Link/Tapo;
- entidades de câmera/PTZ;
- `frontend.extra_module_url`.

### Parte customizada

- patch em runtime dos componentes internos:
  - `hui-picture-entity-card`;
  - `more-info-camera`.

Esses nomes e detalhes internos **não são uma API pública estável**.

Portanto, após uma atualização relevante do Home Assistant:

1. confirme se as câmeras continuam conectando pela integração oficial;
2. se reaparecer `SSLV3_ALERT_HANDSHAKE_FAILURE`, execute `/config/fix_tapo_tls_ecdhe_ha.sh --dry-run` e aplique apenas se necessário;
3. confirme Live View + PTZ nativo;
4. teste o overlay compacto e expandido;
5. teste **digitação + Enter/blur + setas** nos campos Pan/Tilt;
6. confira o Console por erros `[Tapo PTZ]`;
7. se os componentes internos do frontend tiverem mudado, revise o overlay contra a nova versão.

---

# Referências técnicas

## Home Assistant

- TP-Link Smart Home  
  https://www.home-assistant.io/integrations/tplink/

- Tapo  
  https://www.home-assistant.io/integrations/tplink_tapo/

- Frontend / `extra_module_url`  
  https://www.home-assistant.io/integrations/frontend/

- Camera building block  
  https://www.home-assistant.io/integrations/camera/

## Home Assistant Core 2026.8.2

- PTZ buttons  
  https://github.com/home-assistant/core/blob/2026.8.2/homeassistant/components/tplink/button.py

- Pan/Tilt step  
  https://github.com/home-assistant/core/blob/2026.8.2/homeassistant/components/tplink/number.py

- Motion / Person / LED / Tamper  
  https://github.com/home-assistant/core/blob/2026.8.2/homeassistant/components/tplink/switch.py

- `python-kasa==0.10.2` no manifest da integração  
  https://github.com/home-assistant/core/blob/2026.8.2/homeassistant/components/tplink/manifest.json

## Home Assistant Frontend 20260729.6

- Strategy das áreas — câmera gerada como `picture-entity`  
  https://github.com/home-assistant/frontend/blob/20260729.6/src/panels/lovelace/strategies/areas/helpers/areas-strategy-helper.ts

- `hui-picture-entity-card`  
  https://github.com/home-assistant/frontend/blob/20260729.6/src/panels/lovelace/cards/hui-picture-entity-card.ts

- `more-info-camera`  
  https://github.com/home-assistant/frontend/blob/20260729.6/src/dialogs/more-info/controls/more-info-camera.ts

- `ha-camera-stream`  
  https://github.com/home-assistant/frontend/blob/20260729.6/src/components/ha-camera-stream.ts

## Bugs / upstream

- Home Assistant Core #164045 — C210 HW 2.0 / firmware 1.5.2 e TLS handshake failure  
  https://github.com/home-assistant/core/issues/164045

- python-kasa #1724 — `SslAesTransport` sem ECDHE em firmwares recentes  
  https://github.com/python-kasa/python-kasa/issues/1724

## TP-Link

- Conta da Câmera Tapo  
  https://www.tp-link.com/br/support/faq/2790/

- RTSP / ONVIF  
  https://www.tp-link.com/br/support/faq/2680/

---

# Escopo validado

O procedimento descrito aqui foi testado de ponta a ponta com **duas Tapo C210 simultaneamente** na mesma instalação do Home Assistant.

A **v8** consolida o comportamento validado: Live View nas duas câmeras, D-pad PTZ independente por `device_id`, direção `pan` invertida, direção `tilt` nominal, controles operacionais na visão expandida, D-pad compacto parametrizado com escala padrão `0.72` e edição confiável de Pan/Tilt por teclado, Enter, blur e setas.

O workaround TLS separado também foi reaplicado com sucesso após uma atualização posterior do Home Assistant, confirmando na prática o motivo de ele permanecer desacoplado do instalador de UI.

Ele registra separadamente:

- o que é comportamento/documentação oficial;
- o que é workaround upstream ainda não incorporado à versão testada;
- o que é customização local de frontend.

Essa separação é intencional para tornar o processo reproduzível e facilitar manutenção futura.

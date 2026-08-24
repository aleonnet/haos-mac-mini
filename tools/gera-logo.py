#!/usr/bin/env python3
"""
gera-logo.py — gera a máscara do logo do Home Assistant para o terminal.

Desenhar arte ASCII à mão erra proporção e não escala. Aqui a geometria é
calculada e o resultado sai como fragmento bash pronto para a lib.

Resolução: meio-bloco. Cada célula do terminal vira DOIS pixels — o de cima
pinta a frente do "▀", o de baixo pinta o fundo. Como a célula é ~2:1, o pixel
resultante fica quase quadrado, e a resolução vertical dobra.

Máscara por pixel:
    .  fora           #  corpo da casa (azul)          o  circuito (branco)

O traço branco é uma FAIXA, não um contorno de um pixel: cada pixel dela sabe
onde está ao longo do caminho (HA_TT), e é isso que permite animar espessura —
cabeça e cauda andam em posição de arco, não em índice de pixel. O contorno de
um pixel é o caso degenerado da faixa, com espessura pequena.

    ./tools/gera-logo.py                imprime o fragmento bash
    ./tools/gera-logo.py --preview      desenha no terminal para conferir
    ./tools/gera-logo.py --medir        só os números, para comparar geometrias
    ./tools/gera-logo.py --variante 2   usa um dos presets do escolhedor
    ./tools/gera-logo.py --casa 24 --espessura 2.6 --raio 5 --dmin 0 --margem 6
"""
import math, sys

# ── presets ──────────────────────────────────────────────────────────────────
# São as variantes que tools/escolhe-logo.sh desenha em sequência. A 0 é a
# geometria de 48 px que está em produção; as demais encolhem a casa e engrossam
# o traço, que foi o pedido.
#
# dmin é o que separa uma faixa que RESPEITA a casa de uma que a come: com
# dmin < 0 a faixa entra no corpo azul, e num telhado a 45° as duas bordas
# convergem perto do ápice — a faixa se sobrepõe a si mesma e entope o bico.
# Medido: casa 28 / esp 2.6 / raio 3 / dmin -0.9 come 42% da casa.
# A variante 0 do escolhedor NÃO está aqui de propósito: ela é o lib/haos-ui.sh
# atual, sourceado como está, para a comparação ser com o que roda hoje e não
# com uma reconstrução. Reconstruir os 48 px por esta fórmula dá come=20,3%, que
# não é a geometria em produção.
VARIANTES = {
    1: dict(casa=24.0, margem=6.0, espessura=2.0, raio=5.0, dmin=0.0),
    2: dict(casa=24.0, margem=6.0, espessura=2.6, raio=5.0, dmin=0.0),
    3: dict(casa=24.0, margem=6.0, espessura=3.0, raio=5.0, dmin=0.0),
    4: dict(casa=20.0, margem=6.0, espessura=2.6, raio=5.0, dmin=0.0),
    5: dict(casa=28.0, margem=7.0, espessura=2.6, raio=6.0, dmin=0.0),
    6: dict(casa=28.0, margem=6.0, espessura=2.6, raio=5.0, dmin=0.0),
    7: dict(casa=24.0, margem=7.0, espessura=3.6, raio=6.0, dmin=0.0),
}

# ── parâmetros ───────────────────────────────────────────────────────────────
P = dict(casa=24.0, margem=6.0, espessura=2.6, raio=5.0, dmin=0.0, telhado=0.46)

def _arg(nome, conv=float):
    """--nome valor; devolve None se ausente. Erro explícito em valor inválido:
    um typo aqui sai como geometria silenciosamente errada, e foi assim que a
    tentativa anterior chegou ao commit."""
    flag = "--" + nome
    if flag not in sys.argv:
        return None
    i = sys.argv.index(flag)
    if i + 1 >= len(sys.argv):
        sys.exit(f"gera-logo.py: {flag} exige um valor")
    try:
        return conv(sys.argv[i + 1])
    except ValueError:
        sys.exit(f"gera-logo.py: valor inválido para {flag}: {sys.argv[i + 1]!r}")

_v = _arg("variante", int)
if _v is not None:
    if _v not in VARIANTES:
        _ok = " ".join(str(k) for k in sorted(VARIANTES))
        sys.exit(f"gera-logo.py: variante {_v} não existe (há: {_ok}; "
                 f"a 0 é o lib atual, desenhada por tools/escolhe-logo.sh)")
    P.update(VARIANTES[_v])
for _nome in ("casa", "margem", "espessura", "raio", "dmin", "telhado"):
    _x = _arg(_nome)
    if _x is not None:
        P[_nome] = _x

CASA      = P["casa"]
MARGEM    = P["margem"]
ESPESSURA = P["espessura"]
RAIO      = P["raio"]
DMIN      = P["dmin"]
TELHADO   = P["telhado"]
W = int(CASA + MARGEM * 2)
H = W

# A faixa cresce ESPESSURA para fora da casa; sem margem para isso ela sai
# cortada na borda do canvas e o traço "some" de um lado só.
# O render é meio-bloco: lê as linhas aos pares (y, y+1). Com H ímpar a última
# linha não tem par, e em bash o índice fora do array vira string vazia — o
# desenho perde a base sem nenhum erro.
if H % 2 != 0:
    sys.exit(f"gera-logo.py: casa {CASA:g} + 2*margem {MARGEM:g} = {H}, que é ímpar; "
             f"o render é meio-bloco e exige altura par")

if MARGEM < ESPESSURA + 1.0:
    sys.exit(f"gera-logo.py: margem {MARGEM} é curta para espessura {ESPESSURA} "
             f"(precisa de pelo menos {ESPESSURA + 1.0})")

# A geometria vai gravada no fragmento para o portão poder regerar e comparar.
GEOMETRIA = (f"--casa {CASA:g} --margem {MARGEM:g} --espessura {ESPESSURA:g} "
             f"--raio {RAIO:g} --dmin {DMIN:g} --telhado {TELHADO:g}")

def _dist_seg(px, py, x1, y1, x2, y2):
    dx, dy = x2 - x1, y2 - y1
    L = dx * dx + dy * dy
    t = 0.0 if L == 0 else max(0.0, min(1.0, ((px - x1) * dx + (py - y1) * dy) / L))
    return math.hypot(px - (x1 + t * dx), py - (y1 + t * dy))

def _casa_encolhida():
    """Pentágono do HA arredondado por Minkowski: encolhe por RAIO e depois
    toma tudo a distância <= RAIO. Arredondar cada canto com um arco à parte
    deixa degrau na junção com a rampa do telhado."""
    x0, y0 = MARGEM, MARGEM
    cx = x0 + CASA / 2.0
    ombro = y0 + CASA * TELHADO
    V = [(cx, y0), (x0 + CASA, ombro), (x0 + CASA, y0 + CASA),
         (x0, y0 + CASA), (x0, ombro)]
    N = []
    for i in range(len(V)):
        x1, y1 = V[i]; x2, y2 = V[(i + 1) % len(V)]
        ex, ey = x2 - x1, y2 - y1
        L = math.hypot(ex, ey)
        nx, ny = ey / L, -ex / L
        N.append((nx, ny, nx * x1 + ny * y1))
    Vs = []
    for i in range(len(N)):
        a1, b1, c1 = N[i - 1]; a2, b2, c2 = N[i]
        c1 -= RAIO; c2 -= RAIO
        det = a1 * b2 - a2 * b1
        if abs(det) < 1e-9:
            continue
        Vs.append(((c1 * b2 - c2 * b1) / det, (a1 * c2 - a2 * c1) / det))
    return Vs

CASA_VS = _casa_encolhida()

def _dist_ao_contorno(px, py):
    """distância ao contorno do polígono encolhido, e se está dentro"""
    n = len(CASA_VS)
    dentro = True
    for i in range(n):
        x1, y1 = CASA_VS[i]; x2, y2 = CASA_VS[(i + 1) % n]
        if (x2 - x1) * (py - y1) - (y2 - y1) * (px - x1) < 0:
            dentro = False; break
    d = min(_dist_seg(px, py, CASA_VS[i][0], CASA_VS[i][1],
                      CASA_VS[(i + 1) % n][0], CASA_VS[(i + 1) % n][1])
            for i in range(len(CASA_VS)))
    return d, dentro

def dentro_casa(x, y):
    d, dentro = _dist_ao_contorno(x + 0.5, y + 0.5)
    return dentro or d <= RAIO

def dentro_circuito(x, y):
    """Circuito do HA. Proporções medidas no logo oficial:
    disco de cima 50%/33% · direita 75%/58% · esquerda 25%/73%."""
    px, py = x + 0.5, y + 0.5
    x0, y0 = MARGEM, MARGEM
    ESP = CASA * 0.042          # traço fino: ele pediu delicado
    R_DISCO = CASA * 0.085

    topo    = (x0 + CASA * 0.50, y0 + CASA * 0.33)
    direita = (x0 + CASA * 0.75, y0 + CASA * 0.58)
    esq     = (x0 + CASA * 0.25, y0 + CASA * 0.73)
    base    = (x0 + CASA * 0.50, y0 + CASA * 0.93)

    if _dist_seg(px, py, topo[0], topo[1], base[0], base[1]) <= ESP: return True
    if _dist_seg(px, py, direita[0], direita[1], x0 + CASA * 0.50, y0 + CASA * 0.79) <= ESP: return True
    if _dist_seg(px, py, esq[0], esq[1], base[0], base[1]) <= ESP: return True
    for cxx, cyy in (topo, direita, esq):
        if math.hypot(px - cxx, py - cyy) <= R_DISCO: return True
    return False

# ── caminho do traço: o contorno amostrado denso, com comprimento de arco ────
def _caminho():
    n = len(CASA_VS)
    pts = []
    for i in range(n):
        x1, y1 = CASA_VS[i]; x2, y2 = CASA_VS[(i + 1) % n]
        L = math.hypot(x2 - x1, y2 - y1)
        passos = max(2, int(L * 4))
        for k in range(passos):
            t = k / passos
            pts.append((x1 + (x2 - x1) * t, y1 + (y2 - y1) * t))
    # começa embaixo no centro e sobe pela ESQUERDA, como no logo oficial
    mx = sum(p[0] for p in pts) / len(pts)
    my = sum(p[1] for p in pts) / len(pts)
    pts.sort(key=lambda p: (math.atan2(p[1] - my, p[0] - mx) - math.pi / 2) % (2 * math.pi))
    return pts

CAMINHO = _caminho()
M = len(CAMINHO)

# ── monta a máscara ──────────────────────────────────────────────────────────
mask = []
for y in range(H):
    linha = []
    for x in range(W):
        if not dentro_casa(x, y):
            linha.append('.')
        elif dentro_circuito(x, y):
            linha.append('o')
        else:
            linha.append('#')
    mask.append(''.join(linha))

# ── faixa do traço: pixels perto do contorno, com sua posição no caminho ─────
traco = []          # (x, y, indice_no_caminho)
for y in range(H):
    for x in range(W):
        px, py = x + 0.5, y + 0.5
        melhor, idx = 1e9, -1
        for i, (cx_, cy_) in enumerate(CAMINHO):
            d = (px - cx_) ** 2 + (py - cy_) ** 2
            if d < melhor:
                melhor, idx = d, i
        # A faixa monta na borda VERDADEIRA da casa, que fica a RAIO do
        # polígono encolhido — não no encolhido. Centrar no encolhido escondia
        # o traço inteiro sob o corpo azul.
        d = math.sqrt(melhor) - RAIO
        if DMIN <= d <= ESPESSURA:
            traco.append((x, y, idx))
traco.sort(key=lambda t: t[2])

# ── quanto a faixa come da casa ──────────────────────────────────────────────
casa_px = sum(1 for y in range(H) for x in range(W) if mask[y][x] in '#o')
come_px = sum(1 for x, y, _ in traco if mask[y][x] in '#o')

if '--medir' in sys.argv:
    pct = 100.0 * come_px / casa_px if casa_px else 0.0
    print(f"{GEOMETRIA}")
    print(f"canvas={W}x{H}px ({W} col x {H//2} linhas)  casa={casa_px}  "
          f"traco={len(traco)}  come={come_px} ({pct:.1f}%)  "
          f"traco/casa={len(traco)/casa_px:.2f}  caminho={M}")
    sys.exit(0)

if '--mask' in sys.argv:
    for y in range(H):
        sys.stdout.write(''.join('  ' if c == '.' else ('##' if c == '#' else '@@')
                                 for c in mask[y]) + '\n')
    sys.exit(0)

if '--preview' in sys.argv:
    tr = {(x, y) for x, y, _ in traco}
    for y in range(0, H, 2):
        for x in range(W):
            a = 't' if (x, y) in tr else mask[y][x]
            b = 't' if (x, y + 1) in tr else (mask[y + 1][x] if y + 1 < H else '.')
            ch = {'..': ' ', '.#': '▄', '.o': '▄', '.t': '▄',
                  '#.': '▀', 'o.': '▀', 't.': '▀'}.get(a + b, '█')
            sys.stdout.write(ch)
        sys.stdout.write('\n')
    pct = 100.0 * come_px / casa_px if casa_px else 0.0
    print(f"\n{W}x{H} px -> {W} col x {H//2} linhas · caminho {M} · "
          f"traço {len(traco)} px · come {come_px} ({pct:.1f}%)")
    sys.exit(0)

print("# ── GERADO por tools/gera-logo.py — NÃO editar à mão ──────────────────────")
print(f"# Regerar com: ./tools/gera-logo.py {GEOMETRIA}")
print("# Máscara do logo do Home Assistant, por pixel:")
print("#   .  fora    #  corpo da casa    o  circuito")
print("# HA_TX/HA_TY/HA_TT são a FAIXA do traço, em vetores paralelos e já")
print("# ordenados pela posição no caminho. HA_TT guarda essa posição, que é o")
print("# que permite animar uma faixa ESPESSA: cabeça e cauda andam em posição")
print("# de arco, não em índice de pixel.")
print(f"HA_GEOMETRIA='{GEOMETRIA}'")
print(f"HA_W={W}")
print(f"HA_H={H}")
print(f"HA_CAMINHO={M}")
print("HA_MASK=(")
for l in mask:
    print(f"'{l}'")
print(")")
print("HA_TX=(" + " ".join(str(t[0]) for t in traco) + ")")
print("HA_TY=(" + " ".join(str(t[1]) for t in traco) + ")")
print("HA_TT=(" + " ".join(str(t[2]) for t in traco) + ")")

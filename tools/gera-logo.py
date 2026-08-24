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

    ./tools/gera-logo.py            imprime o fragmento bash
    ./tools/gera-logo.py --preview  desenha no terminal para conferir
"""
import math, sys

# ── dimensões ────────────────────────────────────────────────────────────────
# O traço branco corre POR FORA da casa, então o canvas tem margem — sem ela
# não haveria onde engrossá-lo.
CASA = 28.0     # lado da casa, em pixels
MARGEM = 4.0    # espaço para o traço respirar
ESPESSURA = 2.6 # meia-espessura do traço, em pixels
W = int(CASA + MARGEM * 2)
H = W
TELHADO = 0.46  # fração da altura da casa ocupada pelo telhado
RAIO = 3.0      # arredondamento dos cantos

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
                      CASA_VS[(i + 1) % n][0], CASA_VS[(i + 1) % n][1]) for i in range(n))
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
# Cada pixel do traço precisa saber ONDE está ao longo do caminho, senão não dá
# para animar uma faixa espessa: a cabeça e a cauda andam em posição de arco,
# não em índice de pixel.
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

# ── monta a mascara ──────────────────────────────────────────────────────────
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
M = len(CAMINHO)
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
        # Assimétrica de propósito: mais para fora que para dentro, como no
        # logo oficial, onde o branco contorna o azul em vez de comê-lo.
        d = math.sqrt(melhor) - RAIO
        if -0.9 <= d <= ESPESSURA:
            traco.append((x, y, idx))
traco.sort(key=lambda t: t[2])

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
    print(f"\n{W}x{H} px -> {W} col x {H//2} linhas · caminho {M} · traço {len(traco)} px")
    sys.exit(0)

print("# ── GERADO por tools/gera-logo.py — NÃO editar à mão ──────────────────────")
print("# Máscara do logo do Home Assistant, por pixel:")
print("#   .  fora    #  corpo da casa    o  circuito")
print("# HA_TX/HA_TY/HA_TT são a FAIXA do traço, em vetores paralelos e já")
print("# ordenados pela posição no caminho. HA_TT guarda essa posição, que é o")
print("# que permite animar uma faixa ESPESSA: cabeça e cauda andam em posição")
print("# de arco, não em índice de pixel.")
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

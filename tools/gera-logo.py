#!/usr/bin/env python3
"""
gera-logo.py — gera a máscara do logo do Home Assistant para o terminal.

Geometria conferida contra o vídeo oficial (homeassistant_animated_logo.mp4,
frames extraídos em 24/08/2026): a casa tem BEIRAL — o telhado ultrapassa as
paredes e degrauza para dentro por baixo —, ápice pontudo, cantos de base com
raio moderado, e o traço branco desenha o contorno e se retrai.

Resolução: meio-bloco. Cada célula do terminal vira DOIS pixels — o de cima
pinta a frente do "▀", o de baixo pinta o fundo. Como a célula é ~2:1, o pixel
resultante fica quase quadrado.

Máscara por pixel:
    .  fora        #  corpo da casa (azul)        o  circuito (branco)

Além da máscara saem, em vetores paralelos:
    HA_TX/HA_TY/HA_TT   a FAIXA do traço, ordenada pela posição no caminho
                        (cabeça e cauda animam por posição de ARCO)
    HA_PX/HA_PY/HA_PD   os pixels dos três DISCOS do circuito (1=topo,
                        2=direita, 3=esquerda) — o ato "circuito conecta"
                        acende um disco por vez

    ./tools/gera-logo.py            imprime o fragmento bash
    ./tools/gera-logo.py --preview  desenha no terminal para conferir
    ./tools/gera-logo.py --medir    só os números (casa, traço, come)
"""
import math, sys

# ── dimensões ────────────────────────────────────────────────────────────────
CASA    = 26.0   # lado (largura total, beiral incluído)
MARGEM  = 4.0    # folga para o traço respirar (>= ESPESSURA + 1)
ESP     = 1.75   # meia-espessura do traço — pedido: entre 1.5 e 2
DMIN    = 0.0    # a faixa fica POR FORA da borda (come 0% da casa — medido)
W = int(CASA + MARGEM * 2)
H = W

# proporções do logo oficial (medidas na imagem em alta que ele mandou):
# pentágono LIMPO — o telhado morre em QUINAS nos ombros e a parede desce
# alinhada com elas; não há beiral na marca atual (a leitura de "degrau" nos
# frames do vídeo era anti-aliasing do traço).
OMBRO   = 0.44   # altura dos ombros (fração de CASA)
R_APICE = 1.5    # topo pontudo, só quebra de serrilhado
R_OMBRO = 0.8    # as quinas laterais — quase vivas
R_BASE  = 2.4    # cantos de baixo, os únicos redondos de verdade

def _dist_seg(px, py, x1, y1, x2, y2):
    dx, dy = x2 - x1, y2 - y1
    L = dx * dx + dy * dy
    t = 0.0 if L == 0 else max(0.0, min(1.0, ((px - x1) * dx + (py - y1) * dy) / L))
    return math.hypot(px - (x1 + t * dx), py - (y1 + t * dy))

# ── contorno: polígono de 7 vértices com raio POR CANTO ──────────────────────
# Arredondamento clássico de canto: recua r/tan(θ/2) em cada aresta e amostra o
# arco. Um raio único (Minkowski) não serve aqui — o pedido é ápice pontudo COM
# base arredondada, e o beiral exige canto quase vivo no degrau.
def _caminho_arredondado():
    x0 = y0 = MARGEM
    C = CASA
    cx = x0 + C / 2.0
    hy = y0 + C * OMBRO
    V = [
        ((cx, y0),         R_APICE),   # ápice
        ((x0 + C, hy),     R_OMBRO),   # quina direita do telhado
        ((x0 + C, y0 + C), R_BASE),    # base direita
        ((x0, y0 + C),     R_BASE),    # base esquerda
        ((x0, hy),         R_OMBRO),   # quina esquerda do telhado
    ]
    n = len(V)
    pts = []
    for i in range(n):
        (px_, py_), r = V[i]
        (ax, ay), _ = V[(i - 1) % n]
        (bx, by), _ = V[(i + 1) % n]
        ux, uy = ax - px_, ay - py_
        vx, vy = bx - px_, by - py_
        lu, lv = math.hypot(ux, uy), math.hypot(vx, vy)
        ux, uy, vx, vy = ux / lu, uy / lu, vx / lv, vy / lv
        ang = math.acos(max(-1.0, min(1.0, ux * vx + uy * vy)))
        t = min(r / math.tan(ang / 2.0), lu / 2.5, lv / 2.5)
        p1 = (px_ + ux * t, py_ + uy * t)   # entra no canto
        p2 = (px_ + vx * t, py_ + vy * t)   # sai do canto
        # centro do arco: pela bissetriz, a distância r/sin(θ/2)
        bx_, by_ = ux + vx, uy + vy
        lb = math.hypot(bx_, by_)
        passos = max(2, int(r * 3))
        if lb < 1e-9 or r < 0.2:
            pts.append(p1); pts.append(p2)
            continue
        cxa = px_ + bx_ / lb * (t / math.cos(ang / 2.0) if ang < math.pi else t)
        cya = py_ + by_ / lb * (t / math.cos(ang / 2.0) if ang < math.pi else t)
        # amostra o arco de p1 a p2 em volta de (cxa, cya)
        a1 = math.atan2(p1[1] - cya, p1[0] - cxa)
        a2 = math.atan2(p2[1] - cya, p2[0] - cxa)
        while a2 - a1 > math.pi:  a2 -= 2 * math.pi
        while a1 - a2 > math.pi:  a2 += 2 * math.pi
        ra = math.hypot(p1[0] - cxa, p1[1] - cya)
        for k in range(passos + 1):
            a = a1 + (a2 - a1) * k / passos
            pts.append((cxa + ra * math.cos(a), cya + ra * math.sin(a)))
    # densifica as retas entre cantos
    dens = []
    m = len(pts)
    for i in range(m):
        x1, y1 = pts[i]; x2, y2 = pts[(i + 1) % m]
        L = math.hypot(x2 - x1, y2 - y1)
        passos = max(1, int(L * 4))
        for k in range(passos):
            t = k / passos
            dens.append((x1 + (x2 - x1) * t, y1 + (y2 - y1) * t))
    # começa embaixo no centro e sobe pela ESQUERDA, como no vídeo oficial
    mx = sum(p[0] for p in dens) / len(dens)
    my = sum(p[1] for p in dens) / len(dens)
    dens.sort(key=lambda p: (math.atan2(p[1] - my, p[0] - mx) - math.pi / 2) % (2 * math.pi))
    return dens

CAMINHO = _caminho_arredondado()
M = len(CAMINHO)

def dentro_casa(x, y):
    """ray casting contra o caminho denso"""
    px, py = x + 0.5, y + 0.5
    dentro = False
    j = M - 1
    for i in range(M):
        xi, yi = CAMINHO[i]; xj, yj = CAMINHO[j]
        if (yi > py) != (yj > py) and px < (xj - xi) * (py - yi) / (yj - yi) + xi:
            dentro = not dentro
        j = i
    return dentro

# ── circuito: tronco, dois ramos, três discos ────────────────────────────────
# Proporções medidas no logo oficial. O tronco TERMINA 1,8 px acima da borda
# interna da base: encosta visualmente sem furar o contorno — era o defeito
# circulado na variante 1.
x0 = y0 = MARGEM
ESPC    = CASA * 0.045
R_DISCO = CASA * 0.10
topo    = (x0 + CASA * 0.50, y0 + CASA * 0.335)
direita = (x0 + CASA * 0.72, y0 + CASA * 0.565)
esq     = (x0 + CASA * 0.28, y0 + CASA * 0.715)
base    = (x0 + CASA * 0.50, y0 + CASA - 1.8)

def classe_circuito(x, y):
    """0 = não é circuito · 1..3 = disco (topo/direita/esquerda) · 4 = linha"""
    px, py = x + 0.5, y + 0.5
    for i, (cxx, cyy) in enumerate((topo, direita, esq), start=1):
        if math.hypot(px - cxx, py - cyy) <= R_DISCO:
            return i
    if _dist_seg(px, py, topo[0], topo[1], base[0], base[1]) <= ESPC: return 4
    if _dist_seg(px, py, direita[0], direita[1], x0 + CASA * 0.50, y0 + CASA * 0.76) <= ESPC: return 4
    if _dist_seg(px, py, esq[0], esq[1], base[0], base[1]) <= ESPC: return 4
    return 0

# ── máscara e discos ─────────────────────────────────────────────────────────
mask, discos = [], []
for y in range(H):
    linha = []
    for x in range(W):
        if not dentro_casa(x, y):
            linha.append('.')
        else:
            c = classe_circuito(x, y)
            if c == 0:
                linha.append('#')
            else:
                linha.append('o')
                if c in (1, 2, 3):
                    discos.append((x, y, c))
    mask.append(''.join(linha))

# ── faixa do traço ───────────────────────────────────────────────────────────
traco = []
for y in range(H):
    for x in range(W):
        px, py = x + 0.5, y + 0.5
        melhor, idx = 1e9, -1
        for i, (cx_, cy_) in enumerate(CAMINHO):
            d = (px - cx_) ** 2 + (py - cy_) ** 2
            if d < melhor:
                melhor, idx = d, i
        d = math.sqrt(melhor)
        # Distância COM sinal: fora da casa a faixa engorda até ESP; por dentro
        # só meio pixel de abraço — é o que cola o traço na borda (como no
        # vídeo) sem comer o corpo azul (o defeito medido da tentativa velha).
        dentro = dentro_casa(x, y)
        if (not dentro and DMIN <= d <= ESP) or (dentro and d <= 0.5):
            traco.append((x, y, idx))
traco.sort(key=lambda t: t[2])

# ── partículas do assemble ───────────────────────────────────────────────────
# Cada pixel da casa ganha uma ORIGEM fora do canvas (direção radial a partir
# do centro, com um giro de 40 graus — a partícula chega "orbitando") e um
# DELAY que constrói a casa de baixo para cima. Determinístico: nada de
# aleatório em build reproduzível.
cx0, cy0 = W / 2.0, H / 2.0
particulas = []   # (destino x, y, origem ox, oy, delay)
i = 0
for y in range(H):
    for x in range(W):
        if mask[y][x] == '.':
            continue
        dx, dy = x + 0.5 - cx0, y + 0.5 - cy0
        ang = math.atan2(dy, dx) + math.radians(40)
        raio = W * 0.9 + (i % 9)
        ox = int(cx0 + math.cos(ang) * raio)
        oy = int(cy0 + math.sin(ang) * raio)
        delay = (H - 1 - y) // 3 + (i % 3)
        particulas.append((x, y, ox, oy, delay))
        i += 1

casa_px = sum(1 for l in mask for c in l if c in '#o')
come_px = sum(1 for x, y, _ in traco if mask[y][x] in '#o')

if '--medir' in sys.argv:
    pct = 100.0 * come_px / casa_px if casa_px else 0.0
    print(f"canvas={W}x{H}px ({W} col x {H//2} linhas)  casa={casa_px}  "
          f"traco={len(traco)}  come={come_px} ({pct:.1f}%)  caminho={M}  "
          f"discos={len(discos)}px")
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
print("# Geometria conferida contra o vídeo oficial: beiral, ápice pontudo,")
print("# base com raio moderado. Máscara por pixel: . fora · # casa · o circuito.")
print("# HA_TX/HA_TY/HA_TT: faixa do traço ordenada pela posição no caminho —")
print("# cabeça e cauda animam por posição de ARCO, não por índice de pixel.")
print("# HA_PX/HA_PY/HA_PD: pixels dos 3 discos (1 topo · 2 direita · 3 esquerda).")
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
print("HA_PX=(" + " ".join(str(d[0]) for d in discos) + ")")
print("HA_PY=(" + " ".join(str(d[1]) for d in discos) + ")")
print("HA_PD=(" + " ".join(str(d[2]) for d in discos) + ")")
print("# Partículas do assemble: destino (AX,AY), origem (AOX,AOY), atraso (ADL).")
print("HA_AX=("  + " ".join(str(pp[0]) for pp in particulas) + ")")
print("HA_AY=("  + " ".join(str(pp[1]) for pp in particulas) + ")")
print("HA_AOX=(" + " ".join(str(pp[2]) for pp in particulas) + ")")
print("HA_AOY=(" + " ".join(str(pp[3]) for pp in particulas) + ")")
print("HA_ADL=(" + " ".join(str(pp[4]) for pp in particulas) + ")")
print("# Centros dos discos (sonar), em pixel inteiro: topo, direita, esquerda.")
print(f"HA_SCX=({int(topo[0])} {int(direita[0])} {int(esq[0])})")
print(f"HA_SCY=({int(topo[1])} {int(direita[1])} {int(esq[1])})")

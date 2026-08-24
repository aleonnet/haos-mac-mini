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

W = 48          # pixels de largura  -> 48 colunas
H = 48          # pixels de altura   -> 24 linhas de terminal
RAIO = 5.0      # raio do arredondamento, IGUAL em todos os cantos
TELHADO = 0.46  # fração da altura ocupada pelo telhado

def _dist_seg(px, py, x1, y1, x2, y2):
    dx, dy = x2 - x1, y2 - y1
    L = dx * dx + dy * dy
    t = 0.0 if L == 0 else max(0.0, min(1.0, ((px - x1) * dx + (py - y1) * dy) / L))
    return math.hypot(px - (x1 + t * dx), py - (y1 + t * dy))

def _constroi_casa():
    """Pentágono do HA arredondado por Minkowski: encolhe o polígono por RAIO e
    depois toma tudo que está a distância <= RAIO dele.

    Arredondar cada canto com um arco à parte, que foi a primeira tentativa,
    deixa degrau na junção do arco com a rampa — o telhado ganhava um patamar
    de três linhas antes de voltar a abrir. Encolher e engordar dá o mesmo raio
    em todo canto, por construção.
    """
    cx = W / 2.0
    ombro = H * TELHADO
    # pentágono afiado, em sentido horário a partir do ápice
    V = [(cx, 0.0), (float(W), ombro), (float(W), float(H)), (0.0, float(H)), (0.0, ombro)]

    # normais externas de cada aresta e a distância da origem
    N = []
    for i in range(len(V)):
        x1, y1 = V[i]; x2, y2 = V[(i + 1) % len(V)]
        ex, ey = x2 - x1, y2 - y1
        L = math.hypot(ex, ey)
        nx, ny = ey / L, -ex / L          # horário -> normal externa
        N.append((nx, ny, nx * x1 + ny * y1))

    # vértices do polígono encolhido: interseção das arestas deslocadas por RAIO
    Vs = []
    for i in range(len(N)):
        a1, b1, c1 = N[i - 1]; a2, b2, c2 = N[i]
        c1 -= RAIO; c2 -= RAIO
        det = a1 * b2 - a2 * b1
        if abs(det) < 1e-9:
            continue
        Vs.append((((c1 * b2 - c2 * b1) / det), ((a1 * c2 - a2 * c1) / det)))
    return Vs

CASA_VS = _constroi_casa()

def dentro_casa(x, y):
    px, py = x + 0.5, y + 0.5
    n = len(CASA_VS)
    # dentro do polígono encolhido?
    dentro = True
    for i in range(n):
        x1, y1 = CASA_VS[i]; x2, y2 = CASA_VS[(i + 1) % n]
        if (x2 - x1) * (py - y1) - (y2 - y1) * (px - x1) < 0:   # horário, y para baixo
            dentro = False; break
    if dentro:
        return True
    # senão, a distância até a borda do encolhido tem de caber no raio
    d = min(_dist_seg(px, py, CASA_VS[i][0], CASA_VS[i][1],
                      CASA_VS[(i + 1) % n][0], CASA_VS[(i + 1) % n][1]) for i in range(n))
    return d <= RAIO

def seg(px, py, x1, y1, x2, y2):
    return _dist_seg(px, py, x1, y1, x2, y2)

def dentro_circuito(x, y):
    """O circuito do HA: haste vertical, dois ramos diagonais que nela se
    juntam em alturas diferentes, e um disco na ponta de cada um dos três.

    As proporções vêm de medir o logo oficial, não de estimativa:
    disco de cima 50%/33% · direita 75%/58% · esquerda 25%/73%.
    """
    px, py = x + 0.5, y + 0.5
    ESP = 2.0          # meia-espessura do traço
    R_DISCO = 4.2

    topo   = (W * 0.50, H * 0.33)
    direita= (W * 0.75, H * 0.58)
    esq    = (W * 0.25, H * 0.73)
    base   = (W * 0.50, H * 0.93)

    # haste central, do disco de cima até a base
    if _dist_seg(px, py, topo[0], topo[1], base[0], base[1]) <= ESP:
        return True
    # ramo direito encontra a haste mais acima; o esquerdo, quase na base
    if _dist_seg(px, py, direita[0], direita[1], W * 0.50, H * 0.79) <= ESP:
        return True
    if _dist_seg(px, py, esq[0], esq[1], base[0], base[1]) <= ESP:
        return True
    for cxx, cyy in (topo, direita, esq):
        if math.hypot(px - cxx, py - cyy) <= R_DISCO:
            return True
    return False

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

# ── perimetro ORDENADO: é o caminho que o traço branco percorre ─────────────
# Pixel do corpo que faz fronteira com o lado de fora. A casa é convexa, então
# ordenar por ângulo em torno do centroide dá uma volta limpa, sem grafo.
borda = []
for y in range(H):
    for x in range(W):
        if mask[y][x] == '.':
            continue
        for ax, ay in ((1,0), (-1,0), (0,1), (0,-1)):
            nx, ny = x + ax, y + ay
            if nx < 0 or ny < 0 or nx >= W or ny >= H or mask[ny][nx] == '.':
                borda.append((x, y)); break

mx = sum(p[0] for p in borda) / len(borda)
my = sum(p[1] for p in borda) / len(borda)
# começa embaixo, no centro, e sobe pela ESQUERDA — como no logo oficial
borda.sort(key=lambda p: (math.atan2(p[1] - my, p[0] - mx) - math.pi/2) % (2*math.pi))

if '--preview' in sys.argv:
    for y in range(0, H, 2):
        for x in range(W):
            t, b = mask[y][x], mask[y+1][x] if y+1 < H else '.'
            ch = {'..': ' ', '.#': '▄', '.o': '▄', '#.': '▀', 'o.': '▀'}.get(t+b, '█')
            sys.stdout.write(ch)
        sys.stdout.write('\n')
    print(f"\n{W}x{H} px -> {W} colunas x {H//2} linhas · perímetro: {len(borda)} pixels")
    sys.exit(0)

print("# ── GERADO por tools/gera-logo.py — NÃO editar à mão ──────────────────────")
print("# Máscara do logo do Home Assistant, por pixel:")
print("#   .  fora    #  corpo da casa    o  circuito")
print("# HA_BX/HA_BY são o contorno JÁ ORDENADO, em vetores PARALELOS: é o caminho")
print("# que o traço percorre, começando embaixo no centro e subindo pela esquerda,")
print("# como no logo oficial. Dois vetores em vez de \"x,y\" numa string evitam")
print("# fatiar texto no laço mais quente do render.")
print(f"HA_W={W}")
print(f"HA_H={H}")
print("HA_MASK=(")
for l in mask:
    print(f"'{l}'")
print(")")
print("HA_BX=(" + " ".join(str(x) for x, _ in borda) + ")")
print("HA_BY=(" + " ".join(str(y) for _, y in borda) + ")")

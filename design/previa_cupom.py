"""Prévia visual do cupom de 58 mm (32 colunas), espelhando gerarCupom() do app.
Uso: python design/previa_cupom.py  -> design/propostas/cupom_58mm.png"""
from PIL import Image, ImageDraw, ImageFont

COL = 32
CW = 15  # largura de um caractere em px
F = ImageFont.truetype('C:/Windows/Fonts/consola.ttf', 26)
FB = ImageFont.truetype('C:/Windows/Fonts/consolab.ttf', 26)
F2 = ImageFont.truetype('C:/Windows/Fonts/consolab.ttf', 52)

# (texto, estilo) estilo: n=normal b=negrito a=alto(negrito, altura dupla) g=grande(dupla) gc=grande centro c=centro bc=negrito centro r=invertido
L = []
def t(txt, e='n'): L.append((txt, e))
def linha(): t('-' * COL)
def valor(rot, v, e='n'): t(rot + v.rjust(COL - len(rot)), e)

t('HAMBURGUERIA RS', 'bc'); t('PEDIDO #2', 'gc'); t('08/11/2026 22:16', 'c'); linha()
t('ENTREGA', 'g')
t('Conjunto novo horizonte rua A,', 'a'); t('21', 'a')
t('Bairro: Conjunto Novo Horizonte', 'b')
t('Ref: Vizinho ao ponto do geladao')
t('Cliente: Ricardo', 'b'); t('Tel: (79) 99655-1968')
t('OBS: Casa cinza', 'b')
linha(); t('ITENS', 'g')
valor('1x Burguer cheddar', 'R$ 12,00', 'b'); t('  + Bacon (Adicionais)'); t('  OBS: sem cebola', 'b')
linha(); valor('Subtotal', 'R$ 12,00'); valor('Entrega', 'R$ 0,00'); valor('TOTAL', 'R$ 12,00', 'a')
linha(); t('PAGAMENTO: DINHEIRO', 'b'); valor('Cliente paga com', 'R$ 200,00'); t('LEVAR DE TROCO:', 'b'); t('R$ 188,00', 'gc')
linha(); t('Pedido #2', 'c')

alt = {'a': 56, 'g': 60, 'gc': 60}
h = sum(alt.get(e, 32) for _, e in L) + 120
img = Image.new('RGB', (COL * CW + 60, h), 'white')
d = ImageDraw.Draw(img)
y = 40
for txt, e in L:
    x = 30
    if e in ('g', 'gc'):
        w = len(txt) * CW * 2
        x = 30 + ((COL * CW - w) // 2 if e == 'gc' else 0)
        d.text((x, y), txt, font=F2, fill='black')
    elif e == 'r':
        d.rectangle([x, y - 2, x + len(txt) * CW, y + 30], fill='black')
        d.text((x, y), txt, font=FB, fill='white')
    elif e == 'a':
        tmp = Image.new('RGB', (COL * CW, 32), 'white')
        ImageDraw.Draw(tmp).text((0, 0), txt, font=FB, fill='black')
        img.paste(tmp.resize((COL * CW, 56)), (x, y))
    else:
        if e in ('c', 'bc'):
            x = 30 + (COL - len(txt)) * CW // 2
        d.text((x, y), txt, font=FB if e in ('b', 'bc') else F, fill='black')
    y += alt.get(e, 32)
img.save('design/propostas/cupom_58mm.png')
print('ok', img.size)

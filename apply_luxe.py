"""Apply the VERUS LUXE presentation layer to index.html.

Only presentation markup changes: hero block, one section heading, fonts, theme
colour and an appended style/script layer. All original <script> blocks are kept
byte-for-byte (verified by tests/storefront-luxe.test.js).
"""
import re, sys, pathlib

src = pathlib.Path(sys.argv[1]); dst = pathlib.Path(sys.argv[2])
css = pathlib.Path(__file__).with_name('luxe.css').read_text(encoding='utf8')
css_modals = pathlib.Path(__file__).with_name('luxe-modals.css').read_text(encoding='utf8')
js = pathlib.Path(__file__).with_name('luxe.js').read_text(encoding='utf8')
h = open(src, encoding='utf8', newline='').read()  # keep original CRLF bytes untouched
assert 'VERUS LUXE' not in h, 'already applied'

def sub1(old, new):
    global h
    assert h.count(old) == 1, ('expected exactly one match', old[:80])
    h = h.replace(old, new)

# 1) html class + theme colour
sub1('<html lang="vi">', '<html lang="vi" class="lux">')
sub1('<meta name="theme-color" content="#111111">', '<meta name="theme-color" content="#08080a">')

# 2) fonts (Vietnamese-capable serif display + full weight range for body)
sub1('<link href="https://fonts.googleapis.com/css2?family=Be+Vietnam+Pro:wght@600;800&display=swap" rel="stylesheet">',
     '<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>'
     '<link href="https://fonts.googleapis.com/css2?family=Be+Vietnam+Pro:wght@300;400;500;600;700;800'
     '&family=Cormorant+Garamond:ital,wght@0,500;0,600;1,500;1,600&family=Google+Sans:wght@500&display=swap" rel="stylesheet">')

# 3) hero — same copy, same actions/handlers; richer 3D stage
m = re.search(r'<section class="hero">.*?</section>', h, re.S)
assert m
old_hero = m.group(0)
for must in ["vCat('Áo')", "vCat('Quần')", "vCat('Giày')", "showCoupons()", "productArea"]:
    assert must in old_hero
new_hero = (
 '<section class="hero lx-hero" id="lxHero">'
 '<div class="lx-hero-bg" aria-hidden="true"><span class="lx-orb o1"></span><span class="lx-orb o2"></span><span class="lx-grid"></span><span class="lx-grain"></span></div>'
 '<div class="hero-copy"><div class="eyebrow">VERUS STORE · YOUR STYLE. YOUR RULES.</div>'
 '<h1><span class="lx-line"><span>Mặc đúng chất.</span></span><span class="lx-line"><span><em>Không cần giống ai.</em></span></span></h1>'
 '<p>Áo, áo khoác, quần, giày, dép, mũ, phụ kiện — tuyển từ nguồn riêng, giá rõ ràng và <b>miễn phí vận chuyển toàn quốc cho mọi đơn hàng</b>. Thông tin đơn của bạn thì VERUS luôn nói rõ.</p>'
 '<div class="heropills"><span>Miễn phí vận chuyển toàn quốc</span><span>Theo dõi đơn từng bước</span><span>Cọc minh bạch</span></div>'
 '<div class="hero-actions"><button onclick="document.getElementById(\'productArea\').scrollIntoView({behavior:\'smooth\'})">Khám phá sản phẩm</button><button class="outline" onclick="showCoupons()">Xem ưu đãi</button></div></div>'
 '<div class="hero3d" id="hero3d"><div class="h3d-stage">'
 '<div class="lx-shadow" aria-hidden="true"></div>'
 '<div class="lx-ring r1" aria-hidden="true"></div><div class="lx-ring r2" aria-hidden="true"></div>'
 '<div class="lx-mono" aria-hidden="true"><span class="lx-face f"><i>V</i><small>VERUS STORE</small></span><span class="lx-face b"></span><span class="lx-face l"></span><span class="lx-face r"></span><span class="lx-face t"></span><span class="lx-face bt"></span></div>'
 '<div class="lx-dust" aria-hidden="true"></div>'
 '<button class="h3d-card c1" data-l="Á" onclick="vCat(\'Áo\')" aria-label="Xem danh mục Áo"><b>ÁO</b><small>Thun · sơ mi · áo khoác</small></button>'
 '<button class="h3d-card c2" data-l="Q" onclick="vCat(\'Quần\')" aria-label="Xem danh mục Quần"><b>QUẦN</b><small>Jean · short · jogger</small></button>'
 '<button class="h3d-card c3" data-l="G" onclick="vCat(\'Giày\')" aria-label="Xem danh mục Giày"><b>GIÀY</b><small>Sneaker · dép · phụ kiện</small></button>'
 '</div></div>'
 '<div class="lx-scroll-cue" aria-hidden="true">Cuộn xuống</div>'
 '</section>')
h = h.replace(old_hero, new_hero, 1)

# 4) heading for the category tiles (factual copy, no claims)
sub1('<section class="cattiles" aria-label="Danh mục">',
     '<div class="lx-head"><div><div class="eyebrow">DANH MỤC</div><h2>Khám phá theo <em>danh mục</em></h2></div>'
     '<p>Chọn nhóm sản phẩm để xem nhanh các mẫu đang mở bán tại VERUS STORE.</p></div>'
     '<section class="cattiles" aria-label="Danh mục">')

# 5) append the presentation layer last so it wins the cascade
layer = ('\n<!-- VERUS LUXE START: presentation-only layer (dark luxury + 3D/parallax). Safe to remove as one block. -->\n'
         '<style id="verus-luxe">\n' + css + '\n</style>\n'
         '<style id="verus-luxe-modals">\n' + css_modals + '\n</style>\n'
         '<script id="verus-luxe-fx">\n' + js + '\n</script>\n'
         '<!-- VERUS LUXE END -->\n')
idx = h.rfind('</body>')
assert idx > 0
h = h[:idx] + layer + h[idx:]
open(dst, 'w', encoding='utf8', newline='').write(h)
print('ok', len(h))

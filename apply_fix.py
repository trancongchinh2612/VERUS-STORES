import re,sys
f=sys.argv[1]
s=open(f,encoding='utf-8').read()
css=open('layout-fix.css',encoding='utf-8').read()+open('product-modal-fix.css',encoding='utf-8').read()
js=open('product-modal-fix.js',encoding='utf-8').read()
blk=f'<style id="verus-product-modal-fix">\n{css}</style>\n<script id="verus-product-modal-fix-js">\n{js}</script>\n'
s=re.sub(r'<style id="verus-product-modal-fix">.*?</script>\n(?=</body>|$)','',s,flags=re.S) if 'verus-product-modal-fix' in s else s
i=s.rfind('</body>')
s=s[:i]+blk+s[i:]
open(f,'w',encoding='utf-8').write(s)
print('ok',len(s))

import asyncio, json, sys
from pathlib import Path
from playwright.async_api import async_playwright
OUT=Path(sys.argv[1] if len(sys.argv)>1 else "/tmp/browser/modals/shots"); OUT.mkdir(parents=True,exist_ok=True)
U="http://localhost:8099/index.html"
AUDIT="""() => {
 const lum=c=>{const m=c.match(/rgba?\\(([^)]+)\\)/);if(!m)return null;const p=m[1].split(',').map(parseFloat);if(p.length>3&&p[3]<0.35)return null;return (0.2126*p[0]+0.7152*p[1]+0.0722*p[2])/255};
 const roots=[...document.querySelectorAll('.modalbg.show,.modalbg.open,.modalbg[style*="flex"],.modalbg[style*="block"],#vChatBox,[role=dialog]')].filter(e=>e.offsetParent!==null||getComputedStyle(e).position==='fixed');
 const out={};
 for(const r of roots) for(const e of [r,...r.querySelectorAll('*')]){
   const cs=getComputedStyle(e); if(cs.display==='none'||cs.visibility==='hidden'||!e.getClientRects().length) continue;
   const k=e.tagName.toLowerCase()+(e.id?'#'+e.id:'')+(typeof e.className==='string'&&e.className?'.'+e.className.trim().split(/\\s+/).join('.'):'');
   const bg=lum(cs.backgroundColor); const hasText=[...e.childNodes].some(n=>n.nodeType===3&&n.textContent.trim());
   const fg=hasText?lum(cs.color):null;
   const bgi=cs.backgroundImage!=='none'&&!cs.backgroundImage.startsWith('url');
   if((bg!==null&&bg>0.55)||(fg!==null&&fg<0.4)) out[k]=(out[k]||'')+(bg>0.55?' LIGHTBG '+cs.backgroundColor:'')+(fg!==null&&fg<0.4?' DARKTXT '+cs.color:'');
 }
 return out;
}"""
async def main():
  async with async_playwright() as p:
    b=await p.chromium.launch(headless=True)
    c=await b.new_context(viewport={"width":390,"height":844},is_mobile=True,has_touch=True,device_scale_factor=2)
    pg=await c.new_page(); errs=[]
    pg.on("pageerror",lambda e: errs.append(str(e)))
    await pg.goto(U,wait_until="networkidle"); await pg.wait_for_timeout(2500)
    steps=[("cart","showCart()"),("wish","vWish()"),("auth","vAuth()"),("track","trackOrder()"),("coupons","showCoupons()"),("policy","showPolicy()"),("support","showSupport()"),("account","vAccount()")]
    report={}
    async def snap(name):
      await pg.wait_for_timeout(700)
      await pg.screenshot(path=str(OUT/f"{name}.png"))
      report[name]=await pg.evaluate(AUDIT)
    for name,js in steps:
      try: await pg.evaluate(js)
      except Exception as e: report[name]="ERR "+str(e)[:200]; continue
      await snap(name)
      await pg.evaluate("try{closeModal()}catch(e){}; try{window.verusCloseGoogleAccount&&window.verusCloseGoogleAccount()}catch(e){}")
      await pg.keyboard.press("Escape"); await pg.wait_for_timeout(300)
    # product + checkout
    await pg.evaluate("document.querySelector('#products .product .cover').click()")
    await snap("product")
    await pg.evaluate("document.getElementById('modalBody').scrollTop=600"); await snap("product2")
    try:
      await pg.evaluate("vSizeGuide()"); await snap("sizeguide")
    except Exception as e: report['sizeguide']='ERR'+str(e)[:100]
    await pg.evaluate("closeModal()")
    await pg.evaluate("document.querySelector('#products .product .cover').click()"); await pg.wait_for_timeout(800)
    # pick first size if any, then buy now
    await pg.evaluate("(()=>{const s=document.querySelector('#modalBody [onclick^=\"window.__size\"]');s&&s.click()})()")
    await pg.evaluate("window.__add()"); await pg.wait_for_timeout(600)
    await pg.evaluate("try{closeModal()}catch(e){}")
    await pg.evaluate("showCart()"); await snap("cart_full")
    # find checkout button inside cart
    btns=await pg.evaluate("[...document.querySelectorAll('#modalBody button')].map(b=>b.textContent.trim()+' | '+(b.getAttribute('onclick')||''))")
    report['cart_buttons']=btns
    await pg.evaluate("(()=>{const b=[...document.querySelectorAll('#modalBody button')].find(b=>/đặt hàng|thanh toán|checkout/i.test(b.textContent));b&&b.click()})()")
    await snap("checkout")
    await pg.evaluate("document.getElementById('modalBody').scrollTop=700"); await snap("checkout2")
    await pg.evaluate("document.getElementById('modalBody').scrollTop=1600"); await snap("checkout3")
    await pg.evaluate("try{closeModal()}catch(e){}")
    report['errors']=errs
    json.dump(report,open(OUT/"report.json","w"),ensure_ascii=False,indent=1)
    await b.close()
asyncio.run(main())

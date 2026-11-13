import asyncio, json, sys
from pathlib import Path
from playwright.async_api import async_playwright
OUT=Path(sys.argv[1]); OUT.mkdir(parents=True,exist_ok=True)
VP=sys.argv[2] if len(sys.argv)>2 else "m"
U="http://localhost:8099/index.html"
AUDIT=open('/tmp/browser/modals/audit_modals.py').read().split('AUDIT="""')[1].split('"""')[0]
async def main():
  async with async_playwright() as p:
    b=await p.chromium.launch(headless=True)
    if VP=="m": c=await b.new_context(viewport={"width":390,"height":844},is_mobile=True,has_touch=True,device_scale_factor=2)
    else: c=await b.new_context(viewport={"width":1280,"height":900})
    pg=await c.new_page(); errs=[]
    pg.on("pageerror",lambda e: errs.append(str(e)))
    await pg.goto(U,wait_until="networkidle"); await pg.wait_for_timeout(2500)
    rep={}
    async def snap(n,scroll=None):
      if scroll is not None: await pg.evaluate(f"document.querySelector('#modalbg .modal').scrollTop={scroll}")
      await pg.wait_for_timeout(700); await pg.screenshot(path=str(OUT/f"{n}.png")); rep[n]=await pg.evaluate(AUDIT.replace('\\\\','\\'))
    # product first (desktop view)
    await pg.evaluate("document.querySelector('#products .product .cover').click()"); await snap("product")
    await pg.evaluate("(()=>{const s=document.querySelector('#modalBody [onclick^=\"window.__size\"]');s&&s.click()})()")
    await pg.evaluate("window.__add()"); await pg.wait_for_timeout(500); await pg.evaluate("closeModal()")
    # checkout form rendering only (no submit)
    await pg.evaluate("_checkoutInner()"); await snap("checkout1")
    await snap("checkout2",700); await snap("checkout3",1500)
    await pg.evaluate("closeModal()")
    # payment card rendering only
    await pg.evaluate("modal('Thanh toán đơn hàng', verusPaymentPanel('VSQA0001',100000,'VSQA0001','Thanh toán tiền cọc'))"); await snap("pay1"); await snap("pay2",600)
    await pg.evaluate("closeModal()")
    # customer dashboard with sample in-browser data (not saved anywhere)
    await pg.evaluate("""window.__customerData={online:true,email:'khach.mau@example.com',profile:{full_name:'Khách Mẫu',phone:'0900000000'},orders:[],wishIds:[],vip:{points:0,tier:'Member'}};window.vCustomerTab('overview')""")
    await snap("acct_overview"); await snap("acct_overview2",700)
    for t in ['orders','wishlist','profile','rewards','chat']:
      try: await pg.evaluate(f"window.vCustomerTab('{t}')"); await snap("acct_"+t)
      except Exception as e: rep["acct_"+t]="ERR "+str(e)[:200]
    await pg.evaluate("closeModal()")
    # chat look
    await pg.evaluate("""modal('Hội thoại','<div id="vChatBox" style="max-height:45vh;overflow:auto;display:flex;flex-direction:column;gap:8px"><div class="vmsg customer"><b class="tiny">Bạn</b><div>Mẫu tin nhắn</div><small>09/11</small></div><div class="vmsg staff"><b class="tiny">Shop</b><div>Mẫu trả lời</div><small>09/11</small></div></div><div class="field"><textarea id="cReply" rows="2" placeholder="Nhập tin nhắn…"></textarea></div><button class="orange" style="width:100%">Gửi</button>')""")
    await pg.evaluate("toast('Đã sao chép nội dung chuyển khoản')"); await snap("chat_toast")
    await pg.evaluate("closeModal()")
    rep['errors']=errs
    json.dump(rep,open(OUT/"report.json","w"),ensure_ascii=False,indent=1)
    await b.close()
asyncio.run(main())

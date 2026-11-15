import asyncio
from playwright.async_api import async_playwright
import os; os.makedirs("luxe-shots", exist_ok=True)
import sys
U=sys.argv[1] if len(sys.argv)>1 else "http://localhost:8080/index.html"
async def main():
    async with async_playwright() as p:
        b=await p.chromium.launch(headless=True)
        # desktop flow
        c=await b.new_context(viewport={"width":1280,"height":1800})
        pg=await c.new_page(); errs=[]
        pg.on("pageerror",lambda e: errs.append("PAGEERR "+str(e)))
        pg.on("response",lambda r: errs.append(f"HTTP {r.status} {r.url}") if r.status>=400 else None)
        await pg.goto(U,wait_until="networkidle"); await pg.wait_for_timeout(2000)
        # hover tilt on hero
        await pg.mouse.move(900,500); await pg.wait_for_timeout(600)
        await pg.locator('.lx-hero').screenshot(path="luxe-shots/f_hero.png")
        ry=await pg.evaluate("getComputedStyle(document.querySelector('.h3d-stage')).getPropertyValue('--ry')")
        print("stage --ry after hover:",ry)
        # scroll through slowly to trigger reveals
        for y in range(0,6000,400):
            await pg.evaluate(f"scrollTo(0,{y})"); await pg.wait_for_timeout(120)
        await pg.wait_for_timeout(1500)
        hidden=await pg.evaluate("[...document.querySelectorAll('.lx-rv:not(.lx-in)')].map(e=>e.className).slice(0,5)")
        print("unrevealed:",hidden)
        # category card click filters products
        await pg.evaluate("scrollTo({top:0,behavior:'instant'})"); await pg.wait_for_timeout(900)
        el=pg.locator('.h3d-card.c2'); bb=await el.bounding_box(); top=await pg.evaluate(f"document.elementFromPoint({bb['x']+bb['width']/2},{bb['y']+bb['height']/2}).closest('.h3d-card')?.className"); print('element at card center:',top); await el.click(force=True); await pg.wait_for_timeout(800)
        print("after QUẦN click active category:", await pg.evaluate("[...document.querySelectorAll('.categorybar button.active')].map(b=>b.textContent)"), await pg.evaluate("document.getElementById('productCount').textContent"))
        await pg.locator('.categorybar button',has_text="Tất cả").first.click(); await pg.wait_for_timeout(400)
        # open product modal
        await pg.locator('#products .product .cover').first.click(); await pg.wait_for_timeout(1200)
        await pg.screenshot(path="luxe-shots/f_modal.png")
        print("modal title:", await pg.locator('#modalTitle').text_content())
        await pg.keyboard.press("Escape"); await pg.wait_for_timeout(400)
        await pg.evaluate("closeModal&&closeModal()")
        # cart
        await pg.locator('.head-cart').click(); await pg.wait_for_timeout(800)
        await pg.screenshot(path="luxe-shots/f_cart.png")
        await pg.evaluate("closeModal()")
        print("errors:",errs)
        await c.close()
        # mobile hero + reduced motion
        c=await b.new_context(viewport={"width":390,"height":844},has_touch=True,is_mobile=True,reduced_motion="no-preference")
        pg=await c.new_page(); await pg.goto(U,wait_until="networkidle"); await pg.wait_for_timeout(1500)
        await pg.evaluate("scrollTo(0,560)"); await pg.wait_for_timeout(800)
        await pg.screenshot(path="luxe-shots/f_mob_stage.png")
        ov=await pg.evaluate("document.documentElement.scrollWidth>innerWidth")
        print("mobile horizontal overflow:",ov)
        await c.close()
        c=await b.new_context(viewport={"width":1280,"height":1800},reduced_motion="reduce")
        pg=await c.new_page(); await pg.goto(U,wait_until="networkidle"); await pg.wait_for_timeout(800)
        op=await pg.evaluate("[...document.querySelectorAll('.lx-rv')].map(e=>getComputedStyle(e).opacity).filter(o=>o!=='1').length")
        print("reduced-motion hidden elements:",op)
        await c.close(); await b.close()
asyncio.run(main())

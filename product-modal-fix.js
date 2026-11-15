/* VERUS PRODUCT MODAL FIX v1 — gắn class product-modal + dựng thanh MUA ghim đáy */
(function(){
  const bg=document.getElementById('modalbg'),body=document.getElementById('modalBody');
  if(!bg||!body)return;
  const box=bg.querySelector('.modal');if(!box)return;
  function clean(){if(box.classList.contains('product-modal'))box.classList.remove('product-modal');if(bg.classList.contains('pm-open'))bg.classList.remove('pm-open');const o=box.querySelector('#pmBar');if(o)o.remove()}
  function sync(){
    const src=body.querySelector('.detailgrid .buybar');
    if(!src){clean();return}
    if(!box.classList.contains('product-modal'))box.classList.add('product-modal');if(!bg.classList.contains('pm-open'))bg.classList.add('pm-open');
    let bar=box.querySelector('#pmBar');
    if(!bar){
      bar=document.createElement('div');bar.id='pmBar';
      bar.innerHTML='<button type="button" class="pm-cart">Thêm vào giỏ</button><button type="button" class="pm-buy">MUA NGAY</button>';
      box.appendChild(bar);
      bar.querySelector('.pm-cart').addEventListener('click',()=>{if(typeof window.__add==='function')window.__add()});
      bar.querySelector('.pm-buy').addEventListener('click',()=>{if(typeof window.__add==='function')window.__add(true)});
    }
    const c=src.querySelector('.btn-cart'),b=src.querySelector('.btn-buy');
    bar.querySelector('.pm-cart').disabled=!!(c&&c.disabled);
    bar.querySelector('.pm-buy').disabled=!!(b&&b.disabled);
  }
  new MutationObserver(sync).observe(body,{childList:true});
  new MutationObserver(()=>{if(!bg.classList.contains('show'))clean()}).observe(bg,{attributes:true,attributeFilter:['class']});
  sync();
})();

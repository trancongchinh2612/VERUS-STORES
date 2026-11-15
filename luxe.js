/* VERUS LUXE FX — presentation-only motion layer (no data, cart, checkout or network access). */
(function(){
  var root=document.documentElement;
  if(!root.classList.contains('lux'))return;
  var reduce=window.matchMedia&&matchMedia('(prefers-reduced-motion: reduce)').matches;
  var finePointer=window.matchMedia&&matchMedia('(hover:hover) and (pointer:fine)').matches;
  root.classList.add('lux-js');

  /* Headline entrance */
  requestAnimationFrame(function(){requestAnimationFrame(function(){root.classList.add('lx-ready')})});

  /* Gold dust inside the 3D stage (decorative) */
  var dust=document.querySelector('.lx-dust');
  if(dust&&!reduce){
    var n=window.innerWidth<700?10:18;
    for(var i=0;i<n;i++){
      var d=document.createElement('i');
      d.style.left=(8+Math.random()*84)+'%';d.style.top=(10+Math.random()*80)+'%';
      d.style.setProperty('--d',(7+Math.random()*8).toFixed(1)+'s');
      d.style.setProperty('--dl',(-Math.random()*10).toFixed(1)+'s');
      d.style.setProperty('--tx',(Math.random()*40-20).toFixed(0)+'px');
      d.style.setProperty('--ty',(-20-Math.random()*50).toFixed(0)+'px');
      d.style.transform='translateZ('+(Math.random()*220-60).toFixed(0)+'px)';
      dust.appendChild(d);
    }
  }

  /* Scroll: progress bar, header state, hero parallax */
  var bar=document.createElement('div');bar.className='lx-progress';bar.setAttribute('aria-hidden','true');document.body.appendChild(bar);
  var hero=document.querySelector('.lx-hero'),ticking=false;
  function onScroll(){
    ticking=false;
    var y=window.scrollY||0,max=Math.max(1,document.documentElement.scrollHeight-innerHeight);
    bar.style.setProperty('--lx-sp',Math.min(1,y/max).toFixed(4));
    root.classList.toggle('lx-scrolled',y>24);
    if(hero&&!reduce){
      var h=hero.offsetHeight||1,p=Math.max(0,Math.min(1,(y-hero.offsetTop+80)/h));
      hero.style.setProperty('--lx-p',p.toFixed(4));
    }
  }
  addEventListener('scroll',function(){if(!ticking){ticking=true;requestAnimationFrame(onScroll)}},{passive:true});
  addEventListener('resize',onScroll,{passive:true});onScroll();

  /* Touch devices: gentle auto-orbit of the 3D stage (desktop uses pointer tilt from the existing script) */
  var stage=document.querySelector('.lx-hero .h3d-stage');
  if(stage&&!reduce&&!finePointer){
    var t0=performance.now(),visible=true;
    if('IntersectionObserver' in window){new IntersectionObserver(function(e){visible=e[0].isIntersecting}).observe(stage)}
    (function loop(t){
      if(visible){var s=(t-t0)/1000;stage.style.setProperty('--ry',(-14+Math.sin(s*.5)*16).toFixed(2)+'deg');stage.style.setProperty('--rx',(8+Math.cos(s*.4)*4).toFixed(2)+'deg')}
      requestAnimationFrame(loop);
    })(t0);
  }

  /* Reveal-on-scroll for static storefront sections */
  var groups=['.servicegrid .servicecard','.cattiles button','.lx-head','#productArea','.shopstatement','.vstory .vcard','.faq h2','.faq details','.vsteps .eyebrow','.vstep','.vform','.brandstory','.store .footer','.vfoot-grid>div'];
  var targets=[];
  groups.forEach(function(sel){
    document.querySelectorAll(sel).forEach(function(el,i){
      if(el.closest('.admin')||el.closest('.modal'))return;
      el.classList.add('lx-rv');el.style.setProperty('--lx-d',Math.min(i,7)*0.07+'s');targets.push(el);
    });
  });
  function show(el){el.classList.add('lx-in');setTimeout(function(){el.classList.add('lx-done')},1300)}
  if(reduce||!('IntersectionObserver' in window)){targets.forEach(show)}
  else{
    var io=new IntersectionObserver(function(es){es.forEach(function(e){if(e.isIntersecting){show(e.target);io.unobserve(e.target)}})},{rootMargin:'0px 0px -8% 0px',threshold:.08});
    targets.forEach(function(el){io.observe(el)});
    /* Safety net: never leave content hidden (e.g. deep links, print, slow observers). */
    setTimeout(function(){targets.forEach(function(el){var r=el.getBoundingClientRect();if(r.top<innerHeight&&!el.classList.contains('lx-in'))show(el)})},2500);
    addEventListener('beforeprint',function(){targets.forEach(show)});
  }

  /* 3D tilt for editorial cards (mouse only; product cards already tilt via the existing script) */
  if(finePointer&&!reduce){
    var tiltSel='.servicecard,.vcard,.vstep,.cattiles button';
    var cur=null;
    document.addEventListener('pointermove',function(e){
      if(e.pointerType!=='mouse')return;
      var c=e.target.closest&&e.target.closest(tiltSel);
      if(cur&&cur!==c){cur.style.transform='';cur=null}
      if(!c||!c.classList.contains('lx-done')&&c.classList.contains('lx-rv'))return;
      cur=c;var r=c.getBoundingClientRect(),x=(e.clientX-r.left)/r.width-.5,y=(e.clientY-r.top)/r.height-.5;
      c.style.transform='perspective(800px) rotateX('+(-y*9).toFixed(2)+'deg) rotateY('+(x*11).toFixed(2)+'deg) translateZ(6px)';
    },{passive:true});
    document.addEventListener('pointerleave',function(){if(cur){cur.style.transform='';cur=null}},true);
  }
})();

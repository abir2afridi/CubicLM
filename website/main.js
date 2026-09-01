(function(){
'use strict';

/* ── Grain ── */
(function(){
  var c=document.getElementById('grain');if(!c)return;
  var ctx=c.getContext('2d'),w,h;
  var rs=function(){w=c.width=window.innerWidth;h=c.height=window.innerHeight};
  rs();window.addEventListener('resize',rs);
  var f=0;
  (function lp(){f++;if(f%3===0){var img=ctx.createImageData(w,h);var d=img.data;for(var i=0;i<d.length;i+=4){var v=Math.random()*255;d[i]=d[i+1]=d[i+2]=v;d[i+3]=255}ctx.putImageData(img,0,0)}requestAnimationFrame(lp)})();
})();

/* ── Scroll-linked hero zoom ── */
(function(){
  var heading=document.getElementById('hero-heading');
  var bg=document.getElementById('hero-bg');
  if(!heading||!bg)return;
  var ticking=false;
  window.addEventListener('scroll',function(){
    if(!ticking){ticking=true;requestAnimationFrame(function(){
      var scrollY=window.scrollY;
      var vh=window.innerHeight;
      var progress=Math.min(1,scrollY/(vh*.3));
      heading.style.transform='scale('+(1-progress*.11)+')';
      bg.style.transform='scale('+(1+progress*.27)+')';
      ticking=false;
    })}
  },{passive:true});
})();

/* ── GlassSurface for nav-pill ── */
(function(){
  var container=document.getElementById('nav-glass');
  if(!container)return;
  var filterId='nav-glass-filter';
  var feMap=document.getElementById('nav-glass-map');
  function genMap(){
    var rect=container.getBoundingClientRect();
    var w=rect.width||400,h=rect.height||60;
    var bw=h*.035;
    var svg='<svg viewBox="0 0 '+w+' '+h+'" xmlns="http://www.w3.org/2000/svg">'
      +'<defs>'
      +'<linearGradient id="ng-rg" x1="100%" y1="0%" x2="0%" y2="0%">'
      +'<stop offset="0%" stop-color="#0000"/><stop offset="100%" stop-color="red"/></linearGradient>'
      +'<linearGradient id="ng-bg" x1="0%" y1="0%" x2="0%" y2="100%">'
      +'<stop offset="0%" stop-color="#0000"/><stop offset="100%" stop-color="blue"/></linearGradient>'
      +'</defs>'
      +'<rect width="'+w+'" height="'+h+'" fill="black"/>'
      +'<rect width="'+w+'" height="'+h+'" rx="'+h/2+'" fill="url(#ng-rg)"/>'
      +'<rect width="'+w+'" height="'+h+'" rx="'+h/2+'" fill="url(#ng-bg)" style="mix-blend-mode:difference"/>'
      +'<rect x="'+bw+'" y="'+bw+'" width="'+(w-bw*2)+'" height="'+(h-bw*2)+'" rx="'+h/2+'" fill="hsl(0 0% 50% / 0.93)" style="filter:blur(11px)"/>'
      +'</svg>';
    return 'data:image/svg+xml,'+encodeURIComponent(svg);
  }
  function update(){if(feMap)feMap.setAttribute('href',genMap());}
  var isSafari=/Safari/.test(navigator.userAgent)&&!/Chrome/.test(navigator.userAgent);
  var isFirefox=/Firefox/.test(navigator.userAgent);
  var testDiv=document.createElement('div');
  testDiv.style.backdropFilter='url(#'+filterId+')';
  var svgOk=testDiv.style.backdropFilter!=='';
  if(!isSafari&&!isFirefox&&svgOk){
    container.classList.add('glass-surface--svg');
    container.style.setProperty('--filter-id','url(#'+filterId+')');
    container.style.setProperty('--glass-frost','0');
    container.style.setProperty('--glass-saturation','1');
  }else{
    container.classList.add('glass-surface--fallback');
  }
  update();
  var ro=new ResizeObserver(function(){setTimeout(update,0);});
  ro.observe(container);
  window.addEventListener('resize',function(){setTimeout(update,0);});
})();

/* ── Changelog tabs ── */
(function(){
  var tabs=document.querySelectorAll('.changelog-tab');
  if(!tabs.length)return;
  function showVersion(version){
    document.querySelectorAll('.changelog-detail').forEach(function(el){
      el.style.display='none';
    });
    var target=document.getElementById('changelog-'+version);
    if(target)target.style.display='block';
    tabs.forEach(function(tab){
      tab.classList.toggle('active',tab.dataset.version===version);
    });
  }
  tabs.forEach(function(tab){
    tab.addEventListener('click',function(){
      showVersion(this.dataset.version);
    });
  });
  var active=document.querySelector('.changelog-tab.active');
  if(active)showVersion(active.dataset.version);
})();

})();

// ── Cloud marquee: clone each track's set once for a seamless infinite loop ──
(function(){
  if (window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;
  document.querySelectorAll('.cloud-marquee-track').forEach(function(track){
    var set = track.querySelector('.cloud-marquee-set');
    if (!set || track.querySelector('.cloud-marquee-set + .cloud-marquee-set')) return;
    var clone = set.cloneNode(true);
    clone.setAttribute('aria-hidden', 'true');
    track.appendChild(clone);
  });
})();

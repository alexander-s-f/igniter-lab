/* Igniter-Lang — mark engine (vanilla, no deps)
   Scans elements with [data-ig-mark] and injects the asterisk spark SVG.
   Attributes:
     data-ig-mark              presence enables it
     data-variant="original"   (default) | "oval"   oval = derivative for sub-products
     data-ground="ink"         (default) | "amber" | "paper"
     data-glow="1"|"0"         (default 1 on ink, 0 elsewhere)
   The element must be an <svg viewBox="0 0 100 100">. */
(function () {
  var IGNITE = '#ff6a3d',
      AMBER_INK = '#1a1109',
      WHITE = '#fff2e4',
      PAPER_INK = '#2a2018';

  // shared gradient defs — injected once
  if (!document.getElementById('ig-mark-defs')) {
    var defs = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    defs.setAttribute('width', '0');
    defs.setAttribute('height', '0');
    defs.setAttribute('id', 'ig-mark-defs');
    defs.setAttribute('aria-hidden', 'true');
    defs.style.position = 'absolute';
    defs.innerHTML =
      '<defs>' +
      '<radialGradient id="ig-spark" cx="50%" cy="44%" r="62%">' +
        '<stop offset="0" stop-color="#ffe6cc"/>' +
        '<stop offset="0.42" stop-color="#ff8a4d"/>' +
        '<stop offset="1" stop-color="#ff5a2c"/>' +
      '</radialGradient>' +
      '<radialGradient id="ig-glow">' +
        '<stop offset="0" stop-color="#ff8c50" stop-opacity="0.5"/>' +
        '<stop offset="0.6" stop-color="#ff8c50" stop-opacity="0.12"/>' +
        '<stop offset="1" stop-color="#ff8c50" stop-opacity="0"/>' +
      '</radialGradient>' +
      '</defs>';
    document.body.insertBefore(defs, document.body.firstChild);
  }

  function r2(n) { return Math.round(n * 100) / 100; }
  function poly(cx, cy, r, deg) {
    var a = deg * Math.PI / 180;
    return [r2(cx + r * Math.cos(a)), r2(cy + r * Math.sin(a))];
  }

  function spokes(stroke) {
    var s = '';
    for (var k = 0; k < 6; k++) {
      var t = poly(50, 50, 38, -90 + k * 60);
      s += '<line x1="50" y1="50" x2="' + t[0] + '" y2="' + t[1] +
           '" stroke="' + stroke + '" stroke-width="10" stroke-linecap="round"/>';
    }
    return s;
  }

  function build(variant, ground, glow) {
    var arm   = ground === 'amber' ? AMBER_INK : IGNITE;
    var pearl = ground === 'paper' ? PAPER_INK : WHITE;
    var s = '';
    if (glow) s += '<circle cx="50" cy="50" r="34" fill="url(#ig-glow)"/>';
    s += spokes(arm);
    // hot core: gradient on ink ground, solid arm-color otherwise
    s += ground === 'ink'
      ? '<circle cx="50" cy="50" r="9" fill="url(#ig-spark)"/>'
      : '<circle cx="50" cy="50" r="9" fill="' + arm + '"/>';
    s += '<circle cx="50" cy="50" r="3.8" fill="' + pearl + '"/>';
    if (variant === 'oval') {
      s += '<ellipse cx="50" cy="31" rx="3" ry="6.5" fill="' + pearl + '"/>';
    }
    return s;
  }

  function render(el) {
    var variant = el.getAttribute('data-variant') || 'original';
    var ground  = el.getAttribute('data-ground') || 'ink';
    var glowAttr = el.getAttribute('data-glow');
    var glow = glowAttr != null ? glowAttr === '1' : ground === 'ink';
    if (!el.getAttribute('viewBox')) el.setAttribute('viewBox', '0 0 100 100');
    el.style.overflow = 'visible';
    el.innerHTML = build(variant, ground, glow);
  }

  function renderAll(root) {
    (root || document).querySelectorAll('[data-ig-mark]').forEach(render);
  }

  window.IgMark = { render: render, renderAll: renderAll };
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', function () { renderAll(); });
  } else {
    renderAll();
  }
})();

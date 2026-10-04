// Tasto Back del telecomando = pagina precedente.
// config/ir-keymap.toml manda il Back come F9 (XF86Back viene scartato da labwc
// sul Pi, F9 invece arriva alla pagina come le frecce). Qui lo intercettiamo e
// facciamo history.back(), che funziona anche sulle SPA.
document.addEventListener('keydown', (e) => {
  if (e.key === 'F9' || e.key === 'BrowserBack') {
    e.preventDefault();
    e.stopPropagation();
    history.back();
  }
}, true);

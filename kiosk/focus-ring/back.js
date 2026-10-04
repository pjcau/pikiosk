// Tasto Back del telecomando (KEY_BACK → XF86Back → "BrowserBack") = pagina
// precedente. Su Linux/Wayland Chromium non lo gestisce da solo, quindi lo
// intercettiamo qui e facciamo history.back() (funziona anche sulle SPA).
document.addEventListener('keydown', (e) => {
  if (e.key === 'BrowserBack' || e.code === 'BrowserBack' || e.keyCode === 166) {
    e.preventDefault();
    e.stopPropagation();
    history.back();
  }
}, true);

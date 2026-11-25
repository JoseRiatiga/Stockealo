// Stockealo · modo claro u oscuro del sitio (portada, instalar y páginas legales).
// Decisión del dueño (25 nov): siempre claro al abrir, aunque el equipo esté en oscuro.
// Solo cambia a oscuro si la persona toca el botón, y se recuerda en este navegador
// (localStorage, sin cookies). Va en el <head> para que no parpadee al cargar.
(function () {
  var KEY = 'stockealo-site-theme';
  var root = document.documentElement;
  function read() {
    try { return localStorage.getItem(KEY) === 'dark' ? 'dark' : 'light'; } catch (e) { return 'light'; }
  }
  function apply(theme) {
    root.setAttribute('data-theme', theme);
    var buttons = document.querySelectorAll('[data-theme-toggle]');
    for (var i = 0; i < buttons.length; i++) {
      var dark = theme === 'dark';
      buttons[i].setAttribute('aria-pressed', String(dark));
      buttons[i].setAttribute('aria-label', dark ? 'Cambiar a modo claro' : 'Cambiar a modo oscuro');
      buttons[i].title = dark ? 'Modo claro' : 'Modo oscuro';
    }
  }
  apply(read());
  document.addEventListener('DOMContentLoaded', function () {
    apply(read());
    document.addEventListener('click', function (e) {
      var b = e.target.closest && e.target.closest('[data-theme-toggle]');
      if (!b) return;
      var next = read() === 'dark' ? 'light' : 'dark';
      try { localStorage.setItem(KEY, next); } catch (err) {}
      apply(next);
    });
  });
})();

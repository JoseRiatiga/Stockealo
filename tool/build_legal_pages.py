"""Genera stockealo.online/terminos y /privacidad desde los textos legales de la app.

La única fuente es lib/features/legal/presentation/screens/legal_document_screen.dart:
si cambian los Términos o la Política en la app, la web se actualiza al publicar.

Uso:  python tool/build_legal_pages.py [carpeta_de_salida]   (por defecto: web_site)
"""

import html
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "lib/features/legal/presentation/screens/legal_document_screen.dart"

# Literal de Dart entre comillas simples, con escapes
_LITERAL = re.compile(r"'((?:[^'\\]|\\.)*)'")


def _dart_string(code: str) -> str:
    """Une los literales adyacentes de Dart ('a' 'b') y resuelve sus escapes."""
    parts = []
    for raw in _LITERAL.findall(code):
        parts.append(re.sub(r"\\(.)", lambda m: {"n": "\n", "t": "\t"}.get(m.group(1), m.group(1)), raw))
    return "".join(parts)


def _block(text: str, start: str, end: str | None) -> str:
    i = text.index(start)
    j = text.index(end, i) if end else len(text)
    return text[i:j]


def _field(code: str, name: str) -> str:
    """Valor de un argumento con nombre hecho de literales de texto: name: 'a' 'b'"""
    m = re.search(name + r":\s*((?:'(?:[^'\\]|\\.)*'\s*)+)", code)
    if not m:
        raise SystemExit(f"No se encontró {name} en: {code[:80]}")
    return _dart_string(m.group(1))


def parse(text: str, view: str, next_view: str | None) -> dict:
    block = _block(text, f"class {view}", f"class {next_view}" if next_view else "Widget _buildHeader(")
    header = block[block.index("_buildHeader("):block.index("_buildSection(")]
    sections = []
    for part in block.split("_buildSection(")[1:]:
        sections.append({
            "number": _field(part, "number"),
            "title": _field(part, "title"),
            "content": _field(part, "content"),
        })
    return {"title": _field(header, "title"), "subtitle": _field(header, "subtitle"), "sections": sections}


def _content_html(content: str) -> str:
    """Párrafos separados por línea en blanco; las líneas con • se vuelven lista."""
    out = []
    for para in content.split("\n\n"):
        lines = [l for l in para.split("\n") if l.strip()]
        bullets = [l for l in lines if l.lstrip().startswith("•")]
        if bullets and len(bullets) == len(lines):
            items = "".join(f"<li>{html.escape(l.lstrip()[1:].strip())}</li>" for l in lines)
            out.append(f"<ul>{items}</ul>")
        else:
            out.extend(f"<p>{html.escape(l)}</p>" for l in lines)
    return "\n".join(out)


PAGE = """<!doctype html>
<html lang="es">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{page_title} · Stockealo</title>
  <meta name="description" content="{page_title} de Stockealo, la app de inventario y ventas para negocios pequeños.">
  <link rel="icon" href="/favicon.png">
  <link rel="stylesheet" href="/site.css">
</head>
<body>
  <header class="topbar">
    <div class="wrap topbar-in">
      <a class="brand" href="/"><img src="/logo.png" alt="" width="32" height="32"> Stockealo</a>
      <nav class="legal-nav">
        <a href="/terminos/"{terms_current}>Términos</a>
        <a href="/privacidad/"{privacy_current}>Privacidad</a>
      </nav>
    </div>
  </header>
  <main class="wrap doc">
    <h1>{title}</h1>
    <p class="muted">{subtitle}</p>
    {sections}
  </main>
  <footer class="footer">
    <div class="wrap">
      <a href="/">Inicio</a> · <a href="/terminos/">Términos y condiciones</a> · <a href="/privacidad/">Política de privacidad</a>
      <p class="muted">Este texto es el mismo que aparece en la app (Ajustes › Términos y privacidad).</p>
    </div>
  </footer>
</body>
</html>
"""


def render(doc: dict, page_title: str, current: str) -> str:
    sections = "\n".join(
        f'<section class="doc-section"><h2><span class="num">{html.escape(s["number"])}</span>'
        f'{html.escape(s["title"])}</h2>\n{_content_html(s["content"])}</section>'
        for s in doc["sections"]
    )
    return PAGE.format(
        page_title=page_title,
        title=html.escape(doc["title"]),
        subtitle=html.escape(doc["subtitle"]),
        sections=sections,
        terms_current=' aria-current="page"' if current == "terms" else "",
        privacy_current=' aria-current="page"' if current == "privacy" else "",
    )


def main() -> None:
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "web_site"
    text = SOURCE.read_text(encoding="utf-8")
    terms = parse(text, "_TermsOfServiceView", "_PrivacyPolicyView")
    privacy = parse(text, "_PrivacyPolicyView", None)
    if not terms["sections"] or not privacy["sections"]:
        raise SystemExit("No se encontraron secciones legales: revisa legal_document_screen.dart")
    for folder, doc, name, current in [
        ("terminos", terms, "Términos y condiciones", "terms"),
        ("privacidad", privacy, "Política de privacidad", "privacy"),
    ]:
        target = out / folder / "index.html"
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(render(doc, name, current), encoding="utf-8")
        print(f"{target}: {len(doc['sections'])} secciones")


if __name__ == "__main__":
    main()

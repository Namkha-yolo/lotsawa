#!/usr/bin/env python3
"""Generate a formal presentation-quality PDF from the Lotsawa Keyboard documentation."""

import markdown
from weasyprint import HTML
import os

INPUT_MD = os.path.join(os.path.dirname(__file__), "LOTSAWA_KEYBOARD_PLAN.md")
OUTPUT_PDF = os.path.join(os.path.dirname(__file__), "LOTSAWA_KEYBOARD_PLAN.pdf")

CSS = """
@import url('https://fonts.googleapis.com/css2?family=Noto+Serif+Tibetan:wght@400;700&family=Inter:wght@300;400;500;600;700&family=JetBrains+Mono:wght@400;500&display=swap');

@page {
    size: A4;
    margin: 2.2cm 2cm 2.5cm 2cm;
    @top-center {
        content: "Lotsawa Keyboard";
        font-family: 'Inter', sans-serif;
        font-size: 8pt;
        color: #999;
        padding-top: 0.5cm;
    }
    @bottom-center {
        content: counter(page);
        font-family: 'Inter', sans-serif;
        font-size: 8pt;
        color: #999;
    }
}

@page :first {
    @top-center { content: none; }
    @bottom-center { content: none; }
}

* {
    box-sizing: border-box;
}

body {
    font-family: 'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial, sans-serif;
    font-size: 10pt;
    line-height: 1.65;
    color: #1a1a1a;
    -webkit-font-smoothing: antialiased;
}

/* ── Title ── */
h1 {
    font-size: 26pt;
    font-weight: 700;
    color: #0f172a;
    margin-top: 3cm;
    margin-bottom: 0.3cm;
    padding-bottom: 0.4cm;
    border-bottom: 3px solid #1e3a5f;
    page-break-before: avoid;
    line-height: 1.3;
}

h1:first-of-type {
    text-align: center;
    border-bottom: none;
    margin-top: 4cm;
    margin-bottom: 0.1cm;
    font-size: 30pt;
}

/* Section headers */
h2 {
    font-size: 16pt;
    font-weight: 700;
    color: #1e3a5f;
    margin-top: 1.5cm;
    margin-bottom: 0.4cm;
    padding-bottom: 0.2cm;
    border-bottom: 1.5px solid #cbd5e1;
    page-break-after: avoid;
}

h3 {
    font-size: 12pt;
    font-weight: 600;
    color: #334155;
    margin-top: 0.8cm;
    margin-bottom: 0.3cm;
    page-break-after: avoid;
}

h4 {
    font-size: 10.5pt;
    font-weight: 600;
    color: #475569;
    margin-top: 0.5cm;
    margin-bottom: 0.2cm;
    page-break-after: avoid;
}

/* ── Body text ── */
p {
    margin-bottom: 0.4cm;
    text-align: justify;
    orphans: 3;
    widows: 3;
}

strong {
    font-weight: 600;
    color: #0f172a;
}

em {
    font-style: italic;
    color: #475569;
}

/* ── Blockquotes (dedication) ── */
blockquote {
    margin: 0.6cm 0;
    padding: 0.6cm 0.8cm;
    background: linear-gradient(135deg, #f8fafc 0%, #f1f5f9 100%);
    border-left: 4px solid #1e3a5f;
    border-radius: 0 6px 6px 0;
    font-style: italic;
    color: #334155;
    page-break-inside: avoid;
}

blockquote p {
    text-align: left;
    margin-bottom: 0.2cm;
}

blockquote p:last-child {
    margin-bottom: 0;
}

/* ── Horizontal rules ── */
hr {
    border: none;
    border-top: 1px solid #e2e8f0;
    margin: 0.8cm 0;
}

/* ── Lists ── */
ul, ol {
    margin-bottom: 0.4cm;
    padding-left: 0.6cm;
}

li {
    margin-bottom: 0.15cm;
    line-height: 1.55;
}

li strong {
    color: #1e3a5f;
}

/* ── Tables ── */
table {
    width: 100%;
    border-collapse: collapse;
    margin: 0.4cm 0 0.6cm 0;
    font-size: 9pt;
    page-break-inside: auto;
}

thead {
    display: table-header-group;
}

tr {
    page-break-inside: avoid;
}

th {
    background: #1e3a5f;
    color: white;
    font-weight: 600;
    text-align: left;
    padding: 0.25cm 0.35cm;
    font-size: 8.5pt;
    text-transform: uppercase;
    letter-spacing: 0.3pt;
}

td {
    padding: 0.2cm 0.35cm;
    border-bottom: 1px solid #e2e8f0;
    vertical-align: top;
}

tr:nth-child(even) td {
    background: #f8fafc;
}

tr:hover td {
    background: #f1f5f9;
}

/* ── Code ── */
code {
    font-family: 'JetBrains Mono', 'SF Mono', 'Fira Code', monospace;
    font-size: 8.5pt;
    background: #f1f5f9;
    padding: 0.05cm 0.15cm;
    border-radius: 3px;
    color: #be185d;
}

pre {
    background: #0f172a;
    color: #e2e8f0;
    padding: 0.5cm 0.6cm;
    border-radius: 6px;
    overflow-x: auto;
    font-size: 8pt;
    line-height: 1.5;
    margin: 0.4cm 0 0.6cm 0;
    page-break-inside: avoid;
}

pre code {
    background: none;
    color: inherit;
    padding: 0;
    font-size: 8pt;
}

/* ── Links ── */
a {
    color: #1e3a5f;
    text-decoration: none;
    border-bottom: 1px dotted #94a3b8;
}

/* ── Tibetan script ── */
:lang(bo), .tibetan {
    font-family: 'Noto Serif Tibetan', 'Kokonor', 'Microsoft Himalaya', serif;
}

/* Make sure Tibetan renders well inline */
td, th, li, p {
    font-family: 'Inter', 'Noto Serif Tibetan', 'Kokonor', -apple-system, sans-serif;
    line-height: 1.65;
}

/* ── Architecture diagram ── */
pre:has(code) {
    background: #0f172a;
}

/* ── Page break helpers ── */
h1:not(:first-of-type) {
    page-break-before: always;
}

.subtitle {
    text-align: center;
    font-size: 12pt;
    color: #64748b;
    margin-bottom: 2cm;
}
"""

def main():
    with open(INPUT_MD, "r", encoding="utf-8") as f:
        md_content = f.read()

    extensions = ["tables", "fenced_code", "codehilite", "toc", "sane_lists"]
    html_body = markdown.markdown(md_content, extensions=extensions)

    # Wrap the subtitle line
    html_body = html_body.replace(
        "<h2>Project Documentation</h2>",
        '<p class="subtitle">Project Documentation</p>'
    )

    full_html = f"""<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>Lotsawa Keyboard — Project Documentation</title>
    <style>{CSS}</style>
</head>
<body>
{html_body}
</body>
</html>"""

    HTML(string=full_html).write_pdf(OUTPUT_PDF)
    print(f"PDF generated: {OUTPUT_PDF}")

if __name__ == "__main__":
    main()

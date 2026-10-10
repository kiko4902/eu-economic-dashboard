"""Render the Power BI PDF export to one PNG per report page for the README.

Dev-only tool, not a project dependency. Run it with:

    make screenshots

which calls `uv run --no-project --with pymupdf --with pillow python scripts/render_screenshots.py`.
"""

import argparse
import io
from pathlib import Path

import pymupdf
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
PDF = ROOT / "powerbi" / "eu_dashboard.pdf"
OUT_DIR = ROOT / "docs" / "images"
# Report page order (powerbi/eu_dashboard.Report/definition/pages/pages.json).
PAGES = ["overview", "croatia_vs_eu", "country_comparison", "housing", "data_quality"]


def render_page(page: pymupdf.Page, width: int) -> Image.Image:
    """Render one PDF page to an RGB image `width` pixels wide."""
    zoom = width / page.rect.width
    pixmap = page.get_pixmap(matrix=pymupdf.Matrix(zoom, zoom), alpha=False)
    return Image.open(io.BytesIO(pixmap.tobytes("png"))).convert("RGB")


def save_small_png(image: Image.Image, path: Path) -> None:
    """Save as a 256-colour PNG: report pages are flat colours, so this keeps text sharp."""
    image.quantize(colors=256, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).save(
        path, optimize=True
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--pdf", type=Path, default=PDF)
    parser.add_argument("--out-dir", type=Path, default=OUT_DIR)
    parser.add_argument("--width", type=int, default=1600, help="PNG width in pixels")
    args = parser.parse_args()

    with pymupdf.open(args.pdf) as pdf:
        if pdf.page_count != len(PAGES):
            raise SystemExit(f"{args.pdf} has {pdf.page_count} pages, expected {len(PAGES)}")
        for page, name in zip(pdf, PAGES, strict=True):
            path = args.out_dir / f"powerbi_{name}.png"
            save_small_png(render_page(page, args.width), path)
            print(f"{path}: {path.stat().st_size // 1024} KB")


if __name__ == "__main__":
    main()

# assets/images

Two files, and the difference matters.

| File | Bundled in the IPA? | Read by |
|---|---|---|
| `icon.png` (1254×1254) | **No** | `flutter_launcher_icons` and `flutter_native_splash`, which read it from the FILESYSTEM at generate time (`pubspec.yaml` → `image_path` / `image`) |
| `brand_mark.png` (512×512) | **Yes** | `BrandMark` (`lib/shared/widgets/branding/brand_logo.dart`) |

`BrandMark` renders at 156 logical px at most, and the native splash needs
468 px at dpr 3 — so shipping the master meant ~0.85 MB of a ~1.02 MB asset
was pure download and install weight, the single largest bundled asset in the
repo. `BrandMark` already bounds *decode* via `cacheWidth`/`cacheHeight`; this
is about the bundle.

Regenerate `brand_mark.png` after any change to the master:

```bash
python -c "from PIL import Image; Image.open('assets/images/icon.png').convert('RGBA').resize((512,512), Image.LANCZOS).save('assets/images/brand_mark.png', optimize=True, compress_level=9)"
```

Kept as full RGBA rather than palette-quantized on purpose: the mark carries
~39k distinct colours at 512 px (it is not a flat logo), and a 256-colour
palette measured an RMS error of ~3 — visible banding on a brand asset, for
about 150 KB. If a smaller file is ever needed, re-check that number before
quantizing.

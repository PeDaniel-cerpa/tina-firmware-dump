#!/usr/bin/env python3
# ==============================================================================
# recolor_ui.py - recolorrea los recursos verdes de la interfaz sdvcam
#
# Procesa tres cosas:
#   1) imagenes sueltas en <res>/pic/** (PNG/JPG)
#   2) el paquete image.bin (descomprimido de image.bin.lzma)
#   3) atributos de color en <res>/**/*.xml
#
# Las imagenes del paquete estan en ARGB8888 little-endian (bytes B,G,R,A).
# Solo se tocan pixeles donde G es claramente dominante; la luminancia se
# conserva y se vuelca al color objetivo (por defecto rojo Marlboro).
#
# Uso:
#   ./recolor_ui.py --res m750root/data/res \
#                   --image-bin image.bin \
#                   --out ui_red \
#                   --color 210,20,20
# ==============================================================================
import argparse
import pathlib
import re
import shutil
import subprocess

def clamp(v):
    return 0 if v < 0 else 255 if v > 255 else int(v)

def recolor(data, order, target, tol):
    ri, gi, bi = order[:3]
    ai = order[3] if len(order) > 3 else None
    n = len(order)
    out = bytearray(data)
    green = total = 0
    denom = (0.299 + 0.587 * (target[1] / target[0]) +
             0.114 * (target[2] / target[0]))
    for off in range(0, len(data) - n + 1, n):
        r, g, b = data[off + ri], data[off + gi], data[off + bi]
        a = data[off + ai] if ai is not None else 255
        total += 1
        if a == 0 or g <= r + tol or g <= b + tol:
            continue
        green += 1
        lum = 0.299 * r + 0.587 * g + 0.114 * b
        nr = min(target[0], clamp(round(lum / denom)))
        out[off + ri] = nr
        out[off + gi] = clamp(round(nr * target[1] / target[0]))
        out[off + bi] = clamp(round(nr * target[2] / target[0]))
    return bytes(out), green, total

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--res', required=True, help='directorio res/ del rootfs')
    ap.add_argument('--image-bin', help='image.bin descomprimido (opcional)')
    ap.add_argument('--out', required=True, help='directorio de salida')
    ap.add_argument('--color', default='210,20,20', help='RGB destino')
    ap.add_argument('--tol', type=int, default=15)
    ap.add_argument('--min-pct', type=float, default=0.5)
    a = ap.parse_args()

    target = tuple(int(x) for x in a.color.split(','))
    assert len(target) == 3
    res = pathlib.Path(a.res)
    out = pathlib.Path(a.out)
    (out / 'pic').mkdir(parents=True, exist_ok=True)
    (out / 'xml').mkdir(parents=True, exist_ok=True)

    # 1) image.bin empaquetado
    if a.image_bin:
        b = pathlib.Path(a.image_bin).read_bytes()
        names = list(re.finditer(rb'[A-Za-z0-9_.-]+\.(?:png|jpg)\x00', b))
        patched = bytearray(b)
        changed = []
        for i, m in enumerate(names):
            start = m.start()
            end = names[i + 1].start() if i + 1 < len(names) else len(b)
            ds = start + 64 + 12
            new, g, t = recolor(bytes(patched[ds:end]), (2, 1, 0, 3),
                                target, a.tol)
            pct = 100.0 * g / t if t else 0
            if pct >= a.min_pct:
                patched[ds:end] = new
                changed.append((m.group().decode().rstrip('\0'), round(pct, 1)))
        (out / 'image.bin').write_bytes(patched)
        subprocess.run(['lzma', '-c', str(out / 'image.bin')],
                       stdout=open(out / 'image.bin.lzma', 'wb'), check=True)
        (out / 'image.bin').unlink()
        print('image.bin: %d entradas recoloreadas' % len(changed))
        for n, p in changed:
            print('  %5.1f%%  %s' % (p, n))

    # 2) imagenes sueltas
    changed = []
    for f in sorted(res.rglob('*')):
        if f.suffix.lower() not in ('.png', '.jpg', '.jpeg'):
            continue
        fmt = 'rgba' if f.suffix.lower() == '.png' else 'rgb24'
        probe = subprocess.run(
            ['ffprobe', '-v', 'error', '-select_streams', 'v:0',
             '-show_entries', 'stream=width,height', '-of', 'csv=p=0', str(f)],
            capture_output=True, text=True, check=True)
        w, h = probe.stdout.strip().split(',')[:2]
        dec = subprocess.run(['ffmpeg', '-loglevel', 'error', '-i', str(f),
                              '-f', 'rawvideo', '-pix_fmt', fmt, '-'],
                             capture_output=True, check=True)
        order = (0, 1, 2, 3) if fmt == 'rgba' else (0, 1, 2)
        new, g, t = recolor(dec.stdout, order, target, a.tol)
        pct = 100.0 * g / t if t else 0
        if pct < a.min_pct:
            continue
        dest = out / 'pic' / f.name
        cmd = ['ffmpeg', '-loglevel', 'error', '-y',
               '-f', 'rawvideo', '-pix_fmt', fmt, '-s', '%sx%s' % (w, h),
               '-i', '-']
        cmd += (['-c:v', 'png', str(dest)] if fmt == 'rgba'
                else ['-q:v', '2', '-pix_fmt', 'yuvj420p', str(dest)])
        with open(dest, 'wb') as fh:
            subprocess.run(cmd, input=new, stdout=fh, check=True)
        changed.append((f.name, round(pct, 1)))
    print('imagenes sueltas: %d recoloreadas' % len(changed))
    for n, p in changed:
        print('  %5.1f%%  %s' % (p, n))

    # 3) XML
    pat = re.compile(r'(\b(?:bgColor|bgcolor|color)=")(\d+)\|(\d+)\|(\d+)(")')
    xmls = []
    for f in sorted(res.rglob('*.xml')):
        t = f.read_text(encoding='utf-8', errors='ignore')
        def repl(m):
            r, g, b = int(m.group(2)), int(m.group(3)), int(m.group(4))
            if g > r + a.tol and g > b + a.tol:
                return m.group(1) + '|'.join(map(str, target)) + m.group(5)
            return m.group(0)
        new = pat.sub(repl, t)
        if new != t:
            (out / 'xml' / f.name).write_text(new, encoding='utf-8')
            xmls.append(f.name)
    print('XML: %d parcheados: %s' % (len(xmls), ', '.join(xmls)))

if __name__ == '__main__':
    main()

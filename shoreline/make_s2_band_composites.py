"""Yearly median Sentinel-2 band composites (20 m) of the coastal strip, for the U-Net.

Same scenes and cloud mask as make_mndwi_composites.py (sentinel2 mode), but
the output keeps six bands instead of the water index: B02 blue, B03 green,
B04 red, B08 near infrared, B11 and B12 short-wave infrared. All are read
at 20 m (the native size of B11 and B12; the 10 m bands are averaged).
Each band is the median surface reflectance of all clear looks in the year.
Only pixels kept by clip_to_coast.py (the coastal strip) are stored.
Usage: python make_s2_band_composites.py <out_dir> <strip_reference.tif>
  strip_reference.tif: any clipped Sentinel-2 MNDWI file from data/shoreline/
Output: uint16 reflectance x 10000 (0 = no data), 6 bands, EPSG:32631.
"""
import sys, os, numpy as np, pystac_client, planetary_computer as pc, rasterio, xarray as xr
from odc.stac import load
from rasterio.warp import reproject, Resampling

out, ref = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
BBOX = [3.35, 6.36, 4.42, 6.47]
BANDS = ['B02', 'B03', 'B04', 'B08', 'B11', 'B12']
cat = pystac_client.Client.open("https://planetarycomputer.microsoft.com/api/stac/v1", modifier=pc.sign_inplace)
with rasterio.open(ref) as f:
    strip = f.read(1) != -32768; rprof = f.profile
for yr in [2021, 2020] + [y for y in range(2016, 2026) if y not in (2020, 2021)]:   # training and test years first
    path = os.path.join(out, f'sentinel2_bands_{yr}.tif')
    if os.path.exists(path): continue
    items = list(cat.search(collections=['sentinel-2-l2a'], bbox=BBOX, datetime=f'{yr}-01-01/{yr}-12-31',
                            query={'eo:cloud_cover': {'lt': 80}}).items())
    ds = load(items, bands=BANDS + ['SCL'], crs='EPSG:32631', resolution=20, bbox=BBOX, groupby='solar_day',
              chunks={'x': 2048, 'y': 2048}, fail_on_error=False, resampling={'SCL': 'nearest', '*': 'average'})
    base = {i.datetime.date(): float(i.properties.get('s2:processing_baseline', '0') or 0) for i in items}
    off = np.array([-1000.0 if base.get(t.astype('datetime64[D]').item(), 0) >= 4.0 else 0.0 for t in ds.time.values], 'float32')
    offx = xr.DataArray(off, dims='time', coords={'time': ds.time})
    ok = ~ds.SCL.isin([0, 1, 3, 8, 9, 10, 11]) & (ds.B03 > 0) & (ds.B11 > 0)
    x, y = ds.x.values, ds.y.values
    tr = rasterio.Affine(x[1] - x[0], 0, x[0] - (x[1] - x[0]) / 2, 0, y[1] - y[0], y[0] - (y[1] - y[0]) / 2)
    k = np.zeros((len(y), len(x)), 'uint8')
    reproject(strip.astype('uint8'), k, src_transform=rprof['transform'], src_crs=rprof['crs'],
              dst_transform=tr, dst_crs='EPSG:32631', resampling=Resampling.nearest)
    stack = []
    for b in BANDS:
        v = ((ds[b].astype('float32') + offx) / 1e4).where(ok)
        m = v.median('time', skipna=True).compute().values
        stack.append(np.where(np.isfinite(m) & (k == 1), np.clip(np.round(m * 1e4), 1, 65535), 0).astype('uint16'))
    with rasterio.open(path, 'w', driver='GTiff', height=len(y), width=len(x), count=6, dtype='uint16', crs='EPSG:32631',
                       transform=tr, nodata=0, compress='deflate', predictor=2, zlevel=9) as f:
        for i, a in enumerate(stack):
            f.write(a, i + 1); f.set_band_description(i + 1, BANDS[i])
    print(yr, len(items), 'scenes', os.path.getsize(path) // 1024, 'KB', flush=True)

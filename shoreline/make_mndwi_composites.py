"""Yearly median MNDWI composites over the Lagos coast from Landsat and Sentinel-2.

Data: Microsoft Planetary Computer (Landsat Collection 2 Level-2 surface
reflectance, USGS; Sentinel-2 Level-2A, ESA Copernicus), read with odc-stac.
Usage: python make_mndwi_composites.py <out_dir> [landsat|landsat_early|landsat_pooled|sentinel2]
  landsat: one composite per year 1988-2025; landsat_early: one pooled 1984-1987 epoch;
  landsat_pooled: 3-year epochs 1998-2000 ... 2010-2012 (single years in this period
  have a median of only 1 to 3 clear looks, because of cloud and the Landsat 7
  scan-line gaps after May 2003), each labelled with the mean date of its images

Per scene:
  Landsat: reflectance = DN * 2.75e-5 - 0.2 (USGS C2 L2 scale). Pixels are
    dropped if QA_PIXEL flags fill, dilated cloud, cloud or cloud shadow, or if
    the DN is outside the valid range 7273-43636.
  Sentinel-2: reflectance = (DN + offset) / 10000, offset -1000 for processing
    baseline 04.00 and later (from 25 Jan 2022). Pixels dropped where SCL is
    no data, saturated, cloud shadow, cloud (medium, high), cirrus or snow.
  MNDWI = (green - swir1) / (green + swir1)   (Xu 2006)
Per year: median MNDWI of all clear observations, and the number of clear
observations. The median over many dates at random tide stages sits close to
the mid-tide waterline (the approach of Digital Earth Australia Coastlines,
Bishop-Taylor et al. 2021, without its tide filter). Output GeoTIFF bands:
1 median MNDWI x 10000 (int16, -32768 = no data), 2 clear observations (int16).
"""
import sys, os, numpy as np, pystac_client, planetary_computer as pc, rasterio
from odc.stac import load
from rasterio.transform import from_origin

out = sys.argv[1]; which = sys.argv[2] if len(sys.argv) > 2 else 'landsat'
os.makedirs(out, exist_ok=True)
BBOX = [3.35, 6.36, 4.42, 6.47]
cat = pystac_client.Client.open("https://planetarycomputer.microsoft.com/api/stac/v1", modifier=pc.sign_inplace)

def write(path, mndwi, n, ds):
    m = np.where(np.isfinite(mndwi), np.round(mndwi * 10000), -32768).astype('int16')
    x, y = ds.x.values, ds.y.values
    tr = from_origin(x[0] - (x[1] - x[0]) / 2, y[0] - (y[1] - y[0]) / 2, x[1] - x[0], y[0] - y[1])
    with rasterio.open(path, 'w', driver='GTiff', height=m.shape[0], width=m.shape[1], count=2, dtype='int16',
                       crs='EPSG:32631', transform=tr, nodata=-32768, compress='deflate') as f:
        f.write(m, 1); f.write(n.astype('int16'), 2)
        f.set_band_description(1, 'median_MNDWI_x10000'); f.set_band_description(2, 'clear_observations')

if which in ('landsat', 'landsat_early', 'landsat_pooled'):
    # 1984-1987 have few clear images (and 1988-1998 almost none in the
    # archive for this area), so the early years are pooled into one epoch,
    # labelled with the mean date of its images.
    if which == 'landsat':
        epochs = [(y, y) for y in range(1988, 2026)]
    elif which == 'landsat_early':
        epochs = [(1984, 1987)]
    else:
        epochs = [(y, y + 2) for y in range(1998, 2011, 3)]
    for y0, y1 in epochs:
        items = list(cat.search(collections=['landsat-c2-l2'], bbox=BBOX, datetime=f'{y0}-01-01/{y1}-12-31',
                                query={'eo:cloud_cover': {'lt': 80}, 'platform': {'in': ['landsat-5', 'landsat-7', 'landsat-8', 'landsat-9']}}).items())
        if not items: print(y0, 'no scenes', flush=True); continue
        yr = y0 if y0 == y1 else int(round(np.mean([i.datetime.year + i.datetime.timetuple().tm_yday / 365.25 for i in items])))
        tag = 'landsat_mndwi' if y0 == y1 or which == 'landsat_early' else 'landsat3yr_mndwi'
        path = os.path.join(out, f'{tag}_{yr}.tif')
        if os.path.exists(path) and y0 == y1: continue
        ds = load(items, bands=['green', 'swir16', 'qa_pixel'], crs='EPSG:32631', resolution=30, bbox=BBOX,
                  groupby='solar_day', chunks={'x': 2048, 'y': 2048}, fail_on_error=False)
        g = ds.green.astype('float32'); s = ds.swir16.astype('float32'); qa = ds.qa_pixel
        bad = (qa & (1 << 0) | qa & (1 << 1) | qa & (1 << 3) | qa & (1 << 4)) > 0
        ok = (~bad) & (g >= 7273) & (g <= 43636) & (s >= 7273) & (s <= 43636)
        G = g * 2.75e-5 - 0.2; S = s * 2.75e-5 - 0.2
        w = ((G - S) / (G + S)).where(ok & ((G + S) != 0))
        med = w.median('time', skipna=True).compute().values; n = ok.sum('time').compute().values
        write(path, med, n, ds)
        print(yr, f'({y0}-{y1})', len(items), 'scenes,', ds.sizes['time'], 'dates; median clear obs', int(np.median(n)), flush=True)
else:
    for yr in range(2016, 2026):
        path = os.path.join(out, f'sentinel2_mndwi_{yr}.tif')
        if os.path.exists(path): continue
        items = list(cat.search(collections=['sentinel-2-l2a'], bbox=BBOX, datetime=f'{yr}-01-01/{yr}-12-31',
                                query={'eo:cloud_cover': {'lt': 80}}).items())
        if not items: continue
        ds = load(items, bands=['B03', 'B11', 'SCL'], crs='EPSG:32631', resolution=10, bbox=BBOX,
                  groupby='solar_day', chunks={'x': 2048, 'y': 2048}, fail_on_error=False, resampling={'B11': 'bilinear', '*': 'nearest'})
        # offset per date from the processing baseline
        base = {i.datetime.date(): float(i.properties.get('s2:processing_baseline', '0') or 0) for i in items}
        off = np.array([-1000.0 if base.get(t.astype('datetime64[D]').item(), 0) >= 4.0 else 0.0 for t in ds.time.values], 'float32')
        import xarray as xr
        offx = xr.DataArray(off, dims='time', coords={'time': ds.time})
        g = (ds.B03.astype('float32') + offx) / 1e4; s = (ds.B11.astype('float32') + offx) / 1e4
        scl = ds.SCL
        ok = ~scl.isin([0, 1, 3, 8, 9, 10, 11]) & (ds.B03 > 0) & (ds.B11 > 0)
        w = ((g - s) / (g + s)).where(ok & ((g + s) != 0))
        med = w.median('time', skipna=True).compute().values; n = ok.sum('time').compute().values
        write(path, med, n, ds)
        print(yr, len(items), 'scenes,', ds.sizes['time'], 'dates; median clear obs', int(np.median(n)), flush=True)

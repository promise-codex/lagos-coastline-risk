"""Water labels for the U-Net from ESA WorldCover 2020 (v100) and 2021 (v200).

WorldCover (10 m, CC BY 4.0, Zanaga et al. 2021 and 2022) is made by ESA
from Sentinel-1 and Sentinel-2 with its own classifier, so it is
independent of our water index. Class 80 = permanent water bodies.
The label grid is the 20 m Sentinel-2 band composite grid: a 20 m cell is
water when at least half of its four 10 m WorldCover cells are class 80.
Usage: python make_worldcover_labels.py <template_bands.tif> <out_dir>
Output: worldcover_water_<year>.tif, uint8 (1 water, 0 land, 255 no data
outside the coastal strip), same grid as the template.
"""
import sys, os, numpy as np, rasterio, pystac_client, planetary_computer as pc
from rasterio.warp import reproject, Resampling
tpl, out = sys.argv[1], sys.argv[2]; os.makedirs(out, exist_ok=True)
with rasterio.open(tpl) as t:
    prof = t.profile; strip = t.read(2) > 0
cat = pystac_client.Client.open("https://planetarycomputer.microsoft.com/api/stac/v1", modifier=pc.sign_inplace)
items = list(cat.search(collections=['esa-worldcover'], bbox=[3.35, 6.36, 4.42, 6.47]).items())
for yr in (2020, 2021):
    its = [i for i in items if f'_{yr}_' in i.id]
    frac = np.zeros((prof['height'], prof['width']), 'float32')
    for it in its:
        with rasterio.open(it.assets['map'].href) as f:
            w = (f.read(1) == 80).astype('float32')
            tmp = np.full_like(frac, np.nan)
            reproject(w, tmp, src_transform=f.transform, src_crs=f.crs, dst_transform=prof['transform'],
                      dst_crs=prof['crs'], resampling=Resampling.average, dst_nodata=np.nan)
            frac = np.where(np.isnan(tmp), frac, tmp)
    lab = np.where(strip, (frac >= 0.5).astype('uint8'), 255).astype('uint8')
    p = prof.copy(); p.update(count=1, dtype='uint8', nodata=255, compress='deflate')
    with rasterio.open(os.path.join(out, f'worldcover_water_{yr}.tif'), 'w', **p) as g:
        g.write(lab, 1)
    print(yr, len(its), 'tiles; water share in strip %.3f' % (lab[strip] == 1).mean(), flush=True)

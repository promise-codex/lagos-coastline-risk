"""Keep only a strip along the open coast in each composite, to keep the files small.

The ocean is the water body connected to the southern edge in the 2020
Landsat composite (MNDWI > 0). Pixels are kept if they lie within LAND_M of
that ocean on the land side or within SEA_M of the shore on the sea side;
everything else becomes no data. Sentinel-2 is averaged from 10 m to 20 m,
the native size of its SWIR band. The strip is wide enough for every road
transect (the road is at most about 2 km from the beach).
Usage: python clip_to_coast.py <in_dir> <out_dir>
"""
import sys, os, glob, numpy as np, rasterio
from scipy import ndimage
from rasterio.warp import reproject, Resampling
LAND_M, SEA_M = 3000, 1500
src, dst = sys.argv[1], sys.argv[2]; os.makedirs(dst, exist_ok=True)
with rasterio.open(os.path.join(src, 'landsat_mndwi_2020.tif')) as f:
    m = f.read(1); ref = f.profile
w = (m > 0) & (m != -32768)
lab, _ = ndimage.label(w)
ocean = lab == np.argmax(np.bincount(lab[-1][lab[-1] > 0]))
dLand = ndimage.distance_transform_edt(~ocean) * 30          # distance from the ocean, over land
dSea = ndimage.distance_transform_edt(ocean) * 30             # distance from the shore, over the ocean
keep = ((~ocean) & (dLand <= LAND_M)) | (ocean & (dSea <= SEA_M))
for p in sorted(glob.glob(os.path.join(src, '*_mndwi_*.tif'))):
    with rasterio.open(p) as f:
        a = f.read(); prof = f.profile
        k = np.zeros((f.height, f.width), 'uint8')
        reproject(keep.astype('uint8'), k, src_transform=ref['transform'], src_crs=ref['crs'],
                  dst_transform=f.transform, dst_crs=f.crs, resampling=Resampling.nearest)
    a[0][k == 0] = -32768; a[1][k == 0] = 0
    if 'sentinel2' in p:
        # 10 m -> 20 m (the native size of the SWIR band): mean MNDWI, max count
        h, wd = (a.shape[1] // 2) * 2, (a.shape[2] // 2) * 2
        v = a[0][:h, :wd].astype('float32'); v[v == -32768] = np.nan
        v = v.reshape(h // 2, 2, wd // 2, 2)
        with np.errstate(invalid='ignore'):
            mv = np.nanmean(v, axis=(1, 3))
        nobs = a[1][:h, :wd].reshape(h // 2, 2, wd // 2, 2).max(axis=(1, 3))
        a = np.stack([np.where(np.isnan(mv), -32768, np.round(mv)).astype('int16'), nobs.astype('int16')])
        t = prof['transform']
        prof.update(width=wd // 2, height=h // 2, transform=rasterio.Affine(t.a * 2, 0, t.c, 0, t.e * 2, t.f))
    prof.update(compress='deflate', predictor=2, zlevel=9)
    with rasterio.open(os.path.join(dst, os.path.basename(p)), 'w', **prof) as g:
        g.write(a)
        g.set_band_description(1, 'median_MNDWI_x10000'); g.set_band_description(2, 'clear_observations')
    print(os.path.basename(p), os.path.getsize(os.path.join(dst, os.path.basename(p))) // 1024, 'KB')

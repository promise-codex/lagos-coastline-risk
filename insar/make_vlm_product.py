"""Turn the MintPy line-of-sight velocity into a vertical land-motion map tied to GPS.

Run from the MintPy work folder after smallbaselineApp.py has finished:
    python make_vlm_product.py <mintpy_dir> <out_dir>

Steps
1. Re-reference the corrected time series (troposphere by height correlation,
   DEM error removed) to the pixel that holds the UNILAG GPS stations ULAG and
   LAF1 (they are 0.26 km apart), and fit a linear rate over 2017-2025.
2. Fit the same rate on two shorter windows (2019-2025 and 2017-2023) to see
   how much the answer depends on the period. Half the spread of the three
   rates goes into the uncertainty.
3. Convert line-of-sight (LOS) to vertical: v_up = v_los / cos(incidence).
   This assumes the ground moves only up or down. Horizontal plate motion is
   common to the whole scene and cancels when a reference pixel is used.
4. Add the GPS vertical rate at UNILAG so the map is relative to the Earth's
   centre (IGS20 frame), not to the reference pixel. The GPS records end in
   2012-2013, before the radar record starts, so this assumes the UNILAG rate
   did not change. Its uncertainty is kept apart (DATUM_SIGMA) because it
   shifts every pixel by the same amount.
5. Keep land pixels with temporal coherence >= 0.5, write a 3-band GeoTIFF in
   WGS84 lat/lon: vertical rate (mm/yr, positive = up), 1-sigma local
   uncertainty (mm/yr), temporal coherence.
"""
import os, subprocess, sys, json
import numpy as np, h5py
from osgeo import gdal, osr

mdir, odir = sys.argv[1], sys.argv[2]
os.makedirs(odir, exist_ok=True)
REF_YX = (141, 66)            # pixel holding ULAG/LAF1 (6.517 N, 3.398 E)
# NGL IGS20 daily vertical series, 1-year pair median rates (MIDAS-style):
# ULAG 2011.0-2013.8: -2.8 mm/yr; LAF1 2008.2-2012.7: -0.6 mm/yr
GPS_UP = -1.7                 # mean of the two stations, mm/yr
DATUM_SIGMA = 2.5             # mm/yr: station difference (2.2) plus the unknown change since 2013
MIN_TCOH = 0.5

def run(cmd):
    subprocess.run(cmd, cwd=mdir, check=True, stdout=subprocess.DEVNULL)

ts = 'ts_refULAG.h5'
if not os.path.isfile(os.path.join(mdir, ts)):
    run(['cp', 'timeseries_tropHgt_demErr.h5', ts])
    run(['reference_point.py', ts, '-y', str(REF_YX[0]), '-x', str(REF_YX[1])])
variants = {'full': [], 'from2019': ['--start-date', '20190101'], 'to2023': ['--end-date', '20231231']}
for k, a in variants.items():
    run(['timeseries2velocity.py', ts, '-o', f'vel_{k}.h5'] + a)

g = h5py.File(os.path.join(mdir, 'inputs/geometryGeo.h5'), 'r')
inc = g['incidenceAngle'][:]; land = g['waterMask'][:] > 0
cosi = np.cos(np.deg2rad(inc))
tc = h5py.File(os.path.join(mdir, 'temporalCoherence.h5'), 'r')['temporalCoherence'][:]
V, S = {}, None
for k in variants:
    f = h5py.File(os.path.join(mdir, f'vel_{k}.h5'), 'r')
    V[k] = f['velocity'][:] * 1000 / cosi
    if k == 'full':
        S = f['velocityStd'][:] * 1000 / cosi
        attrs = dict(f.attrs)
stack = np.stack(list(V.values()))
spread = (stack.max(0) - stack.min(0)) / 2
up = V['full'] + GPS_UP
sig = np.sqrt(S**2 + spread**2)
keep = land & (tc >= MIN_TCOH)
up[~keep] = np.nan; sig[~keep] = np.nan
tcb = np.where(keep, tc, np.nan)

# write UTM, then warp to lat/lon
ny, nx = up.shape
x0, dx = float(attrs['X_FIRST']), float(attrs['X_STEP'])
y0, dy = float(attrs['Y_FIRST']), float(attrs['Y_STEP'])
epsg = int(attrs.get('EPSG', 32631))
utm = os.path.join(odir, '_vlm_utm.tif')
ds = gdal.GetDriverByName('GTiff').Create(utm, nx, ny, 3, gdal.GDT_Float32)
ds.SetGeoTransform((x0, dx, 0, y0, 0, dy))
sr = osr.SpatialReference(); sr.ImportFromEPSG(epsg); ds.SetProjection(sr.ExportToWkt())
for i, (a, d) in enumerate([(up, 'vertical_rate_mm_per_yr_positive_up'),
                            (sig, 'local_1sigma_mm_per_yr'), (tcb, 'temporal_coherence')], 1):
    b = ds.GetRasterBand(i); b.WriteArray(a.astype(np.float32)); b.SetNoDataValue(np.nan); b.SetDescription(d)
ds = None
out = os.path.join(odir, 'lagos_vlm_s1_2017_2025.tif')
gdal.Warp(out, utm, dstSRS='EPSG:4326', xRes=0.00072, yRes=0.00072, resampleAlg='near',
          creationOptions=['COMPRESS=DEFLATE', 'PREDICTOR=3'])
os.remove(utm)
d = gdal.Open(out, gdal.GA_Update)
for i, n in enumerate(['vertical_rate_mm_per_yr_positive_up', 'local_1sigma_mm_per_yr', 'temporal_coherence'], 1):
    d.GetRasterBand(i).SetDescription(n)
d.SetMetadata({'reference': 'UNILAG GPS ULAG/LAF1 pixel, plus GPS_UP', 'GPS_UP_mm_yr': str(GPS_UP),
               'DATUM_SIGMA_mm_yr': str(DATUM_SIGMA), 'period': '2017-01-10 to 2025-12-30',
               'min_temporal_coherence': str(MIN_TCOH)})
d = None

v = up[keep]
summary = {'pixels': int(keep.sum()), 'gps_up_mm_yr': GPS_UP, 'datum_sigma_mm_yr': DATUM_SIGMA,
           'percentiles_mm_yr': {str(p): round(float(np.percentile(v, p)), 1) for p in [1, 5, 10, 25, 50, 75, 90, 95, 99]},
           'median_local_sigma': round(float(np.nanmedian(sig)), 2)}
json.dump(summary, open(os.path.join(odir, 'vlm_summary.json'), 'w'), indent=1)
print(json.dumps(summary, indent=1))

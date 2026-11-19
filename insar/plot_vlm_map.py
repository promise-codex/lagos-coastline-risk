"""Map of the vertical land motion product (docs/figures/insar_vlm_map.png)."""
import sys, numpy as np
import matplotlib; matplotlib.use('Agg'); import matplotlib.pyplot as plt
from osgeo import gdal
gdal.UseExceptions()
src, out = sys.argv[1], sys.argv[2]
d = gdal.Open(src); v = d.GetRasterBand(1).ReadAsArray(); gt = d.GetGeoTransform()
ext = [gt[0], gt[0] + gt[1] * d.RasterXSize, gt[3] + gt[5] * d.RasterYSize, gt[3]]
fig, ax = plt.subplots(figsize=(13, 4.6))
ax.set_facecolor('#e6e6e6')
im = ax.imshow(np.ma.masked_invalid(v), extent=ext, cmap='RdBu', vmin=-20, vmax=20, interpolation='nearest')
places = {'UNILAG GPS (ULAG, LAF1)': (3.398, 6.517), 'Victoria Island': (3.42, 6.43),
          'Lekki Phase 1': (3.48, 6.44), 'Ajah': (3.575, 6.47)}
for n, (lo, la) in places.items():
    ax.plot(lo, la, 'k^' if 'GPS' in n else 'k.', ms=7)
    ax.annotate(n, (lo, la), xytext=(3, 5), textcoords='offset points', fontsize=8)
cb = fig.colorbar(im, ax=ax, fraction=0.025, pad=0.01)
cb.set_label('Vertical land motion (mm/yr)\nnegative = sinking')
ax.set_xlabel('Longitude (deg E)'); ax.set_ylabel('Latitude (deg N)')
ax.set_aspect(1 / np.cos(np.deg2rad(6.45)))
ax.set_title('Vertical land motion from Sentinel-1 radar, Jan 2017 to Dec 2025, tied to UNILAG GPS '
             '(grey = no reliable measurement: water, vegetation or low coherence)', fontsize=9.5)
plt.tight_layout(); plt.savefig(out, dpi=200)

%DIAGNOSE_DEM Quick check of how DeltaDTM stores the sea, the lagoon and land.
%   Prints the no-data setting, the value range, and sample values along
%   the southern (sea) and northern edges, and saves a picture of the grid.

cfg = project_config();
f = dir(fullfile(cfg.demDir, '*N06E003*.tif'));
info = georasterinfo(fullfile(f(1).folder, f(1).name));
fprintf('File: %s\n', f(1).name);
fprintf('MissingDataIndicator: %s\n', mat2str(info.MissingDataIndicator));
fprintf('NativeFormat: %s\n', string(info.NativeFormat));

[Z, M, R] = load_dem(cfg);
fprintf('RowsStartFrom: %s, ColumnsStartFrom: %s, RasterInterpretation: %s\n', ...
    R.RowsStartFrom, R.ColumnsStartFrom, R.RasterInterpretation);
fprintf('Share of NaN cells: %.1f%%\n', 100 * mean(isnan(Z(:))));
fprintf('Min / max of the values: %.2f / %.2f m\n', min(Z(:)), max(Z(:)));
v = Z(~isnan(Z));
fprintf('Most common values: %s\n', mat2str(mode(v)));
fprintf('Share of cells exactly 0: %.1f%%, below 0: %.1f%%, exactly 10: %.1f%%\n', ...
    100*mean(v == 0), 100*mean(v < 0), 100*mean(v == 10));
cols = round(linspace(1, size(Z, 2), 8));
fprintf('Row 1 (first row) at 8 columns:   %s\n', mat2str(Z(1, cols), 3));
fprintf('Last row at the same 8 columns:   %s\n', mat2str(Z(end, cols), 3));

[lat, lon] = geographicGrid(R);
fig = figure('Color', 'w', 'Position', [100 100 1100 450]);
ax = axes(fig);
imagesc(ax, lon(1,:), lat(:,1), Z, 'AlphaData', ~isnan(Z));
set(ax, 'YDir', 'normal', 'Color', [1 0 1]);
colormap(ax, parula); clim(ax, [-2 10]); colorbar(ax);
axis(ax, 'image');
title(ax, 'DeltaDTM values (magenta = no data)');
exportgraphics(fig, fullfile(cfg.figDir, 'dem_check.png'), 'Resolution', 150);
fprintf('Saved %s\n', fullfile(cfg.figDir, 'dem_check.png'));

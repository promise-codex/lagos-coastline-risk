%DIAGNOSE_LOW_STRETCH Check why the route near km 40-62 is reached by today's high tide.
%   Zoomed map: ocean (dark blue), lagoon and creeks (light blue), land the
%   ocean reaches at mean higher high water (red), and the route (yellow).
%   Also prints ground heights along the route per km: the lowest point,
%   the 10th percentile, and the median, to see whether one low pixel
%   (a creek crossing or a data error) decides the whole kilometre.

cfg = project_config();
[Z, M, R] = load_dem(cfg);
S = load(fullfile(cfg.resultsDir, 'flood_level_map_ocean.mat'), 'FLo');
FLo = S.FLo;
G = readtable(fullfile(cfg.dataDir, 'gtsm', 'gtsm_lagos_stations.csv'));
mhhw = mean(G.MHHW_m);

H = load(fullfile(cfg.osmDir, 'highway_segments.mat'), 'segs', 'samples');
[I, J] = geographicToDiscrete(R, H.samples.lat, H.samples.lon);
ok = ~isnan(I) & ~isnan(J);
z = nan(size(I)); z(ok) = Z(sub2ind(size(Z), I(ok), J(ok)));
mk = nan(size(I)); mk(ok) = M(sub2ind(size(M), I(ok), J(ok)));
fo = nan(size(I)); fo(ok) = FLo(sub2ind(size(FLo), I(ok), J(ok)));
ch = H.samples.chainage_km;

fprintf('km   lowest  p10   median  points_on_water  points_ocean_reaches_at_MHHW\n');
for k = 40:62
    in = ch >= k & ch < k + 1;
    zz = z(in);
    fprintf('%3d  %6.2f %5.2f %6.2f  %8d  %8d\n', k, min(zz), prctile(zz, 10), median(zz, 'omitnan'), ...
        sum(mk(in) ~= 0), sum(fo(in) <= mhhw));
end

% Zoomed map
[lat, lon] = geographicGrid(R);
win = lon(1,:) >= 3.78 & lon(1,:) <= 4.02;
rows = lat(:,1) >= 6.40 & lat(:,1) <= 6.50;
fig = figure('Color', 'w', 'Position', [100 100 1200 520]);
ax = axes(fig);
Zw = Z(rows, win); Mw = M(rows, win); Fw = FLo(rows, win);
imagesc(ax, lon(1,win), lat(rows,1), Zw, 'AlphaData', ~isnan(Zw));
set(ax, 'YDir', 'normal', 'Color', 'w'); colormap(ax, gray); clim(ax, [0 6]);
cb = colorbar(ax); cb.Label.String = 'Ground (m)';
hold(ax, 'on');
over = @(mask, rgb) image(ax, lon(1,win), lat(rows,1), ...
    cat(3, rgb(1)*ones(size(mask)), rgb(2)*ones(size(mask)), rgb(3)*ones(size(mask))), ...
    'AlphaData', 0.8 * double(mask));
over(Mw == 1, [0 0.2 0.6]);
over(Mw == 2, [0.4 0.75 1]);
over(Fw <= mhhw, [1 0 0]);
plot(ax, H.samples.lon, H.samples.lat, 'y-', 'LineWidth', 2);
hold(ax, 'off'); axis(ax, 'image');
xlim(ax, [3.78 4.02]); ylim(ax, [6.40 6.50]);
title(ax, sprintf('km 40-62: ocean (dark blue), lagoon/creeks (light blue), land reached from the ocean at high tide %.2f m (red), route (yellow)', mhhw));
exportgraphics(fig, fullfile(cfg.figDir, 'low_stretch_check.png'), 'Resolution', 200);
fprintf('Saved results/figures/low_stretch_check.png\n');

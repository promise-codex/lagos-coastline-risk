%RUN_FULLMAP_SINKING M1 and M3 with the measured land motion applied pixel by pixel.
%   The radar map (sinking_field) lowers or raises every cell of the
%   elevation model at its own rate, and the connected bathtub is re-run
%   for every year 2020-2150 (fullmap_first_years). This replaces the
%   earlier shortcut that gave each road km one rate: a check showed the
%   shortcut misses water that reaches the road through land that sinks
%   faster than the road itself.
%
%   Runs every AR6 scenario (SSP1-2.6, 2-4.5, 5-8.5) and percentile (5,
%   17, 50, 83, 95) so the app can use the results, for the mean level
%   (any water source) and for high tide and 1, 10 and 100-year storms
%   (open sea only, as in run_m3_extremes).
%
%   Checks first that the new code gives the same answer as the
%   flood-level map when sinking is uniform (0 and 11.4 mm/yr), then
%   splits the difference between the shortcut and the full map into
%   (a) different rates at different points of the same km and
%   (b) water arriving through faster-sinking land around the road.
%
%   Needs: run_m1_sinking (flood_level_map.mat) and the route files.
%   Saves results/fullmap_first_years.mat and two figures. About 10 minutes.

cfg = project_config();
[Z, M, R] = load_dem(cfg);
road = road_cells(cfg, R, M);
[V, S, src] = sinking_field(cfg, R, size(Z));
years = cfg.years; t0 = cfg.refYear;

land = M == 0;
srcNames = {'radar pixel', sprintf('mean within %g m', cfg.insarBuffer_m), ...
    sprintf('mean within %g m', 3 * cfg.insarBuffer_m), 'nearest pixel further away / outside'};
fprintf('Where the sinking rate of each cell comes from (land cells / road points):\n');
for k = 1:4
    fprintf('  %-38s %5.1f%% / %5.1f%%\n', srcNames{k}, 100 * mean(src(land) == k), ...
        100 * mean(src(road.idx) == k));
end
fprintf('Land cells: median rate %.1f mm/yr, 10th to 90th percentile %.1f to %.1f (negative = sinking)\n', ...
    1000 * median(V(land)), 1000 * prctile(V(land), 10), 1000 * prctile(V(land), 90));
fprintf('Road points: median rate %.1f mm/yr, 10th to 90th percentile %.1f to %.1f\n', ...
    1000 * median(V(road.idx)), 1000 * prctile(V(road.idx), 10), 1000 * prctile(V(road.idx), 90));

% ---- AR6 curves ----------------------------------------------------------------------
C = readcell(cfg.slrFile, 'Sheet', 'Total');
hdr = C(1, :);
yearCols = find(cellfun(@(x) isnumeric(x) && ~isempty(x) && x > 1900, hdr));
arYears = cell2mat(hdr(yearCols));
scen = {'ssp126', 'ssp245', 'ssp585'}; q = [5 17 50 83 95];
H6 = zeros(numel(scen), numel(q), numel(years));
for s = 1:numel(scen)
    for i = 1:numel(q)
        row = find(strcmp(C(:, 3), 'medium') & strcmp(C(:, 4), scen{s}) & ...
                   cellfun(@(x) isnumeric(x) && isequal(x, q(i)), C(:, 5)));
        v = interp1(arYears, cell2mat(C(row, yearCols)), years);
        H6(s, i, :) = v - v(years == t0);
    end
end

% ---- Extra event levels per grid column (nearest GTSM point along the coast) ---------
G = readtable(fullfile(cfg.dataDir, 'gtsm', 'gtsm_lagos_stations.csv'));
[~, lonGrid] = geographicGrid(R);
[~, nn] = min(abs(lonGrid(1, :)' - G.lon'), [], 2);
eventNames = {'Mean sea level', 'High tide (MHHW)', '1-year storm', '10-year storm', '100-year storm'};
Ecols = [zeros(1, numel(nn)); G.MHHW_m(nn)'; G.rp1_m(nn)'; G.rp10_m(nn)'; G.rp100_m(nn)'];

% ---- 1. Check against the flood-level map (uniform sinking) ----------------------------
Sfl = load(fullfile(cfg.resultsDir, 'flood_level_map.mat'), 'FL');
fl = double(Sfl.FL(road.idx));
segLevel = accumarray(road.seg, fl, [road.nSeg 1], @(x) wetLevel(x, cfg.segmentWetShare), NaN);
h = squeeze(H6(2, 3, :))';                                        % SSP2-4.5 median
fprintf('\nCheck: full-map code vs flood-level map, uniform sinking, SSP2-4.5 median, mean level\n');
for rate = [0 11.4]
    yrMap = fullmap_first_years(Z, M, single(-rate / 1000), years, h, t0, zeros(1, numel(nn)), cfg, road);
    yrFL = firstYear(segLevel, h + rate / 1000 * (years - t0), years);
    ok = ~isnan(yrMap) & ~isnan(yrFL);
    d = yrMap(ok) - yrFL(ok); d(isinf(yrMap(ok)) & isinf(yrFL(ok))) = 0;
    fprintf('  %4.1f mm/yr: km by 2100 %d (full map) vs %d (flood-level map); largest difference %g years\n', ...
        rate, sum(yrMap <= 2100), sum(yrFL <= 2100), max(abs(d)));
end
fprintf('  (small differences come from the 5 cm steps of the flood-level map)\n');

% ---- 2. Why the per-km shortcut differs (SSP2-4.5 median, mean level) ------------------
Ti = insar_segment_rates(cfg, false);
zr = double(Z(road.idx)); vr = double(V(road.idx)); vSeg = -Ti.sink_mm_yr(road.seg) / 1000;
yrPtOwn = inf(road.nSeg, 1); yrPtSeg = inf(road.nSeg, 1);
for k = 1:numel(years)
    dt = years(k) - t0;
    sOwn = accumarray(road.seg, double(zr + vr * dt <= h(k)), [road.nSeg 1]) ./ max(road.nLand, 1);
    sSeg = accumarray(road.seg, double(zr + vSeg * dt <= h(k)), [road.nSeg 1]) ./ max(road.nLand, 1);
    yrPtOwn(sOwn >= cfg.segmentWetShare & isinf(yrPtOwn)) = years(k);
    yrPtSeg(sSeg >= cfg.segmentWetShare & isinf(yrPtSeg)) = years(k);
end
fprintf('\nWhy one rate per km differs from the full map (road km low enough by 2100, ignoring connection to the water):\n');
fprintf('  each road point sinks at the km median rate: %d km\n', sum(yrPtSeg <= 2100));
fprintf('  each road point sinks at its own rate:       %d km\n', sum(yrPtOwn <= 2100));

% ---- 3. Full map, every scenario and percentile ----------------------------------------
nSeg = road.nSeg;
yrAny = nan(numel(scen), numel(q), nSeg);
yrOcean = nan(numel(scen), numel(q), nSeg, numel(eventNames));
tic
for s = 1:numel(scen)
    for i = 1:numel(q)
        [a, o] = fullmap_first_years(Z, M, V, years, squeeze(H6(s, i, :))', t0, Ecols, cfg, road);
        yrAny(s, i, :) = a; yrOcean(s, i, :, :) = o;
    end
    fprintf('  %s done (%.0f s)\n', scen{s}, toc);
end
yrFirst = min(repmat(yrAny, 1, 1, 1, numel(eventNames)), yrOcean);   % any water at mean level, or open sea at event peak
fprintf('  connected to water (full map) by 2100, SSP2-4.5 median, mean level: %d km\n', sum(yrAny(2, 3, :) <= 2100));

fprintf('\nRoad km reached with measured sinking (full map), AR6 median\n');
fprintf('%-8s %-18s %6s %8s %8s %8s %8s\n', 'Scenario', 'Event', 'today', 'by 2030', 'by 2050', 'by 2100', 'first');
for s = 2:3
    for e = 1:numel(eventNames)
        yr = squeeze(yrFirst(s, 3, :, e));
        fprintf('%-8s %-18s %6d %8d %8d %8d %8g\n', scen{s}, eventNames{e}, sum(yr <= t0), ...
            sum(yr <= 2030), sum(yr <= 2050), sum(yr <= 2100), min(yr));
    end
end
save(fullfile(cfg.resultsDir, 'fullmap_first_years.mat'), 'yrAny', 'yrOcean', 'yrFirst', ...
    'scen', 'q', 'eventNames', 'years');

% ---- 4. Figures ----------------------------------------------------------------------------
[lat, lon] = geographicGrid(R);
st = 3;                                                         % plot every 3rd cell (~90 m)
xs = lon(1, 1:st:end); ys = lat(1:st:end, 1);
fig = figure('Color', 'w', 'Position', [60 60 1250 820]);
tl = tiledlayout(fig, 2, 1, 'TileSpacing', 'compact');
ax1 = nexttile(tl);
Vp = 1000 * double(V); Vp(~land) = NaN;
imagesc(ax1, xs, ys, Vp(1:st:end, 1:st:end)); axis(ax1, 'xy'); set(ax1, 'DataAspectRatio', [1 cosd(6.45) 1]);
colormap(ax1, flipud(redblue(256))); clim(ax1, [-20 20]);
cb = colorbar(ax1); cb.Label.String = 'mm/yr (negative = sinking)';
hold(ax1, 'on'); [rI, rJ] = ind2sub(size(Z), road.idx);
plot(ax1, lon(1, rJ), lat(rI, 1), 'k.', 'MarkerSize', 2); hold(ax1, 'off');
title(ax1, 'Land motion used for every elevation cell (radar, gaps filled from nearby pixels); black = highway');
ax2 = nexttile(tl);
w0 = bathtub_flood(Z, M, h(years == 2100), cfg);
w1 = false(size(Z));
for k = find(years <= 2100)
    w1 = w1 | bathtub_flood(Z + V * (years(k) - t0), M, h(k), cfg);
end
cls = zeros(size(Z)); cls(land) = 1; cls(w1) = 3; cls(w0) = 2; cls(~land) = 0;
imagesc(ax2, xs, ys, cls(1:st:end, 1:st:end));
axis(ax2, 'xy'); set(ax2, 'DataAspectRatio', [1 cosd(6.45) 1]);
colormap(ax2, [0.75 0.85 0.95; 0.93 0.93 0.9; 0.2 0.4 0.8; 0.85 0.2 0.15]); clim(ax2, [-0.5 3.5]);
hold(ax2, 'on'); plot(ax2, lon(1, rJ), lat(rI, 1), 'k.', 'MarkerSize', 2); hold(ax2, 'off');
title(ax2, sprintf(['Land under the mean sea level of 2100 (SSP2-4.5 median): blue = bathtub M0 (%.0f km^2), ' ...
    'red = added by measured sinking (%.0f km^2)'], sum(cell_area_km2(R) .* w0, 'all'), ...
    sum(cell_area_km2(R) .* (w1 & ~w0), 'all')));
xlabel(ax2, 'Longitude (deg E)'); ylabel(ax1, 'Latitude (deg N)'); ylabel(ax2, 'Latitude (deg N)');
exportgraphics(fig, fullfile(cfg.figDir, 'fullmap_sinking_2100.png'), 'Resolution', 200);
fprintf('\nSaved results/fullmap_first_years.mat and figures/fullmap_sinking_2100.png\n');

% -------------------------------------------------------------------------
function yr = firstYear(needed, h, years)
yr = inf(size(needed));
for i = 1:numel(needed)
    if isnan(needed(i)), yr(i) = NaN; continue, end
    k = find(h >= needed(i), 1);
    if ~isempty(k), yr(i) = years(k); end
end
end

function L = wetLevel(x, share)
x = sort(x(~isnan(x)));
if isempty(x), L = NaN; return, end
L = x(max(1, ceil(share * numel(x))));
end

function c = redblue(n)
x = linspace(-1, 1, n)';
c = 0.15 + 0.85 * [min(1, 1 + x), 1 - abs(x), min(1, 1 - x)];
end

%EXTRACT_SHORELINES Step 6: our own shoreline positions 1984-2025 from Landsat and Sentinel-2.
%   Input: yearly median MNDWI composites in data/shoreline/ (made by
%   shoreline/make_mndwi_composites.py; band 1 = MNDWI x 10000, band 2 =
%   number of clear observations).
%
%   For every 1 km road segment a transect is drawn from the road, at right
%   angles to it, out to sea (towards the south, which is where the ocean
%   is along this whole coast). Along the transect the MNDWI is sampled
%   every 5 m. Walking in from the sea, the shoreline is the first place
%   where MNDWI falls below cfg.mndwiThreshold (0, as in Digital Earth
%   Australia Coastlines), found to sub-pixel accuracy by linear
%   interpolation between the two samples either side.
%   A position is kept only if the sea end of the transect (its last sample
%   with data; the composites keep a strip 1.5 km out to sea) is water, the
%   profile has no gap between the sea end and the shoreline, and the
%   shoreline pixel had at least cfg.minClearObs clear observations.
%
%   Outputs (results/):
%     shoreline_positions.csv   distance from the road to the shoreline (m),
%                               one row per segment, one column per sensor-year
%     shoreline_rates.csv       per segment: linear regression rate (LRR) and
%                               end point rate (EPR) 1984/86-2025, with the
%                               assessment's rate for comparison
%   and prints three checks:
%     1. Landsat vs Sentinel-2 positions in the same years (2016-2025)
%     2. our rates vs the assessments' DSAS rates (same idea, same satellites)
%     3. our 2020 shoreline distance vs the DEM-based distance used in run_m2

cfg = project_config();
shoreDir = fullfile(cfg.dataDir, 'shoreline');
H = load(fullfile(cfg.osmDir, 'highway_segments.mat'), 'segs', 'samples');
segs = H.segs; nSeg = height(segs);
mid = (segs.start_km + segs.end_km) / 2;
utm = projcrs(32631);

% ---- Transects -------------------------------------------------------------------
ok = H.samples.mapped(:) & ~isnan(H.samples.lat(:));
[sx, sy] = projfwd(utm, H.samples.lat(ok), H.samples.lon(ok));
sc = H.samples.chainage_km(ok);
x0 = interp1(sc, sx, mid); y0 = interp1(sc, sy, mid);
xa = interp1(sc, sx, mid - 0.5, 'linear', 'extrap'); ya = interp1(sc, sy, mid - 0.5, 'linear', 'extrap');
xb = interp1(sc, sx, mid + 0.5, 'linear', 'extrap'); yb = interp1(sc, sy, mid + 0.5, 'linear', 'extrap');
t = [xb - xa, yb - ya]; t = t ./ vecnorm(t, 2, 2);
nrm = [t(:, 2), -t(:, 1)];                                 % one of the two normals
flip = nrm(:, 2) > 0; nrm(flip, :) = -nrm(flip, :);       % make it point south, to the sea
s = (-300:5:cfg.transectLength_m)';                        % distance along the transect from the road (m)

% ---- Composites ------------------------------------------------------------------------
% Landsat: one pooled 1984-1987 epoch (labelled 1986), 3-year epochs for
% 1998-2012 (files landsat3yr_*, labelled with the mean image date), then
% single years 2013-2025. Sentinel-2: single years 2016-2025.
files = [dir(fullfile(shoreDir, 'landsat_mndwi_*.tif')); dir(fullfile(shoreDir, 'landsat3yr_mndwi_*.tif')); ...
    dir(fullfile(shoreDir, 'sentinel2_mndwi_*.tif'))];
names = string({files.name});
sensor = extractBefore(names, '_mndwi'); yr = double(extractBetween(names, 'mndwi_', '.tif'));
sensor(sensor == "landsat3yr") = "landsat";
[~, o] = sortrows([double(sensor == "sentinel2")', yr']); files = files(o); sensor = sensor(o); yr = yr(o);
P = nan(nSeg, numel(files));
for f = 1:numel(files)
    [A, R] = readgeoraster(fullfile(files(f).folder, files(f).name));
    A = double(A); w = A(:, :, 1); w(w == -32768) = NaN; w = w / 10000; nObs = A(:, :, 2);
    for k = 1:nSeg
        if isnan(x0(k)), continue, end
        px = x0(k) + s * nrm(k, 1); py = y0(k) + s * nrm(k, 2);
        [ci, ri] = worldToIntrinsic(R, px, py);
        prof = interp2(w, ci, ri, 'linear');
        obs  = interp2(nObs, ci, ri, 'nearest');
        P(k, f) = shorePos(s, prof, obs, cfg);
    end
end
colNames = sensor + "_" + string(yr);
T = array2table(P, 'VariableNames', cellstr(colNames));
T = [segs(:, {'segment', 'start_km', 'end_km', 'lat_mid', 'lon_mid'}), T];
writetable(T, fullfile(cfg.resultsDir, 'shoreline_positions.csv'));
fprintf('Shoreline found in %.0f%% of segment-years (Landsat) and %.0f%% (Sentinel-2).\n', ...
    100 * mean(~isnan(P(:, sensor == "landsat")), 'all'), 100 * mean(~isnan(P(:, sensor == "sentinel2")), 'all'));

% ---- Check 1: Landsat vs Sentinel-2 ------------------------------------------------------
both = intersect(yr(sensor == "landsat"), yr(sensor == "sentinel2"));
d = [];
for y = both(:)'
    d = [d; P(:, sensor == "sentinel2" & yr == y) - P(:, sensor == "landsat" & yr == y)]; %#ok<AGROW>
end
d = d(~isnan(d));
fprintf('\nCheck 1, Sentinel-2 (20 m) minus Landsat (30 m), same km and year, %d pairs:\n', numel(d));
fprintf('  mean %.1f m, median %.1f m, robust spread (1.48 x MAD) %.1f m, RMSE %.1f m\n', ...
    mean(d), median(d), 1.4826 * median(abs(d - median(d))), sqrt(mean(d.^2)));
big = abs(d - median(d)) > 100;
fprintf('  %d pairs (%.0f%%) differ by more than 100 m from the median: the two sensors picked a different\n', sum(big), 100 * mean(big));
fprintf('  water edge (river mouth, lagoon or surf). Without them: RMSE %.1f m\n', sqrt(mean(d(~big).^2)));

% ---- Rates (Landsat, the long record) -------------------------------------------------
L = P(:, sensor == "landsat"); ly = yr(sensor == "landsat");
lrr = nan(nSeg, 1); lrrSE = nan(nSeg, 1); epr = nan(nSeg, 1); nYr = zeros(nSeg, 1); span = nan(nSeg, 1);
for k = 1:nSeg
    v = ~isnan(L(k, :));
    nYr(k) = sum(v);
    if nYr(k) < cfg.minShoreYears || (max(ly(v)) - min(ly(v))) < 20, continue, end
    X = [ones(sum(v), 1), ly(v)']; b = X \ L(k, v)';
    res = L(k, v)' - X * b;
    lrr(k) = b(2);                                           % position grows seaward, so a negative slope = erosion
    lrrSE(k) = sqrt(sum(res.^2) / (sum(v) - 2) / sum((ly(v) - mean(ly(v))).^2));
    first = find(v, 1); last = find(v, 1, 'last');
    epr(k) = (L(k, last) - L(k, first)) / (ly(last) - ly(first));
    span(k) = ly(last) - ly(first);
end
% sign convention as in the assessment: negative = erosion (shoreline moving landward)
R2 = readtable(fullfile(cfg.resultsDir, 'm2_ladder_by_km.csv'));
out = segs(:, {'segment', 'start_km', 'end_km', 'lat_mid', 'lon_mid'});
out.years_used = nYr; out.span_years = span;
out.lrr_m_yr = lrr; out.lrr_se_m_yr = lrrSE; out.epr_m_yr = epr;
out.assessment_rate_m_yr = R2.measured_rate_m_yr;
out.dem_dist_to_shore_m = R2.dist_to_shore_m;
y20 = P(:, sensor == "landsat" & yr == 2020);
out.landsat2020_dist_m = y20;

% Very fast seaward advance is not natural beach growth on this coast; it
% marks land made by people (sand filling for Eko Atlantic, the Lekki port
% and similar works). Those km are flagged and left out of the summary and
% of check 2, so they do not hide erosion elsewhere.
built = lrr > cfg.reclaimRate_m_yr;
out.flag = repmat("", nSeg, 1); out.flag(built) = "seaward advance > " + cfg.reclaimRate_m_yr + " m/yr (likely reclaimed land)";
writetable(out, fullfile(cfg.resultsDir, 'shoreline_rates.csv'));
if any(built)
    fprintf('\nFlagged as likely reclaimed land (rate above +%g m/yr): km %s\n', cfg.reclaimRate_m_yr, ...
        strjoin(string(segs.start_km(built))', ', '));
end
lrrAll = lrr; lrr(built) = NaN;
fprintf('\nShoreline change 1984-2025 from Landsat (m/yr, negative = erosion), %d km with a rate (flagged km left out):\n', sum(~isnan(lrr)));
fprintf('  median %.2f, 10th to 90th percentile %.2f to %.2f; km eroding faster than 1 m/yr: %d\n', ...
    median(lrr, 'omitnan'), prctile(lrr, 10), prctile(lrr, 90), sum(lrr < -1));

% ---- Check 2: against the assessments' own measurements ----------------------------------
% The per-km assessment rate used in run_m2 is coarse: Section 1 gives
% bands of rates over several km, and Section 2 gives one rate per
% community, which run_m2 spreads to the nearest km. A km-by-km
% correlation with that step function says little, so the check is done
% where the assessments actually measured, over their own period
% (end point rate 1986-2024, DSAS):
%   2a. Section 2: each community, our 1986-2024 end point rate at the
%       nearest road km against the assessment's value.
%   2b. Section 1: each band, the median of our rates over the km in the
%       band, and whether it falls inside the band's stated range.
e86 = L(:, ly == 1986); e24 = L(:, ly == 2024);
epr8624 = (e24 - e86) / (2024 - 1986); epr8624(built) = NaN;
out.epr_1986_2024_m_yr = epr8624;
writetable(out, fullfile(cfg.resultsDir, 'shoreline_rates.csv'));
fprintf('\nCheck 2a, Section 2 communities, end point rate 1986-2024 (m/yr, negative = erosion):\n');
fprintf('  %-14s %6s %10s %10s\n', 'community', 'km', 'assessment', 'ours');
Pl = readtable(fullfile(cfg.osmDir, 'places.csv'), 'TextType', 'string');
Pl = Pl(~isnan(Pl.lon), :);
a2 = nan(height(Pl), 1); o2 = a2;
for j = 1:height(Pl)
    [~, k] = min(abs(segs.lon_mid - Pl.lon(j)) + 1e9 * (mid < 47.5));
    a2(j) = Pl.epr_m_yr(j); o2(j) = epr8624(k);
    fprintf('  %-14s %6g %10.2f %10.2f\n', Pl.community(j), segs.start_km(k), a2(j), o2(j));
end
c = ~isnan(o2);
fprintf('  %d communities: median difference (ours - assessment) %.2f m/yr, correlation r = %.2f, same direction %d of %d\n', ...
    sum(c), median(o2(c) - a2(c)), corr(o2(c), a2(c)), sum(sign(o2(c)) == sign(a2(c))), sum(c));
B1 = readtable(fullfile(cfg.dataDir, 'esia', 'shoreline_rates_section1.csv'));
fprintf('\nCheck 2b, Section 1 bands (m/yr):\n');
fprintf('  %-12s %-14s %-16s %s\n', 'chainage', 'assessment', 'ours (median)', 'inside range?');
nIn = 0; nB = 0;
for b = 1:height(B1)
    if isnan(B1.epr_min_m_yr(b)), continue, end
    in = mid >= B1.from_km(b) & mid <= B1.to_km(b) & ~isnan(epr8624);
    if ~any(in), continue, end
    m = median(epr8624(in));
    ok2 = m >= B1.epr_min_m_yr(b) - 0.5 & m <= B1.epr_max_m_yr(b) + 0.5;   % 0.5 m/yr allowance for position error
    nB = nB + 1; nIn = nIn + ok2;
    fprintf('  %4.1f-%-6.1f %4g to %-7g %6.2f (%d km)      %s\n', B1.from_km(b), B1.to_km(b), ...
        B1.epr_min_m_yr(b), B1.epr_max_m_yr(b), m, sum(in), string(ok2));
end
fprintf('  %d of %d bands inside the stated range (within 0.5 m/yr)\n', nIn, nB);

% the old km-by-km comparison, kept for reference
c = ~isnan(lrr) & ~isnan(out.assessment_rate_m_yr);
fprintf('\n  (km by km against the spread-out rate used in run_m2: %d km, r = %.2f)\n', ...
    sum(c), corr(lrr(c), out.assessment_rate_m_yr(c)));

% ---- Check 3: shoreline distance vs the elevation model ----------------------------------
c3 = ~isnan(y20) & ~isnan(out.dem_dist_to_shore_m);
d3 = y20(c3) - out.dem_dist_to_shore_m(c3);
fprintf('\nCheck 3, Landsat 2020 distance minus DEM distance to the ocean edge, %d km: median %.0f m, robust spread %.0f m\n', ...
    sum(c3), median(d3), 1.4826 * median(abs(d3 - median(d3))));
fprintf('  (the DEM distance is to the closest 10%% of the km, ours is along the transect at the km centre)\n');

% ---- Figures ---------------------------------------------------------------------------------
fig = figure('Color', 'w', 'Position', [80 80 1150 420]);
ax = axes(fig); hold(ax, 'on');
if any(built)
    plot(ax, mid(built), min(lrrAll(built), 14.5), '^', 'Color', [0.5 0.5 0.5], 'MarkerSize', 5, ...
        'DisplayName', 'likely reclaimed land (drawn at the top if off the scale)');
end
errorbar(ax, mid, lrr, 1.96 * lrrSE, 'o', 'Color', [0 0.35 0.7], 'MarkerFaceColor', [0 0.35 0.7], ...
    'MarkerSize', 4, 'DisplayName', 'this project: Landsat 1984-2025, linear regression (95% interval)');
plot(ax, mid, out.assessment_rate_m_yr, 's', 'Color', [0.85 0.4 0], 'MarkerSize', 6, 'LineWidth', 1.2, ...
    'DisplayName', 'highway assessment (DSAS end point rate)');
yline(ax, 0, 'k-', 'HandleVisibility', 'off'); hold(ax, 'off'); grid(ax, 'on');
xlabel(ax, 'Chainage along the highway (km)'); ylabel(ax, 'Shoreline change (m/yr, negative = erosion)');
ylim(ax, [-15 15]);   % flagged km above this are drawn at the top edge
title(ax, 'Shoreline change rate at each road km: our Landsat measurement vs the assessment');
legend(ax, 'Location', 'southoutside', 'Orientation', 'horizontal');
exportgraphics(fig, fullfile(cfg.figDir, 'shoreline_rates.png'), 'Resolution', 200);

fig = figure('Color', 'w', 'Position', [80 80 1150 420]);
ax = axes(fig); hold(ax, 'on');
show = round(linspace(1, nSeg, 6));
cols = lines(numel(show));
for i = 1:numel(show)
    k = show(i);
    plot(ax, ly, L(k, :), 'o-', 'Color', cols(i, :), 'MarkerFaceColor', cols(i, :), 'MarkerSize', 3, ...
        'DisplayName', sprintf('km %g', segs.start_km(k)));
    plot(ax, yr(sensor == "sentinel2"), P(k, sensor == "sentinel2"), 's', 'Color', cols(i, :), ...
        'MarkerSize', 5, 'HandleVisibility', 'off');
end
hold(ax, 'off'); grid(ax, 'on');
xlabel(ax, 'Year'); ylabel(ax, 'Distance from road to shoreline (m)');
title(ax, 'Shoreline position through time at six road km (circles: Landsat, squares: Sentinel-2)');
legend(ax, 'Location', 'eastoutside');
exportgraphics(fig, fullfile(cfg.figDir, 'shoreline_timeseries.png'), 'Resolution', 200);
fprintf('\nSaved results/shoreline_positions.csv, shoreline_rates.csv and two figures.\n');

% -------------------------------------------------------------------------
function p = shorePos(s, prof, obs, cfg)
% Walk in from the sea end; first crossing below the threshold = shoreline.
p = NaN;
th = cfg.mndwiThreshold;
e = find(~isnan(prof), 1, 'last');                          % sea end = last sample with data
if isempty(e) || prof(e) < th, return, end                  % it must be water
prof = prof(1:e); obs = obs(1:e); s = s(1:e);
i = find(isnan(prof) | prof < th, 1, 'last');               % last land or gap sample, seen from the road side
if isempty(i), return, end
if isnan(prof(i)), return, end                              % gap before reaching land: no position
if obs(i) < cfg.minClearObs || obs(i + 1) < cfg.minClearObs, return, end
% linear interpolation between sample i (land) and i+1 (water)
p = s(i) + (th - prof(i)) / (prof(i + 1) - prof(i)) * (s(i + 1) - s(i));
end

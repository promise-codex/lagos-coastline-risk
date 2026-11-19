%RUN_M1_SINKING Step 2: IPCC AR6 sea level by year, with and without sinking land.
%   M0 here = connected bathtub driven by the AR6 sea-level curve for Lagos.
%   M1      = the same curve plus a uniform land sinking rate.
%   For every 1 km road segment and every coastal strip, the script finds
%   the first year it gets wet under each sea-level case and sinking rate,
%   and the gap in years between M1 and M0.
%
%   Water level above the elevation model's zero in year t:
%       h(t) = [SLR(t) - SLR(refYear)] + s * (t - refYear)
%   where SLR is the AR6 total sea-level change and s the sinking rate.
%   A uniform sinking rate lowers all land equally, which has the same
%   effect on a bathtub as raising the sea by the same amount, so one
%   flood-level map (flood_level_map.m) serves every case.

cfg = project_config();

% ---- 1. Flood-level map (slowest part, saved for later steps) ------------
flFile = fullfile(cfg.resultsDir, 'flood_level_map.mat');
if isfile(flFile)
    fprintf('Loading saved flood-level map.\n');
    S = load(flFile, 'FL', 'R', 'M', 'levels');
    FL = S.FL; R = S.R; M = S.M;
    if ~isequal(S.levels, cfg.floodLevels)
        error('run_m1:levels', 'cfg.floodLevels changed. Delete %s and run again.', flFile);
    end
else
    [Z, M, R] = load_dem(cfg);
    fprintf('Building the flood-level map at %d water levels (takes a few minutes)...\n', ...
        numel(cfg.floodLevels));
    tic
    FL = flood_level_map(Z, M, cfg.floodLevels, cfg);
    fprintf('Done in %.0f s.\n', toc);
    levels = cfg.floodLevels;
    save(flFile, 'FL', 'R', 'M', 'levels', '-v7.3');
end
[lat, lon] = geographicGrid(R);
cellA = cell_area_km2(R);

% ---- 2. AR6 sea-level curves ------------------------------------------------
C = readcell(cfg.slrFile, 'Sheet', 'Total');
hdr = C(1, :);
yearCols = find(cellfun(@(x) isnumeric(x) && ~isempty(x) && x > 1900, hdr));
arYears = cell2mat(hdr(yearCols));
nCase = size(cfg.slrCases, 1);
slr = zeros(nCase, numel(cfg.years));
caseNames = strings(nCase, 1);
for c = 1:nCase
    conf = cfg.slrCases{c, 1}; scen = cfg.slrCases{c, 2}; q = cfg.slrCases{c, 3};
    row = find(strcmp(C(:, 3), conf) & strcmp(C(:, 4), scen) & ...
               cellfun(@(x) isnumeric(x) && isequal(x, q), C(:, 5)));
    if numel(row) ~= 1
        error('run_m1:slr', 'Could not find one row for %s %s quantile %d.', conf, scen, q);
    end
    v = cell2mat(C(row, yearCols));
    slr(c, :) = interp1(arYears, v, cfg.years, 'linear');
    caseNames(c) = sprintf('%s_%s_q%d', scen, conf, q);
    fprintf('AR6 %-6s %-6s q%-2d: %.2f m by 2050, %.2f m by 2100 (vs 1995-2014)\n', ...
        scen, conf, q, interp1(cfg.years, slr(c,:), 2050), interp1(cfg.years, slr(c,:), 2100));
end
slrRef = slr(:, cfg.years == cfg.refYear);

% Water level h(t) for each case and sinking rate: [case x rate x year]
nRate = numel(cfg.subsidence_mm_yr);
h = zeros(nCase, nRate, numel(cfg.years));
for c = 1:nCase
    for r = 1:nRate
        h(c, r, :) = (slr(c, :) - slrRef(c)) + cfg.subsidence_mm_yr(r) / 1000 * (cfg.years - cfg.refYear);
    end
end
if max(h(:)) > max(cfg.floodLevels)
    warning('run_m1:range', ['Water level reaches %.2f m, above the top of cfg.floodLevels (%.2f m). ' ...
        'Cells above that count as never flooded.'], max(h(:)), max(cfg.floodLevels));
end
firstYear = @(needed, hc) firstYearReached(needed, squeeze(hc), cfg.years);

% ---- 3. Road: first year each 1 km segment gets wet -------------------------
H = load(fullfile(cfg.osmDir, 'highway_segments.mat'), 'segs', 'samples');
[I, J] = geographicToDiscrete(R, H.samples.lat, H.samples.lon);
use = ~isnan(I) & ~isnan(J) & H.samples.mapped(:);
fl = FL(sub2ind(size(FL), I(use), J(use)));
% Road points on water cells (bridges over creeks and lagoon arms) are left
% out: NaN is ignored by min, so the segment is judged by its land points.
fl = double(fl);
segOf = discretize(H.samples.chainage_km(use), [H.segs.start_km; H.segs.end_km(end)]);
nSeg = height(H.segs);
segLevel = accumarray(segOf, fl, [nSeg 1], @min, NaN);   % level at which any point is wet

road = H.segs(:, {'segment', 'start_km', 'end_km', 'lat_mid', 'lon_mid'});
road.wet_level_m = segLevel;
for c = 1:nCase
    for r = 1:nRate
        name = sprintf('year_%s_sink%gmm', caseNames(c), cfg.subsidence_mm_yr(r));
        name = char(matlab.lang.makeValidName(strrep(name, '.', 'p')));
        road.(name) = firstYear(segLevel, h(c, r, :));
    end
end
writetable(road, fullfile(cfg.resultsDir, 'm1_road_first_wet_year.csv'));

% ---- 4. Coastal strips: first year 10% of the strip is wet ------------------
ocean = (M == 1);
cellKm = sqrt(mean(cellA(:)));          % cells are close to square here
distKm = bwdist(ocean) * cellKm;
corridor = (M == 0) & distKm <= cfg.corridor_km;
kmPerDegLon = pi/180 * 6371 * cosd(mean(cfg.latlim));
stripEdges = cfg.lonlim(1) : cfg.strip_km / kmPerDegLon : cfg.lonlim(2) + cfg.strip_km / kmPerDegLon;
strip = discretize(lon, stripEdges);
inC = corridor & ~isnan(strip);
flC = double(FL(inC)); flC(isinf(flC)) = 1e6;
level10 = accumarray(strip(inC), flC, [numel(stripEdges) - 1, 1], @(x) prctile(x, 10), NaN);
has = ~isnan(level10);
strips = table(find(has), stripEdges(find(has))', stripEdges(find(has) + 1)', level10(has), ...
    'VariableNames', {'strip', 'lon_west', 'lon_east', 'level_10pct_wet_m'});
strips.level_10pct_wet_m(strips.level_10pct_wet_m >= 1e6) = Inf;
for c = 1:nCase
    for r = 1:nRate
        name = sprintf('year_%s_sink%gmm', caseNames(c), cfg.subsidence_mm_yr(r));
        name = char(matlab.lang.makeValidName(strrep(name, '.', 'p')));
        strips.(name) = firstYear(strips.level_10pct_wet_m, h(c, r, :));
    end
end
writetable(strips, fullfile(cfg.resultsDir, 'm1_corridor_first_wet_year.csv'));

% ---- 5. Summary ---------------------------------------------------------------
fprintf('\nRoad: number of 1 km segments (of %d) with some wet length\n', sum(~isnan(segLevel)));
fprintf('%-24s %-12s %8s %8s %8s\n', 'Sea-level case', 'Sinking', 'by 2050', 'by 2100', 'by 2150');
for c = 1:nCase
    for r = 1:nRate
        yr = firstYear(segLevel, h(c, r, :));
        fprintf('%-24s %5.1f mm/yr %8d %8d %8d\n', caseNames(c), cfg.subsidence_mm_yr(r), ...
            sum(yr <= 2050), sum(yr <= 2100), sum(yr <= 2150));
    end
end

fprintf('\nWhen the first road segment gets wet, and when 10 segments are wet:\n');
for c = 1:nCase
    for r = 1:nRate
        yr = sort(firstYear(segLevel, h(c, r, :)));
        fprintf('%-24s %5.1f mm/yr: first %s, tenth %s\n', caseNames(c), cfg.subsidence_mm_yr(r), ...
            yearText(yr(1)), yearText(yr(min(10, numel(yr)))));
    end
end

% ---- 6. Figure: first wet year along the road -------------------------------
c = find(strcmp(cfg.slrCases(:, 2), 'ssp245') & strcmp(cfg.slrCases(:, 1), 'medium'), 1);
fig = figure('Color', 'w', 'Position', [100 100 1100 420]);
ax = axes(fig); hold(ax, 'on');
cols = lines(nRate);
for r = 1:nRate
    yr = firstYear(segLevel, h(c, r, :));
    plot(ax, road.start_km + 0.5, yr, 'o', 'Color', cols(r, :), 'MarkerFaceColor', cols(r, :), ...
        'MarkerSize', 4, 'DisplayName', sprintf('%g mm/yr sinking', cfg.subsidence_mm_yr(r)));
end
hold(ax, 'off');
ylim(ax, [cfg.refYear max(cfg.years)]);
xlabel(ax, 'Chainage along the highway (km, from the westernmost mapped point)');
ylabel(ax, 'First year with some wet length');
title(ax, sprintf(['M0 vs M1: first year each 1 km road segment is reached by the sea ' ...
    '(AR6 %s median; segments never reached by %d not shown)'], cfg.slrCases{c, 2}, max(cfg.years)));
legend(ax, 'Location', 'southoutside', 'Orientation', 'horizontal');
grid(ax, 'on');
exportgraphics(fig, fullfile(cfg.figDir, 'm1_road_first_wet_year.png'), 'Resolution', 200);
fprintf('\nSaved tables and figure to %s\n', cfg.resultsDir);

% -------------------------------------------------------------------------
function yr = firstYearReached(needed, hc, years)
% First year the water level hc reaches each needed level (Inf if never).
yr = inf(size(needed));
for i = 1:numel(needed)
    if isnan(needed(i)), yr(i) = NaN; continue, end
    k = find(hc >= needed(i), 1);
    if ~isempty(k), yr(i) = years(k); end
end
end

function t = yearText(y)
if isinf(y) || isnan(y), t = 'not by 2150'; else, t = sprintf('%d', y); end
end

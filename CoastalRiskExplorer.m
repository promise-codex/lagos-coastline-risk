function CoastalRiskExplorer()
%COASTALRISKEXPLORER Interactive app: which parts of the Lagos coastal highway the sea reaches, and when.
%   Choose the method (M0 to M3), the IPCC scenario and percentile, the
%   land sinking rate, the Bruun factor and a year. The map colours each
%   1 km of the route by whether it is reached by that year, and the chart
%   shows how many km are reached over time for the chosen settings and
%   for the bathtub method (M0) used in the assessment.
%
%   Needs the results of run_m3_extremes and run_m2_shoreline.

cfg = project_config();
D = loadData(cfg);

fig = uifigure('Name', 'Lagos Coastal Highway: Sea Reach Explorer', 'Position', [60 60 1250 720]);
gl = uigridlayout(fig, [1 2]); gl.ColumnWidth = {300, '1x'};
ctl = uigridlayout(gl, [16 1]); ctl.RowHeight = repmat({'fit'}, 1, 16);
right = uigridlayout(gl, [2 1]); right.RowHeight = {'1.4x', '1x'};

uilabel(ctl, 'Text', 'Method', 'FontWeight', 'bold');
ddMethod = uidropdown(ctl, 'Items', {'M0 bathtub (assessment approach)', 'M1 + land sinking', ...
    'M2 + moving beach', 'M3 + ordinary high tide', 'M3 + 1-year storm', 'M3 + 10-year storm', ...
    'M3 + 100-year storm'}, 'Value', 'M3 + ordinary high tide');
uilabel(ctl, 'Text', 'IPCC AR6 scenario', 'FontWeight', 'bold');
ddScen = uidropdown(ctl, 'Items', {'ssp126', 'ssp245', 'ssp585'}, 'Value', 'ssp245');
uilabel(ctl, 'Text', 'Sea-level percentile', 'FontWeight', 'bold');
ddQ = uidropdown(ctl, 'Items', {'5', '17', '50', '83', '95'}, 'Value', '50');
lblSink = uilabel(ctl, 'Text', 'Land sinking: 11.4 mm/yr', 'FontWeight', 'bold');
slSink = uislider(ctl, 'Limits', [0 40], 'Value', 11.4, 'MajorTicks', 0:10:40);
lblB = uilabel(ctl, 'Text', 'Bruun factor: 50 m per m', 'FontWeight', 'bold');
slB = uislider(ctl, 'Limits', [0 100], 'Value', 50, 'MajorTicks', 0:25:100);
lblYear = uilabel(ctl, 'Text', 'Year: 2050', 'FontWeight', 'bold');
slYear = uislider(ctl, 'Limits', [2020 2150], 'Value', 2050, 'MajorTicks', 2020:30:2140);
txt = uitextarea(ctl, 'Editable', 'off', 'Value', {''});
uilabel(ctl, 'Text', 'Sources: DeltaDTM, IPCC AR6, GTSM (Copernicus), OpenStreetMap, highway ESIA (2024).', ...
    'WordWrap', 'on', 'FontSize', 10);

gx = geoaxes(right); geobasemap(gx, 'satellite');
ax = uiaxes(right);

ctrls = {ddMethod, ddScen, ddQ, slSink, slB, slYear};
for k = 1:numel(ctrls)
    ctrls{k}.ValueChangedFcn = @(~, ~) refresh();
end
refresh();

    function refresh()
        sink = slSink.Value / 1000; B = slB.Value; yr = round(slYear.Value);
        lblSink.Text = sprintf('Land sinking: %.1f mm/yr', slSink.Value);
        lblB.Text = sprintf('Bruun factor: %.0f m per m', B);
        lblYear.Text = sprintf('Year: %d', yr);
        method = ddMethod.Value;
        if startsWith(method, 'M0'), sink = 0; end     % the bathtub method has no sinking
        slr = D.slr.(ddScen.Value)(str2double(ddQ.Value) == D.q, :);
        first = firstYears(D, cfg, slr, sink, B, method);
        firstM0 = firstYears(D, cfg, D.slr.(ddScen.Value)(D.q == 50, :), 0, 0, 'M0');

        reached = first <= yr;
        cla(gx); hold(gx, 'on');
        for k = 1:height(D.segs)
            seg = D.samples.chainage_km >= D.segs.start_km(k) & D.samples.chainage_km <= D.segs.end_km(k);
            if reached(k), c = [0.9 0.1 0.1]; else, c = [0.2 0.9 0.3]; end
            geoplot(gx, D.samples.lat(seg), D.samples.lon(seg), '-', 'Color', c, 'LineWidth', 4);
        end
        hold(gx, 'off');
        geolimits(gx, [6.36 6.50], [3.40 4.40]);
        title(gx, sprintf('%s, %s p%s: %d of %d km reached by %d (red)', method, ddScen.Value, ...
            ddQ.Value, sum(reached), numel(reached), yr));

        yrs = cfg.years;
        n = arrayfun(@(y) sum(first <= y), yrs);
        n0 = arrayfun(@(y) sum(firstM0 <= y), yrs);
        plot(ax, yrs, n, 'r-', 'LineWidth', 2, 'DisplayName', 'chosen settings'); hold(ax, 'on');
        plot(ax, yrs, n0, 'k--', 'LineWidth', 1.5, 'DisplayName', 'M0 bathtub, median, no sinking');
        xline(ax, yr, ':', 'HandleVisibility', 'off'); hold(ax, 'off');
        grid(ax, 'on'); xlim(ax, [2020 2150]); ylim(ax, [0 height(D.segs)]);
        xlabel(ax, 'Year'); ylabel(ax, 'Road km reached');
        legend(ax, 'Location', 'northwest');

        f = min(first);
        if isinf(f), fs = 'not by 2150'; else, fs = sprintf('%d', f); end
        txt.Value = {sprintf('First km reached: %s', fs), ...
                     sprintf('Reached by 2050: %d km', sum(first <= 2050)), ...
                     sprintf('Reached by 2100: %d km', sum(first <= 2100)), ...
                     sprintf('M0 bathtub by 2100: %d km', sum(firstM0 <= 2100))};
    end
end

% -------------------------------------------------------------------------
function D = loadData(cfg)
T3 = readtable(fullfile(cfg.resultsDir, 'm3_road_first_wet_year.csv'));
T2 = readtable(fullfile(cfg.resultsDir, 'm2_ladder_by_km.csv'));
G  = readtable(fullfile(cfg.dataDir, 'gtsm', 'gtsm_lagos_stations.csv'));
H  = load(fullfile(cfg.osmDir, 'highway_segments.mat'), 'segs', 'samples');
D.segs = H.segs; D.samples = H.samples;
[~, nearest] = min(abs(T3.lon_mid - G.lon'), [], 2);
D.event = struct('tide', G.MHHW_m(nearest), 'rp1', G.rp1_m(nearest), ...
                 'rp10', G.rp10_m(nearest), 'rp100', G.rp100_m(nearest));
D.lvlAny = T3.flood_level_any_m; D.lvlOcean = T3.flood_level_ocean_m;
D.dist = T2.dist_to_shore_m;
D.r = min(T2.measured_rate_m_yr, 0);
D.eroKnown = ~isnan(D.r) & ~isnan(D.dist); D.r(~D.eroKnown) = 0;
C = readcell(cfg.slrFile, 'Sheet', 'Total');
hdr = C(1, :);
yearCols = find(cellfun(@(x) isnumeric(x) && ~isempty(x) && x > 1900, hdr));
arYears = cell2mat(hdr(yearCols));
D.q = [5 17 50 83 95];
for s = {'ssp126', 'ssp245', 'ssp585'}
    Q = zeros(numel(D.q), numel(cfg.years));
    for i = 1:numel(D.q)
        row = find(strcmp(C(:, 3), 'medium') & strcmp(C(:, 4), s{1}) & ...
                   cellfun(@(x) isnumeric(x) && isequal(x, D.q(i)), C(:, 5)));
        Q(i, :) = interp1(arYears, cell2mat(C(row, yearCols)), cfg.years);
    end
    D.slr.(s{1}) = Q;
end
end

function first = firstYears(D, cfg, slr, sink, B, method)
years = cfg.years; t0 = cfg.refYear;
h = cummax((slr - slr(years == t0)) + sink * (years - t0));
lagoon = reachYear(D.lvlAny, h, years);
if startsWith(method, 'M0') || startsWith(method, 'M1')
    first = lagoon; return
end
retreat = -D.r .* (years - t0) + B * cumtrapz(years, max(gradient(slr, years) - 0.00325, 0));
ero = inf(height(D.segs), 1);
for k = find(D.eroKnown)'
    j = find(retreat(k, :) >= D.dist(k), 1);
    if ~isempty(j), ero(k) = years(j); end
end
first = min(lagoon, ero);
if startsWith(method, 'M3')
    if contains(method, 'high tide'), E = D.event.tide;
    elseif contains(method, '100-year'), E = D.event.rp100;
    elseif contains(method, '10-year'), E = D.event.rp10;
    else, E = D.event.rp1;
    end
    first = min(first, reachYear(D.lvlOcean - E, h, years));
end
end

function yr = reachYear(needed, h, years)
idx = sum(h(:)' < needed(:), 2) + 1;
yr = inf(numel(needed), 1);
ok = idx <= numel(years) & ~isnan(needed(:));
yr(ok) = years(idx(ok));
end

%CHECK_SPATIAL_SINKING Test the "one rate per road km" shortcut against a full map run.
%   run_m3_extremes gives each road km one sinking rate (the median of the
%   radar pixels near it) and moves the water level up by that rate. That
%   is exact only if the land between the road and the water sinks at the
%   same rate. Here the whole elevation model is lowered pixel by pixel
%   with the radar map instead, and the connected bathtub is re-run for
%   every year:
%       Z(t) = Z + v(x) * (t - refYear),   water level = SLR(t) - SLR(refYear)
%   v(x) is the radar vertical rate (positive = up) interpolated to the
%   elevation grid; where the radar has no pixel (water, dense vegetation)
%   the nearest measured pixel is used.
%   The first year each road km is reached (10% of its length wet) is then
%   compared with the M1 result of run_m3_extremes (AR6 SSP2-4.5 median,
%   mean sea level). Takes a few minutes (one flood per year).
%
%   Needs: run_m3_extremes run first.

cfg = project_config();
[Z, M, R] = load_dem(cfg);

% ---- Radar rate on the elevation grid ----------------------------------------
[A, Rg] = readgeoraster(cfg.insarFile);
v = double(A(:, :, 1));
[plat, plon] = geographicGrid(Rg);
ok = ~isnan(v);
F = scatteredInterpolant(plon(ok), plat(ok), v(ok), 'nearest', 'nearest');
[lat, lon] = geographicGrid(R);
V = single(F(lon, lat)) / 1000;                       % m/yr, positive = up
clear A v plat plon F

% ---- AR6 SSP2-4.5 median ------------------------------------------------------------
C = readcell(cfg.slrFile, 'Sheet', 'Total');
hdr = C(1, :);
yearCols = find(cellfun(@(x) isnumeric(x) && ~isempty(x) && x > 1900, hdr));
row = find(strcmp(C(:, 3), 'medium') & strcmp(C(:, 4), 'ssp245') & ...
           cellfun(@(x) isnumeric(x) && isequal(x, 50), C(:, 5)));
slr = interp1(cell2mat(hdr(yearCols)), cell2mat(C(row, yearCols)), cfg.years);
slr = slr - slr(cfg.years == cfg.refYear);

% ---- Road sample points -------------------------------------------------------------
H = load(fullfile(cfg.osmDir, 'highway_segments.mat'), 'segs', 'samples');
[I, J] = geographicToDiscrete(R, H.samples.lat, H.samples.lon);
use = ~isnan(I) & ~isnan(J) & H.samples.mapped(:);
idx = sub2ind(size(Z), I(use), J(use));
segOf = discretize(H.samples.chainage_km(use), [H.segs.start_km; H.segs.end_km(end)]);
onLand = M(idx) == 0 & ~isnan(segOf);                % water cells under bridges are left out
nSeg = height(H.segs);
nLand = accumarray(segOf(onLand), 1, [nSeg 1]);

% ---- One flood per year -----------------------------------------------------------------
yrFull = inf(nSeg, 1); yrFull(nLand == 0) = NaN;
wetEver = false(size(Z));
tic
for k = 1:numel(cfg.years)
    t = cfg.years(k);
    f = bathtub_flood(Z + V * (t - cfg.refYear), M, slr(k), cfg);
    wetEver = wetEver | f;                            % once reached, a cell stays reached
    wet = wetEver(idx) & onLand;
    share = accumarray(segOf(onLand), double(wet(onLand)), [nSeg 1]) ./ max(nLand, 1);
    newly = share >= cfg.segmentWetShare & isinf(yrFull);
    yrFull(newly) = t;
end
fprintf('Ran %d yearly floods in %.0f s.\n', numel(cfg.years), toc);

% ---- Compare with the per-km shortcut ------------------------------------------------
T3 = readtable(fullfile(cfg.resultsDir, 'm3_road_first_wet_year.csv'));
vn = T3.Properties.VariableNames;
yrSeg = T3.(vn{contains(vn, 'ssp245') & contains(vn, 'MeanSeaLevel') & contains(vn, 'sinkInSAR')});
both = ~isnan(yrFull) & ~isnan(yrSeg);
fprintf('\nM1 with measured sinking, SSP2-4.5 median: road km reached\n');
fprintf('%-32s %8s %8s %8s %8s\n', 'Method', 'by 2050', 'by 2100', 'by 2150', 'first');
fprintf('%-32s %8d %8d %8d %8d\n', 'one rate per km (shortcut)', sum(yrSeg <= 2050), sum(yrSeg <= 2100), ...
    sum(yrSeg <= 2150), min(yrSeg));
fprintf('%-32s %8d %8d %8d %8d\n', 'full map, pixel by pixel', sum(yrFull <= 2050), sum(yrFull <= 2100), ...
    sum(yrFull <= 2150), min(yrFull));
d = yrFull(both) - yrSeg(both);
fin = isfinite(d);
fprintf('Segments reached by 2150 in both: %d. Same year: %d. Median difference %.0f years, largest %.0f.\n', ...
    sum(fin), sum(d(fin) == 0), median(d(fin)), max(abs(d(fin))));
fprintf('Reached in one method only: %d segments.\n', sum(xor(isfinite(yrFull(both)), isfinite(yrSeg(both)))));

out = H.segs(:, {'segment', 'start_km', 'end_km'});
out.year_per_km_shortcut = yrSeg; out.year_full_map = yrFull;
writetable(out, fullfile(cfg.resultsDir, 'check_spatial_sinking.csv'));
fprintf('Saved results/check_spatial_sinking.csv\n');

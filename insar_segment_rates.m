function T = insar_segment_rates(cfg, makeFigures)
%INSAR_SEGMENT_RATES Measured land sinking rate for every 1 km of the highway.
%   T = insar_segment_rates(cfg) reads the vertical land motion map made
%   from Sentinel-1 radar (data/insar/lagos_vlm_s1_2017_2025.tif, see
%   insar/README_insar.md) and returns one row per road segment:
%     sink_mm_yr    sinking rate, mm per year, POSITIVE = land going down
%     sigma_mm_yr   1-sigma uncertainty of that rate (local part only)
%     n_pixels      radar pixels used
%     source        "measured", "measured (wider search)" or "filled"
%
%   How a segment gets its rate
%   1. Every good radar pixel (80 m, temporal coherence >= 0.5, land) is
%      given to the road segment whose nearest road point is closest.
%   2. Pixels within cfg.insarBuffer_m of the road are used. The segment
%      rate is their median, so a few odd pixels cannot decide it.
%   3. If fewer than cfg.insarMinPixels are found, the search is widened to
%      3 x cfg.insarBuffer_m. If there are still too few, the segment is
%      filled by straight-line interpolation along the road from its
%      measured neighbours ("filled").
%   Uncertainty: sigma^2 = (median pixel sigma)^2 + (robust spread of the
%   pixel rates)^2. The spread term is kept whole (not divided by the number
%   of pixels) because nearby pixels share errors and because the road may
%   behave like any of them. Filled segments add the spread of all measured
%   segment rates. The common GPS tie error (cfg.insarDatumSigma) is NOT in
%   sigma; it shifts every segment together and is drawn once per run in
%   run_uncertainty.
%
%   T = insar_segment_rates(cfg, true) also saves a map and a profile figure.

if nargin < 2, makeFigures = false; end
H = load(fullfile(cfg.osmDir, 'highway_segments.mat'), 'segs', 'samples');
segs = H.segs; nSeg = height(segs);

[A, Rg] = readgeoraster(cfg.insarFile);
A = double(A);
rate = A(:, :, 1); sig = A(:, :, 2);                % mm/yr, positive = up
[plat, plon] = geographicGrid(Rg);                  % pixel centres
ok = ~isnan(rate) & ~isnan(sig);
plat = plat(ok); plon = plon(ok); rate = rate(ok); sig = sig(ok);

% Road sample points (mapped part of the route only)
sLat = H.samples.lat(:); sLon = H.samples.lon(:); sCh = H.samples.chainage_km(:);
use = H.samples.mapped(:) & ~isnan(sLat) & ~isnan(sLon);
sLat = sLat(use); sLon = sLon(use); sCh = sCh(use);
sSeg = discretize(sCh, [segs.start_km; segs.end_km(end)]);

% Local flat coordinates in metres (error < 0.1% over this small area)
lat0 = mean(cfg.latlim);
mx = 1000 * 111.32 * cosd(lat0); my = 1000 * 110.57;
[idx, dist] = knnsearch([sLon * mx, sLat * my], [plon * mx, plat * my]);
pSeg = sSeg(idx);

sink = nan(nSeg, 1); sigma = nan(nSeg, 1); nPix = zeros(nSeg, 1);
source = repmat("filled", nSeg, 1);
radii = cfg.insarBuffer_m * [1 3];
labels = ["measured", "measured (wider search)"];
for k = 1:nSeg
    for j = 1:numel(radii)
        in = pSeg == k & dist <= radii(j);
        if sum(in) >= cfg.insarMinPixels
            v = rate(in);
            sink(k) = -median(v);
            sigma(k) = sqrt(median(sig(in))^2 + (1.4826 * median(abs(v - median(v))))^2);
            nPix(k) = sum(in);
            source(k) = labels(j);
            break
        end
    end
end

meas = ~isnan(sink);
mid = (segs.start_km + segs.end_km) / 2;
if sum(meas) < 2
    error('insar_segment_rates:none', 'Fewer than 2 road segments have radar pixels. Check cfg.insarFile.');
end
isFill = ~meas;
if any(isFill)
    first = find(meas, 1, 'first'); last = find(meas, 1, 'last');
    sink(isFill) = interp1(mid(meas), sink(meas), mid(isFill), 'linear');
    % beyond the measured ends hold the end value (no trend extrapolation)
    sink(isFill & mid < mid(first)) = sink(first);
    sink(isFill & mid > mid(last))  = sink(last);
    sigNb = interp1(mid(meas), sigma(meas), mid(isFill), 'nearest', 'extrap');
    sigma(isFill) = sqrt(sigNb.^2 + std(sink(meas))^2);
end

T = segs(:, {'segment', 'start_km', 'end_km', 'lat_mid', 'lon_mid'});
T.sink_mm_yr = sink; T.sigma_mm_yr = sigma; T.n_pixels = nPix; T.source = source;
writetable(T, fullfile(cfg.resultsDir, 'insar_segment_rates.csv'));

fprintf(['Radar sinking along the road: %d of %d km measured within %g m, %d with a wider ' ...
    'search, %d filled.\n'], sum(source == "measured"), nSeg, cfg.insarBuffer_m, ...
    sum(source == "measured (wider search)"), sum(isFill));
fprintf('  Segment sinking rate: median %.1f mm/yr, 10th to 90th percentile %.1f to %.1f mm/yr, fastest %.1f mm/yr (km %g)\n', ...
    median(sink), prctile(sink, 10), prctile(sink, 90), max(sink), segs.start_km(find(sink == max(sink), 1)));

if ~makeFigures, return, end

% ---- Map ----------------------------------------------------------------------
fig = figure('Color', 'w', 'Position', [80 80 1200 430]);
gx = geoaxes(fig); geobasemap(gx, 'grayland'); hold(gx, 'on');
geoscatter(gx, plat, plon, 4, rate, 'filled');
geoplot(gx, sLat, sLon, 'k-', 'LineWidth', 1.2);
hold(gx, 'off');
colormap(gx, flipud(redblue(256))); clim(gx, [-20 20]);
cb = colorbar(gx); cb.Label.String = 'Vertical land motion (mm/yr, negative = sinking)';
geolimits(gx, cfg.latlim, cfg.lonlim);
title(gx, 'Land motion measured by Sentinel-1 radar, 2017-2025 (tied to UNILAG GPS); black line = coastal highway');
exportgraphics(fig, fullfile(cfg.figDir, 'insar_sinking_map.png'), 'Resolution', 200);

% ---- Profile along the road -----------------------------------------------------
fig = figure('Color', 'w', 'Position', [80 80 1100 380]);
ax = axes(fig); hold(ax, 'on');
m1 = source == "measured"; m2 = source == "measured (wider search)";
errorbar(ax, mid(m1), sink(m1), sigma(m1), 'o', 'Color', [0 0.35 0.7], 'MarkerFaceColor', [0 0.35 0.7], ...
    'MarkerSize', 4, 'DisplayName', sprintf('measured within %g m', cfg.insarBuffer_m));
if any(m2)
    errorbar(ax, mid(m2), sink(m2), sigma(m2), 's', 'Color', [0.85 0.45 0], 'MarkerSize', 5, ...
        'DisplayName', sprintf('measured within %g m', 3 * cfg.insarBuffer_m));
end
if any(isFill)
    errorbar(ax, mid(isFill), sink(isFill), sigma(isFill), 'x', 'Color', [0.5 0.5 0.5], ...
        'DisplayName', 'filled from neighbours');
end
yline(ax, 0, 'k-', 'HandleVisibility', 'off');
yline(ax, 11.4, 'k:', '11.4 mm/yr (fastest 10% in a published 2015-2025 study)', 'HandleVisibility', 'off');
hold(ax, 'off'); grid(ax, 'on');
xlabel(ax, 'Chainage along the highway (km)');
ylabel(ax, 'Sinking rate (mm/yr, positive = down)');
title(ax, sprintf(['Measured sinking under each road km (median of radar pixels, error bar = local 1-sigma; ' ...
    'all values share a further \\pm%.1f mm/yr GPS tie error)'], cfg.insarDatumSigma));
legend(ax, 'Location', 'northwest');
exportgraphics(fig, fullfile(cfg.figDir, 'insar_road_profile.png'), 'Resolution', 200);
end

function c = redblue(n)
% Blue (negative) to white to red (positive); flipped above so sinking is red.
x = linspace(-1, 1, n)';
c = [min(1, 1 + x), 1 - abs(x), min(1, 1 - x)];
c = 0.15 + 0.85 * c;
end

%MAKE_SEGMENTS Build a single highway centreline and cut it into 1 km segments.
%   Uses the "Lagos Coastal Highway" ways saved by get_osm_features. The
%   road has two carriageways in places, so the pieces are merged into one
%   centreline by averaging latitude in narrow longitude bins (the road
%   runs roughly west to east along the coast). Chainage 0 is the
%   westernmost mapped point, which is close to, but not exactly, the
%   assessment's CH 0+000 at Ahmadu Bello Way, Victoria Island Annex.
%
%   Output: data/osm/highway_segments.mat with
%     centre   table of centreline points (lat, lon, chainage_km, gap)
%     segs     table of 1 km segments
%     samples  struct with points every 30 m along the road, for sampling grids

cfg = project_config();
S = load(fullfile(cfg.osmDir, 'osm_features.mat'), 'features');
f = S.features;

isRoad = strcmp({f.name}, 'Lagos Coastal Highway') & ...
         (contains({f.kind}, 'highway=trunk') | contains({f.kind}, 'highway=construction'));
road = f(isRoad);
fprintf('Using %d highway pieces.\n', numel(road));

lat = vertcat(road.lat);
lon = vertcat(road.lon);
ok  = ~isnan(lat) & ~isnan(lon);
lat = lat(ok); lon = lon(ok);

% ---- Merge carriageways into one centreline -------------------------------
binWidth = 0.002;                              % degrees of longitude (about 220 m)
edges = (floor(min(lon)/binWidth)*binWidth) : binWidth : (ceil(max(lon)/binWidth)*binWidth + binWidth);
[~, ~, bin] = histcounts(lon, edges);
nb = numel(edges) - 1;
cLon = edges(1:end-1)' + binWidth/2;
cLat = accumarray(bin, lat, [nb 1], @mean, NaN);

% Bins with no mapped road are gaps: fill by straight-line interpolation
gap = isnan(cLat);
cLat(gap) = interp1(cLon(~gap), cLat(~gap), cLon(gap), 'linear');
keep = ~isnan(cLat);                           % drops empty bins beyond the ends
cLat = cLat(keep); cLon = cLon(keep); gap = gap(keep);

% Light smoothing to remove zig-zag between the two carriageways
cLat = smoothdata(cLat, 'movmean', 3);

% ---- Chainage ---------------------------------------------------------------
E = wgs84Ellipsoid('meter');
step = distance(cLat(1:end-1), cLon(1:end-1), cLat(2:end), cLon(2:end), E);
ch = [0; cumsum(step)] / 1000;                 % km
centre = table(cLat, cLon, ch, gap, 'VariableNames', {'lat', 'lon', 'chainage_km', 'gap'});

totalKm = ch(end);
gapKm = sum(step(gap(1:end-1) | gap(2:end))) / 1000;
fprintf('Centreline length: %.2f km, of which %.2f km is interpolated across unmapped gaps.\n', totalKm, gapKm);

% ---- Sample points every 30 m (matches the 30 m elevation grid) ------------
sCh = (0:0.03:totalKm)';
samples.chainage_km = sCh;
samples.lat = interp1(ch, cLat, sCh);
samples.lon = interp1(ch, cLon, sCh);

% ---- 1 km segments ----------------------------------------------------------
startKm = (0:floor(totalKm))';
startKm = startKm(startKm < totalKm);
endKm = min(startKm + 1, totalKm);
midKm = (startKm + endKm) / 2;
segs = table((1:numel(startKm))', startKm, endKm, ...
    interp1(ch, cLat, midKm), interp1(ch, cLon, midKm), ...
    'VariableNames', {'segment', 'start_km', 'end_km', 'lat_mid', 'lon_mid'});

save(fullfile(cfg.osmDir, 'highway_segments.mat'), 'centre', 'segs', 'samples');
writetable(segs, fullfile(cfg.resultsDir, 'highway_segments.csv'));

% ---- Map ----------------------------------------------------------------------
fig = figure('Color', 'w', 'Position', [100 100 1100 450]);
gx = geoaxes(fig);
geobasemap(gx, 'satellite');
hold(gx, 'on');
for k = 1:numel(road)
    geoplot(gx, road(k).lat, road(k).lon, '-', 'Color', [1 1 0], 'LineWidth', 1);
end
geoplot(gx, centre.lat, centre.lon, 'c-', 'LineWidth', 2);
geoplot(gx, centre.lat(centre.gap), centre.lon(centre.gap), 'r.', 'MarkerSize', 10);
every5 = segs.start_km(mod(segs.start_km, 5) == 0);
for k = 1:numel(every5)
    i = segs.segment(segs.start_km == every5(k));
    text(gx, segs.lat_mid(i), segs.lon_mid(i), sprintf(' %d km', every5(k)), ...
        'Color', 'w', 'FontWeight', 'bold');
end
hold(gx, 'off');
title(gx, sprintf('Highway centreline (cyan), unmapped gaps (red), %.1f km', totalKm));
exportgraphics(fig, fullfile(cfg.figDir, 'highway_segments.png'), 'Resolution', 200);
fprintf('Saved %d segments to %s\n', height(segs), fullfile(cfg.osmDir, 'highway_segments.mat'));

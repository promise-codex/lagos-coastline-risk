%MAKE_SEGMENTS Build the highway centreline and cut it into 1 km segments.
%   Uses the coastal highway ways saved by get_osm_features. The
%   road has two carriageways in places, so the pieces are merged into one
%   centreline by averaging latitude in narrow longitude bins (the road
%   runs roughly west to east along the coast).
%
%   OpenStreetMap does not yet map the whole road. Short holes (up to
%   maxFillKm) are bridged with a straight line. Longer gaps are only used
%   to carry the chainage across (straight line, so chainage beyond a gap
%   is approximate) and every point in them is flagged as unmapped. Road
%   results are only reported for mapped points. For the unmapped parts,
%   use the coastal corridor results from run_m0_bathtub instead.
%
%   Chainage 0 is the westernmost mapped point, which is close to, but not
%   exactly, the assessment's CH 0+000 at Ahmadu Bello Way.
%
%   Output: data/osm/highway_segments.mat with
%     centre   table of centreline points (lat, lon, chainage_km, mapped)
%     segs     table of 1 km segments, with the share of each that is mapped
%     samples  struct with points every 30 m along the road (mapped flag included)
%     stretches table of continuous mapped stretches

cfg = project_config();
S = load(fullfile(cfg.osmDir, 'osm_features.mat'), 'features');
f = S.features;

% Names seen so far: "Lagos Coastal Highway"; further east OSM may use
% "Lagos-Calabar Coastal Highway", so match either
isRoad = ~cellfun(@isempty, regexpi({f.name}, 'coastal highway|calabar', 'once')) & ...
         (contains({f.kind}, 'highway=trunk') | contains({f.kind}, 'highway=construction'));
road = f(isRoad);
fprintf('Using %d highway pieces, named: %s\n', numel(road), strjoin(unique({road.name}), ' | '));

% Fill in points along each piece (about every 50 m). Some pieces have
% vertices kilometres apart; the straight line between two vertices is
% still part of the mapped road, so it counts as mapped.
lat = []; lon = [];
for k = 1:numel(road)
    [la, lo] = densify(road(k).lat, road(k).lon, 0.0005);
    lat = [lat; la]; lon = [lon; lo]; %#ok<AGROW>
end
% Keep only the study area. One OSM piece runs all the way to Calabar,
% and the download returns the whole piece, not just the part in the box.
ok  = ~isnan(lat) & ~isnan(lon) & ...
      lat >= cfg.latlim(1) & lat <= cfg.latlim(2) & ...
      lon >= cfg.lonlim(1) & lon <= cfg.lonlim(2);
lat = lat(ok); lon = lon(ok);

% ---- Merge carriageways into one centreline -------------------------------
binWidth  = 0.002;                              % degrees of longitude (about 220 m)
maxFillKm = 0.5;                                % holes up to this length are bridged
edges = (floor(min(lon)/binWidth)*binWidth) : binWidth : (ceil(max(lon)/binWidth)*binWidth + binWidth);
[~, ~, bin] = histcounts(lon, edges);
nb   = numel(edges) - 1;
cLon = edges(1:end-1)' + binWidth/2;
cLat = accumarray(bin, lat, [nb 1], @mean, NaN);

empty  = isnan(cLat);
cLat(empty) = interp1(cLon(~empty), cLat(~empty), cLon(empty), 'linear');
keep = ~isnan(cLat);                            % drops empty bins beyond the ends
cLat = cLat(keep); cLon = cLon(keep); empty = empty(keep);

% Light smoothing to remove zig-zag between the two carriageways
% (only mapped bins are smoothed, so gap lines stay straight)
sm = smoothdata(cLat, 'movmean', 3);
cLat(~empty) = sm(~empty);

% ---- Chainage ---------------------------------------------------------------
E = wgs84Ellipsoid('meter');
step = distance(cLat(1:end-1), cLon(1:end-1), cLat(2:end), cLon(2:end), E);
ch = [0; cumsum(step)] / 1000;                  % km

% Empty runs shorter than maxFillKm count as mapped (small holes in OSM)
mapped = ~empty;
runs = findRuns(empty);
for r = 1:size(runs, 1)
    a = max(runs(r,1) - 1, 1); b = min(runs(r,2) + 1, numel(ch));
    if ch(b) - ch(a) <= maxFillKm
        mapped(runs(r,1):runs(r,2)) = true;
    end
end
centre = table(cLat, cLon, ch, mapped, 'VariableNames', {'lat', 'lon', 'chainage_km', 'mapped'});

% Continuous mapped stretches
mr = findRuns(mapped);
stretches = table(ch(mr(:,1)), ch(mr(:,2)), cLon(mr(:,1)), cLon(mr(:,2)), ...
    'VariableNames', {'from_km', 'to_km', 'from_lon', 'to_lon'});
stretches.length_km = stretches.to_km - stretches.from_km;

totalKm  = ch(end);
mappedKm = sum(stretches.length_km);
fprintf('Centreline from %.3f E to %.3f E: %.2f km, of which %.2f km is mapped in OpenStreetMap.\n', ...
    cLon(1), cLon(end), totalKm, mappedKm);
fprintf('Mapped stretches:\n');
disp(stretches)

% ---- Sample points every 30 m (matches the 30 m elevation grid) ------------
sCh = (0:0.03:totalKm)';
samples.chainage_km = sCh;
samples.lat    = interp1(ch, cLat, sCh);
samples.lon    = interp1(ch, cLon, sCh);
samples.mapped = interp1(ch, double(mapped), sCh, 'nearest') > 0.5;

% ---- 1 km segments ----------------------------------------------------------
startKm = (0:floor(totalKm))';
startKm = startKm(startKm < totalKm);
endKm = min(startKm + 1, totalKm);
midKm = (startKm + endKm) / 2;
segOf = discretize(sCh, [startKm; endKm(end)]);
mappedFrac = accumarray(segOf, double(samples.mapped), [numel(startKm) 1], @mean, 0);
segs = table((1:numel(startKm))', startKm, endKm, ...
    interp1(ch, cLat, midKm), interp1(ch, cLon, midKm), mappedFrac, ...
    'VariableNames', {'segment', 'start_km', 'end_km', 'lat_mid', 'lon_mid', 'mapped_frac'});

save(fullfile(cfg.osmDir, 'highway_segments.mat'), 'centre', 'segs', 'samples', 'stretches');
writetable(segs, fullfile(cfg.resultsDir, 'highway_segments.csv'));
writetable(stretches, fullfile(cfg.resultsDir, 'highway_mapped_stretches.csv'));

% ---- Map ----------------------------------------------------------------------
fig = figure('Color', 'w', 'Position', [100 100 1200 450]);
gx = geoaxes(fig);
geobasemap(gx, 'satellite');
hold(gx, 'on');
for k = 1:numel(road)
    geoplot(gx, road(k).lat, road(k).lon, '-', 'Color', [1 1 0], 'LineWidth', 1);
end
gLat = centre.lat; gLat(~centre.mapped) = NaN;     % break the line at gaps
geoplot(gx, gLat, centre.lon, 'c-', 'LineWidth', 2.5);
geoplot(gx, centre.lat(~centre.mapped), centre.lon(~centre.mapped), 'r.', 'MarkerSize', 6);
every5 = segs.start_km(mod(segs.start_km, 5) == 0);
for k = 1:numel(every5)
    i = segs.segment(segs.start_km == every5(k));
    text(gx, segs.lat_mid(i), segs.lon_mid(i), sprintf(' %d', every5(k)), ...
        'Color', 'w', 'FontWeight', 'bold');
end
hold(gx, 'off');
geolimits(gx, cfg.latlim, cfg.lonlim);
title(gx, sprintf(['Highway in OpenStreetMap: mapped (cyan, %.1f km), straight line across gaps (red), ' ...
    'km labels every 5 km'], mappedKm));
exportgraphics(fig, fullfile(cfg.figDir, 'highway_segments.png'), 'Resolution', 200);
fprintf('Saved %d segments (%d fully mapped) to %s\n', height(segs), sum(segs.mapped_frac == 1), ...
    fullfile(cfg.osmDir, 'highway_segments.mat'));

% -------------------------------------------------------------------------
function [la, lo] = densify(lat, lon, maxStepDeg)
% Add points along each straight piece so no two points are more than
% maxStepDeg apart. NaN breaks between parts are kept.
la = []; lo = [];
for i = 1:numel(lat) - 1
    if any(isnan([lat(i) lat(i+1) lon(i) lon(i+1)]))
        continue
    end
    n = max(1, ceil(hypot(lat(i+1) - lat(i), lon(i+1) - lon(i)) / maxStepDeg));
    t = (0:n-1)' / n;
    la = [la; lat(i) + t * (lat(i+1) - lat(i))]; %#ok<AGROW>
    lo = [lo; lon(i) + t * (lon(i+1) - lon(i))]; %#ok<AGROW>
end
if ~isempty(lat) && ~isnan(lat(end))
    la = [la; lat(end)]; lo = [lo; lon(end)];
end
end

function runs = findRuns(tf)
% Start and end index of each run of true values in a logical vector.
d = diff([false; tf(:); false]);
runs = [find(d == 1), find(d == -1) - 1];
end

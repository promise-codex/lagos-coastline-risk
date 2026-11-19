%RUN_M0_BATHTUB First test of method M0 (connected bathtub) for the Lagos coast.
%   Loads DeltaDTM, floods it at each sea-level value in cfg.slr_m, and
%   saves a table of flooded land area plus one map per value.

cfg = project_config();
[Z, M, R] = load_dem(cfg);
cellA = cell_area_km2(R);
[lat, lon] = geographicGrid(R);

nLevels  = numel(cfg.slr_m);
area_km2 = zeros(nLevels, 1);
floodMaps = false([size(Z) nLevels]);

for k = 1:nLevels
    floodMaps(:,:,k) = bathtub_flood(Z, M, cfg.slr_m(k), cfg);
    area_km2(k) = sum(cellA(floodMaps(:,:,k)), 'all');
    fprintf('Sea level +%.2f m: %.2f km^2 of land flooded\n', cfg.slr_m(k), area_km2(k));
end

results = table(cfg.slr_m(:), area_km2, ...
    'VariableNames', {'SeaLevelRise_m', 'FloodedLand_km2'});
writetable(results, fullfile(cfg.resultsDir, 'm0_bathtub_area.csv'));
save(fullfile(cfg.resultsDir, 'm0_bathtub.mat'), 'floodMaps', 'R', 'cfg', 'results');

% ---- Maps -----------------------------------------------------------------
% Background: elevation (land only), grey water, red flooded land
for k = 1:nLevels
    fig = figure('Color', 'w', 'Position', [100 100 1100 450]);
    ax = axes(fig);
    landZ = Z;
    if ~isempty(M)
        landZ(M ~= 0) = NaN;
    end
    imagesc(ax, lon(1,:), lat(:,1), landZ, 'AlphaData', ~isnan(landZ));
    set(ax, 'YDir', 'normal', 'Color', [0.85 0.88 0.92]);
    colormap(ax, parula);
    clim(ax, [0 10]);
    cb = colorbar(ax);
    cb.Label.String = 'Ground elevation (m above mean sea level, EGM2008)';
    hold(ax, 'on');
    red = cat(3, ones(size(Z)), zeros(size(Z)), zeros(size(Z)));
    image(ax, lon(1,:), lat(:,1), red, 'AlphaData', 0.7 * double(floodMaps(:,:,k)));
    hold(ax, 'off');
    axis(ax, 'image');
    xlabel(ax, 'Longitude (degrees E)');
    ylabel(ax, 'Latitude (degrees N)');
    title(ax, sprintf('M0 bathtub: land below +%.1f m and connected to the sea (red), %.1f km^2', ...
        cfg.slr_m(k), area_km2(k)));
    exportgraphics(fig, fullfile(cfg.figDir, sprintf('m0_bathtub_%03dcm.png', round(100*cfg.slr_m(k)))), ...
        'Resolution', 200);
end

% ---- Road exposure per 1 km segment (if make_segments has been run) ------
% Only points where OpenStreetMap maps the road are used. Segments with no
% mapped points get NaN (shown blank in the figure).
segFile = fullfile(cfg.osmDir, 'highway_segments.mat');
if isfile(segFile)
    H = load(segFile, 'segs', 'samples');
    [I, J] = geographicToDiscrete(R, H.samples.lat, H.samples.lon);
    use = ~isnan(I) & ~isnan(J) & H.samples.mapped(:);
    idx = sub2ind(size(Z), I(use), J(use));
    sCh = H.samples.chainage_km(use);
    segOf = discretize(sCh, [H.segs.start_km; H.segs.end_km(end)]);
    nSeg = height(H.segs);
    frac = zeros(nSeg, nLevels);
    for k = 1:nLevels
        fk = floodMaps(:,:,k);
        wet = fk(idx);
        frac(:, k) = accumarray(segOf, double(wet), [nSeg 1], @mean, NaN);
    end
    names = cellstr(compose('flooded_frac_%03dcm', round(100*cfg.slr_m)));
    roadTable = [H.segs, array2table(frac, 'VariableNames', names)];
    writetable(roadTable, fullfile(cfg.resultsDir, 'm0_bathtub_road_segments.csv'));
    nMapped = sum(~isnan(frac(:,1)));
    for k = 1:nLevels
        fprintf('Sea level +%.2f m: %d of %d mapped road segments have some flooded length\n', ...
            cfg.slr_m(k), sum(frac(:,k) > 0), nMapped);
    end

    fig = figure('Color', 'w', 'Position', [100 100 1000 300]);
    ax = axes(fig);
    imagesc(ax, H.segs.start_km + 0.5, 1:nLevels, frac', 'AlphaData', ~isnan(frac'));
    set(ax, 'YDir', 'normal', 'YTick', 1:nLevels, ...
        'YTickLabel', compose('+%.1f m', cfg.slr_m), 'Color', [0.9 0.9 0.9]);
    colormap(ax, flipud(hot));
    clim(ax, [0 1]);
    cb = colorbar(ax);
    cb.Label.String = 'Share of segment length flooded';
    xlabel(ax, 'Chainage along the highway (km, from the westernmost mapped point)');
    ylabel(ax, 'Sea-level rise');
    title(ax, 'M0 bathtub: flooded share of each 1 km road segment (grey = road not mapped)');
    exportgraphics(fig, fullfile(cfg.figDir, 'm0_bathtub_road_segments.png'), 'Resolution', 200);
else
    fprintf('Run make_segments first to get results per road segment.\n');
end

% ---- Coastal corridor: land within cfg.corridor_km of the ocean ------------
% Covers the whole coast, including where the road is not mapped. The
% corridor is cut into alongshore strips of cfg.strip_km by longitude
% (the coast here runs close to west-east). Distance is measured in grid
% cells and converted to km with the mean cell size (cells are close to
% square at this latitude, within about 1 percent).
if ~isempty(M)
    ocean = (M == 1);
    [cellLatKm, cellLonKm] = cellSizeKm(R, mean(cfg.latlim));
    distKm = bwdist(ocean) * mean([cellLatKm cellLonKm]);
    corridor = (M == 0) & distKm <= cfg.corridor_km;

    kmPerDegLon = cellLonKm / cellExtentLon(R);
    stripDeg = cfg.strip_km / kmPerDegLon;
    stripEdges = cfg.lonlim(1) : stripDeg : cfg.lonlim(2) + stripDeg;
    strip = discretize(lon, stripEdges);
    nStrip = numel(stripEdges) - 1;

    inC = corridor & ~isnan(strip);
    corrArea = accumarray(strip(inC), cellA(inC), [nStrip 1]);
    floodArea = zeros(nStrip, nLevels);
    for k = 1:nLevels
        w = inC & floodMaps(:,:,k);
        floodArea(:, k) = accumarray(strip(w), cellA(w), [nStrip 1]);
    end
    has = corrArea > 0;
    stripTable = table(find(has), stripEdges(find(has))', stripEdges(find(has)+1)', corrArea(has), ...
        'VariableNames', {'strip', 'lon_west', 'lon_east', 'corridor_km2'});
    names = cellstr(compose('flooded_frac_%03dcm', round(100*cfg.slr_m)));
    stripTable = [stripTable, array2table(floodArea(has,:) ./ corrArea(has), 'VariableNames', names)];
    writetable(stripTable, fullfile(cfg.resultsDir, 'm0_bathtub_corridor_strips.csv'));
    fprintf('Corridor (land within %.1f km of the ocean): %.1f km^2 in %d strips of %.1f km\n', ...
        cfg.corridor_km, sum(corrArea), height(stripTable), cfg.strip_km);
    for k = 1:nLevels
        fprintf('Sea level +%.2f m: %.1f%% of the corridor flooded\n', cfg.slr_m(k), ...
            100 * sum(floodArea(:,k)) / sum(corrArea));
    end

    fig = figure('Color', 'w', 'Position', [100 100 1000 300]);
    ax = axes(fig);
    xMid = (stripTable.lon_west + stripTable.lon_east) / 2;
    imagesc(ax, xMid, 1:nLevels, stripTable{:, names}');
    set(ax, 'YDir', 'normal', 'YTick', 1:nLevels, 'YTickLabel', compose('+%.1f m', cfg.slr_m));
    colormap(ax, flipud(hot));
    clim(ax, [0 1]);
    cb = colorbar(ax);
    cb.Label.String = 'Share of corridor land flooded';
    xlabel(ax, 'Longitude (degrees E), west to east');
    ylabel(ax, 'Sea-level rise');
    title(ax, sprintf('M0 bathtub: flooded share of land within %.1f km of the ocean, per %.0f km strip', ...
        cfg.corridor_km, cfg.strip_km));
    exportgraphics(fig, fullfile(cfg.figDir, 'm0_bathtub_corridor_strips.png'), 'Resolution', 200);
else
    fprintf('No mask tiles, so the coastal corridor was skipped.\n');
end

disp(results)
fprintf('Saved results to %s\n', cfg.resultsDir);

% -------------------------------------------------------------------------
function [kmLat, kmLon] = cellSizeKm(R, latMid)
% Size of one grid cell in km (north-south and east-west) at latitude latMid.
kmPerDeg = pi/180 * 6371;
kmLat = kmPerDeg * cellExtentLat(R);
kmLon = kmPerDeg * cellExtentLon(R) * cosd(latMid);
end

function d = cellExtentLat(R)
if strcmp(R.RasterInterpretation, 'postings'), d = R.SampleSpacingInLatitude;
else, d = R.CellExtentInLatitude; end
end

function d = cellExtentLon(R)
if strcmp(R.RasterInterpretation, 'postings'), d = R.SampleSpacingInLongitude;
else, d = R.CellExtentInLongitude; end
end

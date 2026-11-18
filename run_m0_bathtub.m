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

disp(results)
fprintf('Saved results to %s\n', cfg.resultsDir);

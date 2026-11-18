function [Z, M, R] = load_dem(cfg)
%LOAD_DEM Read DeltaDTM tiles, crop them to the study area and join them.
%   [Z, M, R] = load_dem(cfg) returns
%     Z  elevation in metres above EGM2008 (about mean sea level), NaN = no data
%     M  DeltaDTM mask (0 land, 1 ocean, 2 lakes, 3 rivers, 255 above +10 m),
%        or [] if no mask tiles were found
%     R  geographic raster reference for Z and M
%
%   Tiles are read from cfg.demDir. Elevation tiles are every .tif whose
%   name does not contain "mask"; mask tiles are those whose name does.

demFiles  = dir(fullfile(cfg.demDir, '*.tif'));
if isempty(demFiles)
    error('load_dem:noFiles', ...
        'No .tif files in %s. Put the DeltaDTM tiles there first.', cfg.demDir);
end
isMask    = contains(lower({demFiles.name}), 'mask');
elevFiles = demFiles(~isMask);
maskFiles = demFiles(isMask);

[Z, R] = joinTiles(elevFiles, cfg, true);
if isempty(maskFiles)
    warning('load_dem:noMask', ...
        ['No mask tiles found. Water will be taken as the no-data cells ' ...
         'of the elevation model instead.']);
    M = [];
else
    [M, Rm] = joinTiles(maskFiles, cfg, false);
    if ~isequal(size(M), size(Z)) || any(abs(Rm.LatitudeLimits - R.LatitudeLimits) > 1e-9)
        error('load_dem:maskMismatch', ...
            'Mask and elevation grids do not line up. Check that both cover the same tiles.');
    end
end

fprintf('Elevation grid: %d x %d cells, lat %.3f to %.3f, lon %.3f to %.3f\n', ...
    size(Z,1), size(Z,2), R.LatitudeLimits, R.LongitudeLimits);
end

% -------------------------------------------------------------------------
function [A, R] = joinTiles(files, cfg, isElevation)
% Read each tile, crop it to the study area, then join tiles side by side
% (west to east). Tiles that do not touch the study area are skipped.
parts = {};
refs  = {};
west  = [];
for k = 1:numel(files)
    f = fullfile(files(k).folder, files(k).name);
    info = georasterinfo(f);
    [Ak, Rk] = readgeoraster(f);
    % Skip tiles outside the study area
    if Rk.LongitudeLimits(2) <= cfg.lonlim(1) || Rk.LongitudeLimits(1) >= cfg.lonlim(2) || ...
       Rk.LatitudeLimits(2)  <= cfg.latlim(1) || Rk.LatitudeLimits(1)  >= cfg.latlim(2)
        fprintf('Skipping %s (outside the study area)\n', files(k).name);
        continue
    end
    latlimK = [max(cfg.latlim(1), Rk.LatitudeLimits(1)),  min(cfg.latlim(2), Rk.LatitudeLimits(2))];
    lonlimK = [max(cfg.lonlim(1), Rk.LongitudeLimits(1)), min(cfg.lonlim(2), Rk.LongitudeLimits(2))];
    [Ak, Rk] = geocrop(Ak, Rk, latlimK, lonlimK);
    if isElevation
        Ak = single(Ak);
        if ~isempty(info.MissingDataIndicator)
            Ak(Ak == info.MissingDataIndicator) = NaN;
        end
    else
        Ak = uint8(Ak);
    end
    parts{end+1} = Ak; %#ok<AGROW>
    refs{end+1}  = Rk; %#ok<AGROW>
    west(end+1)  = Rk.LongitudeLimits(1); %#ok<AGROW>
    fprintf('Read %s\n', files(k).name);
end
if isempty(parts)
    error('load_dem:noOverlap', 'None of the tiles cover the study area.');
end

% Sort west to east and check every tile has the same rows
[~, order] = sort(west);
parts = parts(order);
refs  = refs(order);
nRows = cellfun(@(a) size(a,1), parts);
if any(nRows ~= nRows(1))
    error('load_dem:rows', ...
        ['Tiles have different numbers of rows after cropping. ' ...
         'The study area may span two tile rows; keep cfg.latlim inside one 1-degree band.']);
end

% Postings-type tiles share their edge column with the next tile: drop it
R1 = refs{1};
if strcmp(R1.RasterInterpretation, 'postings')
    for k = 2:numel(parts)
        if abs(refs{k}.LongitudeLimits(1) - refs{k-1}.LongitudeLimits(2)) < 1e-9
            parts{k} = parts{k}(:, 2:end);
        end
    end
end

A = cat(2, parts{:});
lonlim = [refs{1}.LongitudeLimits(1), refs{end}.LongitudeLimits(2)];
latlim = R1.LatitudeLimits;
if strcmp(R1.RasterInterpretation, 'postings')
    R = georefpostings(latlim, lonlim, size(A), ...
        'ColumnsStartFrom', R1.ColumnsStartFrom, 'RowsStartFrom', R1.RowsStartFrom);
else
    R = georefcells(latlim, lonlim, size(A), ...
        'ColumnsStartFrom', R1.ColumnsStartFrom, 'RowsStartFrom', R1.RowsStartFrom);
end
end

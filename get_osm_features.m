%GET_OSM_FEATURES Download the coastal highway, port and refinery from OpenStreetMap.
%   Uses the public Overpass API. Prints every feature it finds so you can
%   check the names, then saves them to data/osm/osm_features.mat and
%   plots them. OpenStreetMap data is (c) OpenStreetMap contributors, ODbL.

cfg = project_config();
bbox = sprintf('%.4f,%.4f,%.4f,%.4f', cfg.latlim(1), cfg.lonlim(1), cfg.latlim(2), cfg.lonlim(2));

query = [ ...
    '[out:json][timeout:120];(' ...
    'way["highway"]["name"~"Coastal|Calabar",i](' bbox ');' ...
    'way["highway"]["ref"~"Coastal",i](' bbox ');' ...
    'way["name"~"Dangote",i](' bbox ');' ...
    'relation["name"~"Dangote",i](' bbox ');' ...
    'way["name"~"Lekki Deep|Lekki Port|Deep Sea Port",i](' bbox ');' ...
    'relation["name"~"Lekki Deep|Lekki Port|Deep Sea Port",i](' bbox ');' ...
    ');out geom;'];

opts = weboptions('Timeout', 180, 'ContentType', 'json');
fprintf('Querying OpenStreetMap (this can take up to a minute)...\n');
% The public servers are often busy (502/504), so try a few mirrors, twice each
servers = {'https://overpass-api.de/api/interpreter', ...
           'https://overpass.private.coffee/api/interpreter', ...
           'https://maps.mail.ru/osm/tools/overpass/api/interpreter'};
resp = [];
for attempt = 1:2
    for s = 1:numel(servers)
        try
            resp = webread(servers{s}, 'data', query, opts);
            fprintf('Answer from %s\n', servers{s});
            break
        catch err
            fprintf('%s failed (%s). Trying the next server...\n', servers{s}, err.message(1:min(60,end)));
            pause(5);
        end
    end
    if ~isempty(resp), break, end
end
if isempty(resp)
    error('get_osm_features:busy', 'All OpenStreetMap servers are busy. Wait a few minutes and run again.');
end

elements = resp.elements;
if isstruct(elements)
    elements = num2cell(elements);
end
fprintf('Found %d features.\n\n', numel(elements));

features = struct('type', {}, 'id', {}, 'name', {}, 'kind', {}, 'lat', {}, 'lon', {});
for k = 1:numel(elements)
    e = elements{k};
    name = '(no name)';
    kind = '';
    if isfield(e, 'tags')
        if isfield(e.tags, 'name'),     name = e.tags.name;            end
        if isfield(e.tags, 'highway'),  kind = ['highway=' e.tags.highway];
        elseif isfield(e.tags, 'landuse'), kind = ['landuse=' e.tags.landuse];
        elseif isfield(e.tags, 'industrial'), kind = ['industrial=' e.tags.industrial];
        end
    end
    [la, lo] = elementGeometry(e);
    if isempty(la), continue, end
    features(end+1) = struct('type', e.type, 'id', e.id, 'name', name, ...
        'kind', kind, 'lat', la, 'lon', lo); %#ok<SAGROW>
    fprintf('%-9s %12d  %-45s %s  (%d points)\n', e.type, e.id, name, kind, numel(la));
end

save(fullfile(cfg.osmDir, 'osm_features.mat'), 'features', 'query');

% Quick map
fig = figure('Color', 'w', 'Position', [100 100 1100 450]);
gx = geoaxes(fig);
geobasemap(gx, 'satellite');
hold(gx, 'on');
for k = 1:numel(features)
    geoplot(gx, features(k).lat, features(k).lon, 'LineWidth', 2);
end
hold(gx, 'off');
geolimits(gx, cfg.latlim, cfg.lonlim);
title(gx, 'Features found in OpenStreetMap');
exportgraphics(fig, fullfile(cfg.figDir, 'osm_features.png'), 'Resolution', 200);
fprintf('\nSaved %d features to %s\n', numel(features), fullfile(cfg.osmDir, 'osm_features.mat'));

% -------------------------------------------------------------------------
function [la, lo] = elementGeometry(e)
% Ways carry a 'geometry' list; relations carry 'members', each with its own.
la = []; lo = [];
if isfield(e, 'geometry')
    g = e.geometry;
    if iscell(g), g = [g{:}]; end
    la = [g.lat]'; lo = [g.lon]';
elseif isfield(e, 'members')
    mem = e.members;
    if isstruct(mem), mem = num2cell(mem); end
    for m = 1:numel(mem)
        if isfield(mem{m}, 'geometry')
            g = mem{m}.geometry;
            if iscell(g), g = [g{:}]; end
            % NaN separates the parts so plots do not join them
            la = [la; [g.lat]'; NaN]; %#ok<AGROW>
            lo = [lo; [g.lon]'; NaN]; %#ok<AGROW>
        end
    end
end
end

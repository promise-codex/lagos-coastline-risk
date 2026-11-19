%GET_PLACE_COORDS Find the Section 2 beach communities in OpenStreetMap.
%   The assessment gives shoreline change rates by community name
%   (Section 2, Table 4.19, p. 4-89) without coordinates. This script looks
%   the names up as OpenStreetMap place points inside the study area and
%   saves data/osm/places.csv. Names it cannot find fall back to the
%   assessment's own sampling-point coordinates where those exist.

cfg = project_config();
T = readtable(fullfile(cfg.dataDir, 'esia', 'shoreline_rates_section2.csv'), 'TextType', 'string');
bbox = sprintf('%.4f,%.4f,%.4f,%.4f', cfg.latlim(1), cfg.lonlim(1), cfg.latlim(2), cfg.lonlim(2));
query = ['[out:json][timeout:60];node["place"]["name"](' bbox ');out;'];

servers = {'https://overpass-api.de/api/interpreter', ...
           'https://overpass.private.coffee/api/interpreter', ...
           'https://maps.mail.ru/osm/tools/overpass/api/interpreter'};
opts = weboptions('Timeout', 120, 'ContentType', 'json');
resp = [];
for attempt = 1:2
    for s = 1:numel(servers)
        try
            resp = webread(servers{s}, 'data', query, opts);
            break
        catch err
            fprintf('%s failed (%s). Trying the next server...\n', servers{s}, err.message(1:min(60, end)));
            pause(5);
        end
    end
    if ~isempty(resp), break, end
end
if isempty(resp), error('get_place_coords:busy', 'OpenStreetMap servers busy. Try again in a few minutes.'); end

el = resp.elements;
if isstruct(el), el = num2cell(el); end
names = strings(numel(el), 1); plat = nan(numel(el), 1); plon = nan(numel(el), 1);
for k = 1:numel(el)
    names(k) = string(el{k}.tags.name); plat(k) = el{k}.lat; plon(k) = el{k}.lon;
end
norm = @(s) lower(regexprep(s, '[^a-zA-Z]', ''));     % "Akodo-Ise" -> "akodoise"
nn = arrayfun(norm, names);

T.lon = nan(height(T), 1); T.lat = nan(height(T), 1); T.coord_source = strings(height(T), 1);
for i = 1:height(T)
    key = norm(T.community(i));
    alt = strrep(key, 'campaigne', 'campagne');
    hit = find(nn == key | nn == alt);
    % Prefer the place nearest the coast (lowest latitude) if a name repeats
    if ~isempty(hit)
        [~, j] = min(plat(hit)); j = hit(j);
        T.lon(i) = plon(j); T.lat(i) = plat(j);
        T.coord_source(i) = "OpenStreetMap place: " + names(j);
    elseif ~isnan(T.lon_fallback(i))
        T.lon(i) = T.lon_fallback(i); T.lat(i) = T.lat_fallback(i);
        T.coord_source(i) = string(T.fallback_source(i));
    else
        T.coord_source(i) = "NOT FOUND";
    end
    fprintf('%-14s %8.4f %8.4f  %s\n', T.community(i), T.lat(i), T.lon(i), T.coord_source(i));
end
writetable(T(:, {'community', 'epr_m_yr', 'lat', 'lon', 'coord_source'}), fullfile(cfg.osmDir, 'places.csv'));
fprintf('Saved %s (%d of %d located)\n', fullfile(cfg.osmDir, 'places.csv'), sum(~isnan(T.lon)), height(T));

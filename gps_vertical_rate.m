%GPS_VERTICAL_RATE Vertical rate of the two GPS stations at UNILAG, used to tie the radar map.
%   Downloads the daily IGS20 position series of ULAG and LAF1 (University
%   of Lagos, 0.26 km apart) from the Nevada Geodetic Laboratory and
%   estimates the vertical rate the same way as MIDAS (Blewitt et al. 2016),
%   simplified: the median of the slopes of all pairs of days about one
%   year apart. Using one-year pairs cancels the yearly cycle, and the
%   median ignores jumps and outliers.
%
%   The mean of the two rates is written into
%   insar/make_vlm_product.py (GPS_UP); this script lets anyone check it.
%   Both records end in 2012-2013, before the radar record (2017-2025)
%   starts, so using them assumes the rate at UNILAG did not change.
%
%   Data: Blewitt, G., Hammond, W. C., Kreemer, C. (2018), Harnessing the
%   GPS data explosion for interdisciplinary science, Eos 99.

stations = {'ULAG', 'LAF1'};
rate = nan(1, 2);
for k = 1:2
    url = sprintf('https://geodesy.unr.edu/gps_timeseries/IGS20/tenv3/IGS20/%s.tenv3', stations{k});
    txt = webread(url, weboptions('Timeout', 60, 'ContentType', 'text'));
    C = textscan(txt, '%s %s %f %f %f %f %f %f %f %f %f %f %f %*[^\n]', 'HeaderLines', 1);
    t = C{3}; up = C{12} + C{13};                     % decimal year; height = u0 + up (m)
    slopes = [];
    for i = 1:numel(t)
        j = find(t > t(i) + 0.99 & t <= t(i) + 1.01);
        slopes = [slopes; (up(j) - up(i)) ./ (t(j) - t(i))]; %#ok<AGROW>
    end
    rate(k) = 1000 * median(slopes);
    spread = 1000 * 1.4826 * median(abs(slopes - median(slopes)));
    fprintf('%s: %d days, %.1f to %.1f, vertical rate %.1f mm/yr (spread of pair slopes %.1f mm/yr, %d pairs)\n', ...
        stations{k}, numel(t), t(1), t(end), rate(k), spread, numel(slopes));
end
fprintf('Mean of the two stations: %.1f mm/yr (used to tie the radar map).\n', mean(rate));

%RUN_AFTER_INSAR Re-run every step that uses land sinking, with the measured radar rates.
%   Run this once after pulling the radar update. It needs the results of
%   run_m1_sinking (flood_level_map.mat) and the downloaded route
%   (data/osm/highway_segments.mat, data/osm/places.csv) from earlier runs.
%   It prints everything to the Command Window and saves a copy in
%   results/run_after_insar_log.txt. Takes about 10 to 20 minutes.

cfg = project_config();
logFile = fullfile(cfg.resultsDir, 'run_after_insar_log.txt');
if isfile(logFile), delete(logFile); end
diary(logFile);
fprintf('==== 1. GPS rate at UNILAG (tie point of the radar map) ====\n');
gps_vertical_rate
fprintf('\n==== 2. M3 with measured sinking (also makes insar_segment_rates.csv and its figures) ====\n');
run_m3_extremes
fprintf('\n==== 3. M2 and the method ladder ====\n');
run_m2_shoreline
fprintf('\n==== 4. Monte Carlo ====\n');
run_uncertainty
fprintf('\n==== 5. Check: one rate per km vs pixel-by-pixel sinking ====\n');
check_spatial_sinking
diary off
fprintf('\nDone. Log saved to %s\n', logFile);

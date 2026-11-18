%SETUP_PROJECT Create the folder structure and check the toolboxes.
%   Run this once, from the folder that holds it.

cfg = project_config();

folders = {cfg.dataDir, cfg.demDir, cfg.osmDir, cfg.resultsDir, cfg.figDir};
for k = 1:numel(folders)
    if ~isfolder(folders{k})
        mkdir(folders{k});
        fprintf('Created %s\n', folders{k});
    end
end

% Check that the toolboxes used in this first step are installed
needed = {'Mapping Toolbox', 'Image Processing Toolbox'};
v = ver;
installed = {v.Name};
for k = 1:numel(needed)
    if any(strcmp(installed, needed{k}))
        fprintf('OK      %s\n', needed{k});
    else
        fprintf('MISSING %s\n', needed{k});
    end
end

fprintf('\nNext: put the DeltaDTM tiles (and their mask tiles) in\n  %s\n', cfg.demDir);
fprintf('then run run_m0_bathtub.\n');

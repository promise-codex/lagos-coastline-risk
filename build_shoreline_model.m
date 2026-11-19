function build_shoreline_model(modelName)
%BUILD_SHORELINE_MODEL Create the Simulink shoreline model used by method M2.
%   build_shoreline_model() creates shoreline_model.slx in the project
%   folder. The state y (one value per 1 km road segment, metres, positive
%   seaward, 0 = today's shoreline) evolves as
%
%       dy/dt = r  -  B * s(t)  +  D * L * y
%
%     r     measured long-term shoreline change rate per segment (m/yr),
%           from the highway assessment's own end point rates
%     s(t)  extra relative sea-level rise rate above the historical rate
%           (m/yr), from IPCC AR6 plus land sinking, read as a time series
%     B     Bruun factor: metres of retreat per metre of extra rise
%     D, L  optional alongshore smoothing (one-line diffusion, m^2/yr) with
%           L the second-difference matrix over 1 km spacing and closed
%           ends. D = 0 by default because no calibrated value exists here.
%
%   The model is solved with a fixed one-year step (ode4) from 2020 to 2150.

if nargin < 1, modelName = 'shoreline_model'; end
cfg = project_config();
file = fullfile(cfg.root, [modelName '.slx']);
if bdIsLoaded(modelName), close_system(modelName, 0); end
if isfile(file), delete(file); end

new_system(modelName);
m = modelName;
set_param(m, 'Solver', 'ode4', 'FixedStep', '1', 'StartTime', '2020', 'StopTime', '2150', ...
    'SaveTime', 'on', 'TimeSaveName', 'tout', 'ReturnWorkspaceOutputs', 'on');

add_block('simulink/Sources/Constant', [m '/Measured rate r'], ...
    'Value', 'eprVec', 'Position', [40 40 140 70]);
add_block('simulink/Sources/From Workspace', [m '/Extra rise rate s(t)'], ...
    'VariableName', 'extraRiseRate', 'Interpolate', 'on', 'OutputAfterFinalValue', 'Holding final value', ...
    'Position', [40 110 160 140]);
add_block('simulink/Math Operations/Gain', [m '/Bruun factor B'], ...
    'Gain', 'bruunFactor', 'Position', [200 110 260 140]);
add_block('simulink/Math Operations/Sum', [m '/Sum'], ...
    'Inputs', '+-+', 'Position', [320 60 350 160]);
add_block('simulink/Continuous/Integrator', [m '/Shoreline y'], ...
    'InitialCondition', 'zeros(nSeg,1)', 'Position', [400 95 440 125]);
add_block('simulink/Math Operations/Gain', [m '/Alongshore D*L'], ...
    'Gain', 'diffMatrix', 'Multiplication', 'Matrix(K*u)', ...
    'Position', [380 190 460 220], 'Orientation', 'left');
add_block('simulink/Sinks/To Workspace', [m '/Save y'], ...
    'VariableName', 'yOut', 'SaveFormat', 'Array', 'Position', [500 95 580 125]);

add_line(m, 'Measured rate r/1', 'Sum/1', 'autorouting', 'on');
add_line(m, 'Extra rise rate s(t)/1', 'Bruun factor B/1', 'autorouting', 'on');
add_line(m, 'Bruun factor B/1', 'Sum/2', 'autorouting', 'on');
add_line(m, 'Sum/1', 'Shoreline y/1', 'autorouting', 'on');
add_line(m, 'Shoreline y/1', 'Save y/1', 'autorouting', 'on');
add_line(m, 'Shoreline y/1', 'Alongshore D*L/1', 'autorouting', 'on');
add_line(m, 'Alongshore D*L/1', 'Sum/3', 'autorouting', 'on');

try   % a note on the canvas; skipped quietly if this release names it differently
    note = Simulink.Annotation([m '/Shoreline position per 1 km road segment (m, + seaward): dy/dt = r - B*s(t) + D*L*y']);
    note.Position = [40 250 520 280];
catch
end

save_system(m, file);
close_system(m, 0);
fprintf('Saved %s\n', file);
end

classdef tShorePosition < matlab.unittest.TestCase
    % Unit tests for shore_position.m. Drafted by MATLAB Copilot from a
    % prompt by the author (see README, "How generative AI was used"),
    % checked by hand and run with runtests('tShorePosition').
    methods(Test)
        function cleanCrossing(testCase)
            s = [0 1 2 3];
            prof = [0.10 0.20 0.80 0.90];
            obs = [5 5 5 5];
            th = 0.5;
            minObs = 3;

            p = shore_position(s, prof, obs, th, minObs);

            testCase.verifyEqual(p, 1.5, 'AbsTol', 1e-12);
        end

        function noWaterAtSeaEnd(testCase)
            s = [0 1 2 3];
            prof = [0.80 0.70 0.40 0.30];
            obs = [5 5 5 5];
            th = 0.5;
            minObs = 3;

            p = shore_position(s, prof, obs, th, minObs);

            testCase.verifyTrue(isnan(p));
        end

        function gapBeforeLand(testCase)
            s = [0 1 2 3 4];
            prof = [0.20 0.30 NaN 0.80 0.90];
            obs = [5 5 5 5 5];
            th = 0.5;
            minObs = 3;

            p = shore_position(s, prof, obs, th, minObs);

            testCase.verifyTrue(isnan(p));
        end
    end
end

function run_test1_pv(DAY)
%RUN_TEST1_PV  Test 1: run PV_Unit_day.slx (one 19.2 kW unit) on the NASA POWER weather.
%   run_test1_pv            -> clear day  (9 May 2025)
%   run_test1_pv('cloudy')  -> partly cloudy day (16 May 2025)
%   Results go to 04_results/test1_pv/nasa_<DAY>/  (figures, .mat log, summary.txt)
if nargin < 1, DAY = 'clear'; end
root = fileparts(fileparts(mfilename('fullpath')));          % RET_Project_v2
addpath(fullfile(root,'01_model'), fullfile(root,'02_scripts'), ...
        fullfile(root,'02_scripts','pv'), fullfile(root,'03_data'));
mdl = 'PV_Unit_day';
load_system(fullfile(root,'01_model',[mdl '.slx']));

% InitFcn: read the weather from 03_data (on the path) and honour DAY from the base workspace
init = sprintf([ ...
  'Ts = 1e-6;\n' ...
  't_hour = 0.05;   %% simulated seconds per real hour (24 h = 1.2 s)\n' ...
  'if ~exist(''DAY'',''var''), DAY = ''clear''; end\n' ...
  'f = fullfile(fileparts(get_param(bdroot,''FileName'')), ''pv_daily_profile.mat'');\n' ...
  'if ~isfile(f), f = which(''pv_daily_profile.mat''); end\n' ...
  'S = load(f);   %% NASA POWER profile (next to model, else 03_data on path)\n' ...
  't_day = S.t;\n' ...
  'if strcmp(DAY,''cloudy''), G_day = S.G_cloudy; T_amb_day = S.T_amb_cloudy;\n' ...
  'else, G_day = S.G_clear; T_amb_day = S.T_amb; end\n']);
set_param(mdl, 'InitFcn', init, 'StopTime', '24*0.05');
save_system(mdl);

assignin('base','DAY',DAY);
fprintf('\nTest 1: %s, %s day (NASA POWER). Simulating 24 h = 1.2 s, takes a few minutes...\n', mdl, DAY);
tic; out = sim(mdl); fprintf('Simulation finished in %.0f s\n', toc);

od = fullfile(root,'04_results','test1_pv',['nasa_' DAY]);
if ~exist(od,'dir'), mkdir(od); end
pvdata = out.pvdata; wxdata = out.wxdata;                     %#ok<NASGU>
save(fullfile(od,['test1_pv_' DAY '.mat']), 'pvdata','wxdata','DAY');

assignin('base','out',out);
assignin('base','dayLabel', ternary(strcmp(DAY,'cloudy'), 'Partly Cloudy Day (16 May 2025, NASA POWER)', 'Clear Day (9 May 2025, NASA POWER)'));
here = pwd; cd(od);
diary('summary.txt'); diary on;
fprintf('Weather: NASA POWER hourly, Coimbatore 11.02N 76.96E, %s day\n', DAY);
evalin('base','ppt_plots_pv');
diary off; cd(here);
fprintf('Results saved in %s\n', od);
end

function v = ternary(c,a,b), if c, v = a; else, v = b; end, end

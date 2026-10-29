% setup_paths.m - run once per MATLAB session from the RET_Project_v2 folder
root = fileparts(mfilename('fullpath'));
addpath(fullfile(root,'01_model'), fullfile(root,'02_scripts'), fullfile(root,'02_scripts','model_fixes'), ...
        fullfile(root,'02_scripts','pv'), fullfile(root,'03_data'));
cd(fullfile(root,'01_model'));          % models save here; data/scripts found on the path
init_microgrid;
fprintf('RET v2 paths set. Working folder: %s\n', pwd);

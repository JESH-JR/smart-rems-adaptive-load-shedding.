%% fix_microgrid_model_v2.m  -  rebuilds microgrid_top_fixed.slx in MATLAB R2025a
% Step A: runs the v1 script (fix_microgrid_model.m) on the R2025a original microgrid_top.slx
% Step B: applies the v2 fixes found in the 29 Oct review:
%   1. Load Manager SoC input: % -> per unit (gain 1/100), sampled at Ts_ems
%   2. dSoC/dt scaled to "per real hour" (gain t_hour) so the -0.15 threshold means 0.15 pu/h
%   3. Load Manager P_def input: W -> kW (gain 1/1000)
%   4. Loads MATLAB Function sample time = Ts_fc (Edef integrates dt = 0.25 h once per 15 min)
%   5. SC converter: series L_Boost1 (1.5 mH) on the 400 V side removed
%   6. Battery MaxQ = Q_sim_Ah (was a hard-coded number)
%   7. Supercapacitor rated voltage = V_sc_nom
%   8. Floating AC RLC loads + switches inside 'Loads' commented out (inverter is off the bus)
%   9. Automatic rate-transition handling on
% Run from anywhere:  fix_microgrid_model_v2

root = fileparts(fileparts(fileparts(mfilename('fullpath'))));            % RET_Project_v2
addpath(fullfile(root,'01_model'), fullfile(root,'01_model','_rebuild_source'), fullfile(root,'02_scripts'), fullfile(root,'02_scripts','model_fixes'), fullfile(root,'03_data'));
cd(fullfile(root,'01_model'));

v = ver('MATLAB');
if ~contains(v.Release,'R2025a'), warning('Running in %s, the team version is R2025a.', v.Release); end

% keep the old (R2025b) file instead of letting v1 delete it
mdl = 'microgrid_top_fixed';
if bdIsLoaded(mdl), close_system(mdl,0); end
if exist(fullfile(pwd,[mdl '.slx']),'file') && ~exist(fullfile(pwd,[mdl '_R2025b_old.slx']),'file')
    movefile([mdl '.slx'], [mdl '_R2025b_old.slx']);
end

%% ---------- Step A: v1 fixes ----------
fix_microgrid_model;                       % creates and saves microgrid_top_fixed.slx (prints its own report)
if ~bdIsLoaded(mdl), load_system(mdl); end

%% ---------- Step B: v2 fixes ----------
B   = @(p) [mdl '/' p];
rep = {};
rep(end+1,:) = trystep('1-2. SoC -> per unit, dSoC/dt per real hour', @() fix_soc_inputs(mdl));
rep(end+1,:) = trystep('3. P_def W -> kW',                           @() fix_pdef(mdl));
rep(end+1,:) = trystep('4. Loads function sample time = Ts_fc',      @() set_chart_ts([mdl '/Loads/MATLAB Function'],'Ts_fc'));
rep(end+1,:) = trystep('5. Remove L_Boost1 from SC converter',       @() remove_lboost1(mdl));
rep(end+1,:) = trystep('6a. Battery preset model OFF (else R is auto-computed: 133 ohm)', @() set_param(B('Battery'),'PresetModel','off'));
rep(end+1,:) = trystep('6b. Battery R = R_bat, response time 1 ms', @() set_param(B('Battery'),'R','R_bat','Batt_Tr','1e-3'));
rep(end+1,:) = trystep('6. Battery MaxQ = Q_sim_Ah',                 @() set_param(B('Battery'),'MaxQ','Q_sim_Ah'));
rep(end+1,:) = trystep('7. Supercap rated voltage = V_sc_nom',       @() set_param(B('Supercapacitor'),'Voltage','V_sc_nom'));
rep(end+1,:) = trystep('8. Comment out floating AC loads in Loads',  @() comment_ac_loads(mdl));
rep(end+1,:) = trystep('9. Auto rate transitions on',                @() set_param(mdl,'AutoInsertRateTranBlk','on'));
set_param(mdl,'StopTime','T_stop');
save_system(mdl);

fprintf('\n===== fix_microgrid_model_v2 report (%s.slx, %s) =====\n', mdl, v.Release);
for k = 1:size(rep,1)
    if rep{k,2}, fprintf('  OK    %s\n', rep{k,1}); else, fprintf('  FAIL  %s  ->  %s\n', rep{k,1}, rep{k,3}); end
end
fprintf(['\nNext: short test first  ->  out = sim(''%s'',''StopTime'',''0.36'');   (= 3 real hours)\n' ...
         'Check: battery voltage ~240 V, V_DC ~400 V, P_load_meas positive. Then the full day.\n\n'], mdl);

%% =============== helpers ===============
function r = trystep(name, fh)
    try, fh(); r = {name, true, ''}; catch e, r = {name, false, e.message}; end
end

function set_chart_ts(path, ts)
    ch = sfroot().find('-isa','Stateflow.EMChart','Path',path);
    if isempty(ch), ch = sfroot().find('-isa','Stateflow.Chart','Path',path); end
    if isempty(ch), error('chart not found at %s', path); end
    ch.SampleTime = ts;
end

function fix_soc_inputs(mdl)
    % From2 [SoC_Battery, %] used to feed Load Manager/1 and Discrete Derivative directly
    lh = get_param([mdl '/From2'],'LineHandles'); delete_line(lh.Outport(1));
    lh = get_param([mdl '/Discrete Derivative'],'LineHandles'); delete_line(lh.Outport(1));
    p = get_param([mdl '/From2'],'Position');
    add_block('simulink/Discrete/Zero-Order Hold', [mdl '/SoC_ZOH'], 'SampleTime','Ts_ems', 'Position', p + [90 0 110 0]);
    add_block('simulink/Math Operations/Gain', [mdl '/SoC_pu'], 'Gain','1/100', 'Position', p + [160 0 190 0]);
    q = get_param([mdl '/Discrete Derivative'],'Position');
    add_block('simulink/Math Operations/Gain', [mdl '/dSoC_per_hour'], 'Gain','t_hour', 'Position', q + [90 0 100 0]);
    add_line(mdl,'From2/1','SoC_ZOH/1','autorouting','on');
    add_line(mdl,'SoC_ZOH/1','SoC_pu/1','autorouting','on');
    add_line(mdl,'SoC_pu/1','Load Manager/1','autorouting','on');
    add_line(mdl,'SoC_pu/1','Discrete Derivative/1','autorouting','on');
    add_line(mdl,'Discrete Derivative/1','dSoC_per_hour/1','autorouting','on');
    add_line(mdl,'dSoC_per_hour/1','Load Manager/2','autorouting','on');
end

function fix_pdef(mdl)
    lh = get_param([mdl '/From5'],'LineHandles'); delete_line(lh.Outport(1));
    p = get_param([mdl '/From5'],'Position');
    add_block('simulink/Math Operations/Gain', [mdl '/Pdef_kW'], 'Gain','1/1000', 'Position', p + [90 0 110 0]);
    add_line(mdl,'From5/1','Pdef_kW/1','autorouting','on');
    add_line(mdl,'Pdef_kW/1','Load Manager/3','autorouting','on');
end

function remove_lboost1(mdl)
    S  = [mdl '/Bidirectional DC-DC converter ' char(10) 'For Supercapacitor'];
    L  = [S '/L_Boost1'];
    lh = get_param(L,'LineHandles');
    delete_line([lh.LConn lh.RConn]);
    delete_block(L);
    hp = get_param([S '/High +'],'PortHandles');
    q1 = get_param([S '/Q1'],'PortHandles');
    add_line(S, hp.RConn(1), q1.LConn(1), 'autorouting','on');
end

function comment_ac_loads(mdl)
    L = [mdl '/Loads'];
    names = {'Parallel RLC Load','Parallel RLC Load1','Parallel RLC Load2','Ideal Switch','Ideal Switch1','Ideal Switch2'};
    for k = 1:numel(names), set_param([L '/' names{k}],'Commented','on'); end
end

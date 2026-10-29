%% fix_microgrid_model_v2b.m  -  small follow-up fixes to microgrid_top_fixed.slx (R2025a)
%  1. Break the algebraic loop: 1-step delay (Ts) on the bus voltage feeding the DC load
%  2. Load Manager state actions end with ';' (stops "L = 0" printing every step)
%  3. Log the key signals (no scope hunting) -> plot with plot_test4
root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(fullfile(root,'01_model'), fullfile(root,'01_model','_rebuild_source'), fullfile(root,'02_scripts'), fullfile(root,'02_scripts','model_fixes'), fullfile(root,'03_data'));
cd(fullfile(root,'01_model'));
mdl = 'microgrid_top_fixed';  load_system(mdl);
rep = {};
rep(end+1,:) = trystep('1. Unit delay on V_DC -> DC load (algebraic loop)', @() add_vdc_delay(mdl));
rep(end+1,:) = trystep('2. Load Manager actions end with ;',               @() fix_lm_labels(mdl));
rep(end+1,:) = trystep('3. Signal logging for plot_test4',                @() add_logging(mdl));
set_param(mdl,'SignalLogging','on','SignalLoggingName','logsout');
save_system(mdl);
fprintf('\n===== fix_microgrid_model_v2b report =====\n');
for k = 1:size(rep,1)
    if rep{k,2}, fprintf('  OK    %s\n', rep{k,1}); else, fprintf('  FAIL  %s  ->  %s\n', rep{k,1}, rep{k,3}); end
end
fprintf('\nNext:  out = sim(''%s'',''StopTime'',''0.36'');   then   plot_test4(out,''short_3h'')\n\n', mdl);

function r = trystep(name, fh)
    try, fh(); r = {name, true, ''}; catch e, r = {name, false, e.message}; end
end

function add_vdc_delay(mdl)
    if getSimulinkBlockHandle([mdl '/VDC_delay']) > 0, return; end
    lh = get_param([mdl '/From_VDC_load'],'LineHandles'); delete_line(lh.Outport(1));
    p = get_param([mdl '/From_VDC_load'],'Position');
    add_block('simulink/Discrete/Unit Delay', [mdl '/VDC_delay'], 'SampleTime','Ts', ...
              'InitialCondition','V_dc_ref', 'Position', p + [70 0 70 0]);
    set_param([mdl '/Vdc_limit'],'Position', get_param([mdl '/Vdc_limit'],'Position') + [60 0 60 0]);
    add_line(mdl,'From_VDC_load/1','VDC_delay/1','autorouting','on');
    add_line(mdl,'VDC_delay/1','Vdc_limit/1','autorouting','on');
end

function fix_lm_labels(mdl)
    ch = sfroot().find('-isa','Stateflow.Chart','Path',[mdl '/Load Manager']);
    st = ch.find('-isa','Stateflow.State');
    for k = 1:numel(st)
        s = st(k).LabelString;
        s = regexprep(s, '(L\s*=\s*\d)\s*(?=\r?\n|$)', '$1;');
        s = regexprep(s, '(outage_flag\s*=\s*\d)\s*(?=\r?\n|$)', '$1;');
        st(k).LabelString = s;
    end
end

function add_logging(mdl)
    sig = { 'Bus Selector1',1,'V_bat';  'Bus Selector1',2,'I_bat';  'Bus Selector1',3,'SoC_bat'; ...
            'Bus Selector2',1,'V_sc';   'Bus Selector2',2,'I_sc'; ...
            'Voltage Measurement',1,'V_DC'; 'P_load_meas',1,'P_load_meas'; 'P_PV_total',1,'P_PV'; ...
            'Load Manager',1,'L'; 'Loads/kW_to_W',1,'P_req_W' };
    for k = 1:size(sig,1)
        ph = get_param([mdl '/' sig{k,1}],'PortHandles');
        set_param(ph.Outport(sig{k,2}), 'DataLogging','on', 'DataLoggingNameMode','Custom', ...
                  'DataLoggingName',sig{k,3}, 'DataLoggingDecimateData','on', 'DataLoggingDecimation','20');
    end
end

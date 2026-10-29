%% fix_microgrid_model_v2c.m  -  battery model fix for the time-compressed day (R2025a)
% Problem: the generic Li-ion block derives its polarization resistance from the capacity.
%          Shrinking the capacity to 0.018 Ah (time compression) makes it hundreds of ohms,
%          so the 240 V pack collapses to ~0 V under load (also the cause of the 22 V in the report).
% Fix:     1. Battery block uses the REAL capacity Q_real_Ah (541.7 Ah) -> realistic 240 V pack
%          2. Compressed-time SoC from coulomb counting (report Eq. 11):
%             SoC = SoC0*100 - 100/(3600*Q_sim_Ah) * integral(i_bat dt), limited to 0..100 %
%             -> feeds Goto [SoC_Battery] (EMS, Load Manager, PV curtailment)
root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(fullfile(root,'01_model'), fullfile(root,'01_model','_rebuild_source'), fullfile(root,'02_scripts'), fullfile(root,'02_scripts','model_fixes'), fullfile(root,'03_data'));
cd(fullfile(root,'01_model'));
evalin('base','init_microgrid');
mdl = 'microgrid_top_fixed';  load_system(mdl);
rep = {};
rep(end+1,:) = trystep('1. Battery block: real capacity, consistent parameters', @() fix_battery(mdl));
rep(end+1,:) = trystep('2. Coulomb-counting SoC -> [SoC_Battery]',             @() add_soc_counter(mdl));
save_system(mdl);
fprintf('\n===== fix_microgrid_model_v2c report =====\n');
for k = 1:size(rep,1)
    if rep{k,2}, fprintf('  OK    %s\n', rep{k,1}); else, fprintf('  FAIL  %s  ->  %s\n', rep{k,1}, rep{k,3}); end
end
b = [mdl '/Battery'];
fprintf('Battery block now: NomV %s, NomQ %s, R %s, FullV %s, preset %s\n', get_param(b,'NomV'), ...
        get_param(b,'NomQ'), get_param(b,'R'), get_param(b,'FullV'), get_param(b,'PresetModel'));
fprintf('\nNext:  out = sim(''%s'',''StopTime'',''0.36'');   plot_test4(out,''short_3h'')\n\n', mdl);

function r = trystep(name, fh)
    try, fh(); r = {name, true, ''}; catch e, r = {name, false, e.message}; end
end

function fix_battery(mdl)
    b = [mdl '/Battery'];
    set_param(b,'PresetModel','on');                         % let the block derive a consistent real-size parameter set
    set_param(b,'NomV','V_bat_nom','NomQ','Q_real_Ah','SOC','SoC0*100');
    set_param(b,'PresetModel','off');                        % keep those values, then set our own R / response time
    set_param(b,'MaxQ','Q_real_Ah','R','R_bat','Batt_Tr','1e-3');
end

function add_soc_counter(mdl)
    if getSimulinkBlockHandle([mdl '/SoC_coulomb']) > 0, return; end
    % disconnect the block's own SoC from Goto8 [SoC_Battery]
    lh = get_param([mdl '/Goto8'],'LineHandles'); delete_line(lh.Inport(1));
    p = get_param([mdl '/Goto8'],'Position');
    add_block('simulink/Discrete/Discrete-Time Integrator', [mdl '/SoC_coulomb'], ...
        'gainval','-100/(3600*Q_sim_Ah)', 'InitialCondition','SoC0*100', 'SampleTime','Ts', ...
        'LimitOutput','on', 'UpperSaturationLimit','100', 'LowerSaturationLimit','0', ...
        'Position', p + [-120 60 -80 70]);
    add_line(mdl,'Bus Selector1/2','SoC_coulomb/1','autorouting','on');   % battery current (+ = discharge)
    add_line(mdl,'SoC_coulomb/1','Goto8/1','autorouting','on');
    % logging: SoC_bat now comes from the counter
    ph = get_param([mdl '/Bus Selector1'],'PortHandles');  set_param(ph.Outport(3),'DataLogging','off');
    ph = get_param([mdl '/SoC_coulomb'],'PortHandles');
    set_param(ph.Outport(1),'DataLogging','on','DataLoggingNameMode','Custom','DataLoggingName','SoC_bat', ...
              'DataLoggingDecimateData','on','DataLoggingDecimation','20');
end

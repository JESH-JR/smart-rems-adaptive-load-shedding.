%% fix_microgrid_model_v2d.m  -  (1) SoC counter (re-do of v2c step 2)  (2) connect the bus-voltage loop
% (1) Coulomb-counting SoC (report Eq. 11) -> Goto [SoC_Battery]. v2c removed the old link but the
%     counter block was not created, so SoC_Battery read 0 %.
% (2) Combined controller (report Eq. 19): the voltage-loop PI output was not connected to anything.
%       battery ref = EMS ref + LPF(PI) * V_SC/V_bat      (slow part -> battery)
%       SC ref      = [PI - LPF(PI) + battery current error] * V_bat/V_SC   (fast part -> supercap)
root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(fullfile(root,'01_model'), fullfile(root,'01_model','_rebuild_source'), fullfile(root,'02_scripts'), fullfile(root,'02_scripts','model_fixes'), fullfile(root,'03_data'));
cd(fullfile(root,'01_model'));
evalin('base','init_microgrid');
mdl = 'microgrid_top_fixed';  load_system(mdl);
rep = {};
rep(end+1,:) = trystep('1. Coulomb-counting SoC -> [SoC_Battery]', @() add_soc_counter(mdl));
rep(end+1,:) = trystep('2. Connect voltage loop (battery slow / SC fast)', @() fix_controller(mdl));
save_system(mdl);
fprintf('\n===== fix_microgrid_model_v2d report =====\n');
for k = 1:size(rep,1)
    if rep{k,2}, fprintf('  OK    %s\n', rep{k,1}); else, fprintf('  FAIL  %s  ->  %s\n', rep{k,1}, rep{k,3}); end
end
fprintf('\nNext:  out = sim(''%s'',''StopTime'',''0.36'');   plot_test4(out,''short_3h'')\n\n', mdl);

function r = trystep(name, fh)
    try, fh(); r = {name, true, ''}; catch e, r = {name, false, e.message}; end
end

function add_soc_counter(mdl)
    blk = [mdl '/SoC_coulomb'];
    if getSimulinkBlockHandle(blk) < 0
        p = get_param([mdl '/Goto8'],'Position');
        add_block('simulink/Discrete/Discrete-Time Integrator', blk, ...
            'Position', [p(1)-160, p(2)+70, p(1)-90, p(2)+110]);
        set_param(blk, 'gainval','-100/(3600*Q_sim_Ah)', 'InitialCondition','SoC0*100', 'SampleTime','Ts');
        set_param(blk, 'LimitOutput','on', 'UpperSaturationLimit','100', 'LowerSaturationLimit','0');
    end
    lh = get_param([mdl '/Goto8'],'LineHandles');            % make sure Goto8 is fed by the counter
    if lh.Inport(1) > 0, delete_line(lh.Inport(1)); end
    lh = get_param(blk,'LineHandles');
    if lh.Inport(1) < 0, add_line(mdl,'Bus Selector1/2','SoC_coulomb/1','autorouting','on'); end
    add_line(mdl,'SoC_coulomb/1','Goto8/1','autorouting','on');
    ph = get_param([mdl '/Bus Selector1'],'PortHandles');  set_param(ph.Outport(3),'DataLogging','off');
    ph = get_param(blk,'PortHandles');
    set_param(ph.Outport(1),'DataLogging','on','DataLoggingNameMode','Custom','DataLoggingName','SoC_bat', ...
              'DataLoggingDecimateData','on','DataLoggingDecimation','20');
end

function fix_controller(mdl)
    CC  = [mdl '/Combined Control Battery//Supercapacitor'];
    nl  = char(10);
    FOF = ['First-Order' nl 'Filter'];
    pos = @(b) get_param([CC '/' b],'Position');
    % (a) HF part: Sum3 = PI - LPF(PI)
    add_line(CC, [FOF '/1'], 'Sum3/2', 'autorouting','on');
    % (b) SC current reference = Divide1 (instead of the EMS feed-forward)
    lh = get_param([CC '/I_SC_ref_EMS'],'LineHandles'); delete_line(lh.Outport(1));
    p = pos('I_SC_ref_EMS');
    add_block('simulink/Sinks/Terminator', [CC '/Term_ISC_EMS'], 'Position', [p(3)+40 p(2) p(3)+60 p(4)]);
    add_line(CC, 'I_SC_ref_EMS/1', 'Term_ISC_EMS/1');
    add_line(CC, 'Divide1/1', 'Sum2/1', 'autorouting','on');
    % (c) LF part to the battery: Ibat_ref = EMS ref + LPF(PI) * V_SC/V_bat
    lh = get_param([CC '/Ibat_ref_Ems'],'LineHandles'); delete_line(lh.Outport(1));
    f = pos(FOF);
    add_block('simulink/Math Operations/Product', [CC '/LPF_to_bat'], 'Inputs','*/', ...
              'Position', [f(3)+60 f(4)+40 f(3)+100 f(4)+80]);
    p = pos('Ibat_ref_Ems');
    add_block('simulink/Math Operations/Sum', [CC '/Ibat_ref_tot'], 'Inputs','++', ...
              'Position', [p(3)+60 p(2)-10 p(3)+90 p(4)+10]);
    add_line(CC, [FOF '/1'], 'LPF_to_bat/1', 'autorouting','on');
    add_line(CC, 'Divide/1', 'LPF_to_bat/2', 'autorouting','on');      % Divide = V_bat/V_SC
    add_line(CC, 'Ibat_ref_Ems/1', 'Ibat_ref_tot/1', 'autorouting','on');
    add_line(CC, 'LPF_to_bat/1', 'Ibat_ref_tot/2', 'autorouting','on');
    add_line(CC, 'Ibat_ref_tot/1', 'Sum1/1', 'autorouting','on');
end

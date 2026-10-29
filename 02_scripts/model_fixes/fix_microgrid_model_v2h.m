%% fix_microgrid_model_v2h.m  -  break the Load Manager algebraic loop
% With [L] now reaching the loads, L -> loads -> P_load -> bus/PV -> P_def -> Load Manager is a
% direct-feedthrough loop. Real supervisory controllers act one sample later: add a Unit Delay
% (one EMS step = 1 real minute) on the Load Manager output L.
m = 'microgrid_top_fixed';  load_system(m);
d = [m '/L_delay'];
if getSimulinkBlockHandle(d) < 0
    lm = get_param([m '/Load Manager'],'PortHandles');
    g1 = get_param([m '/Goto1'],'PortHandles');
    delete_line(m, lm.Outport(1), g1.Inport(1));
    p = get_param([m '/Goto1'],'Position');
    set_param([m '/Goto1'],'Position', p + [80 0 80 0]);
    add_block('simulink/Discrete/Unit Delay', d, 'SampleTime','Ts_ems', 'InitialCondition','0', ...
              'Position',[p(1) p(2) p(1)+40 p(4)]);
    dp = get_param(d,'PortHandles');
    add_line(m, lm.Outport(1), dp.Inport(1), 'autorouting','on');
    add_line(m, dp.Outport(1), g1.Inport(1), 'autorouting','on');
end
save_system(m);
fprintf('L_delay inserted (Ts_ems = 1 real minute). Saved.\n');

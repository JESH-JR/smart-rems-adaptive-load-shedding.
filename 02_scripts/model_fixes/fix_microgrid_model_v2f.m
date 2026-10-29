%% fix_microgrid_model_v2f.m  -  SoC counter parameters (Discrete-Time Integrator gain must be positive)
% SoC[%] = SoC0*100 + 100/(3600*Q_sim_Ah) * integral(-i_bat dt)   (i_bat > 0 = discharge)
m = 'microgrid_top_fixed';  load_system(m);
b = [m '/SoC_coulomb'];
set_param(b,'gainval','100/(3600*Q_sim_Ah)');
set_param(b,'InitialCondition','SoC0*100');
set_param(b,'SampleTime','Ts');
set_param(b,'LimitOutput','on','UpperSaturationLimit','100','LowerSaturationLimit','0');
n = [m '/I_bat_neg'];
if getSimulinkBlockHandle(n) < 0
    ph  = get_param(b,'PortHandles');
    src = get_param(get_param(ph.Inport(1),'Line'),'SrcPortHandle');
    delete_line(m, src, ph.Inport(1));                       % only this branch; Goto7 [I_Bat] stays connected
    p = get_param(b,'Position');
    add_block('simulink/Math Operations/Gain', n, 'Gain','-1', 'Position',[p(1)-80 p(2) p(1)-40 p(4)]);
    g = get_param(n,'PortHandles');
    add_line(m, src, g.Inport(1), 'autorouting','on');
    add_line(m, g.Outport(1), ph.Inport(1), 'autorouting','on');
end
save_system(m);
fprintf('SoC_coulomb: gain %s, initial %s, input = -I_bat. Saved.\n', get_param(b,'gainval'), get_param(b,'InitialCondition'));

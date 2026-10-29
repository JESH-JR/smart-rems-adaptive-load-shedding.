%% fix_microgrid_model_v2g.m  -  make load shedding actually reach the loads
% Goto [L] (Load Manager output) was LOCAL at the top level, so the From [L] blocks inside the
% 'Loads' subsystem never saw it: loads_func always got L = 0 and nothing was ever shed.
% Also: log the slow signals (L, requested load) without decimation so the plot shows every step.
m = 'microgrid_top_fixed';  load_system(m);
set_param([m '/Goto1'], 'TagVisibility','global');
ph = get_param([m '/Load Manager'],'PortHandles');  set_param(ph.Outport(1),'DataLoggingDecimation','1');
ph = get_param([m '/Loads/kW_to_W'],'PortHandles'); set_param(ph.Outport(1),'DataLoggingDecimation','1');
set_param(m,'UnconnectedInputMsg','warning');               % never silently feed 0 again
save_system(m);
fprintf('Goto [L] is now %s. Saved.\n', get_param([m '/Goto1'],'TagVisibility'));

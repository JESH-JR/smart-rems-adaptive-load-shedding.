%% fix_microgrid_model_v2e.m  -  (1) wire the SoC counter  (2) current/duty limits + anti-windup
% (1) v2d created SoC_coulomb but could not wire it: the block is really named "Bus<newline>Selector1",
%     so lines are now made with port handles.
% (2) With no limits the voltage PI wound up, the battery current reference ran away, the duty hit 1 and
%     the battery was shorted through Q2 (2570 A, 131 V). Added:
%       - voltage PI output limit +-(I_bat_max + I_sc_max), clamping anti-windup
%       - battery current reference limit +-I_bat_max = 1.5*Pbmax/V_bat_nom (~156 A)
%       - SC current reference limit +-I_sc_max = 200 A
%       - current-loop PIs (duty) limited to 0...0.9 with clamping (never a permanent short)
root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(fullfile(root,'01_model'), fullfile(root,'01_model','_rebuild_source'), fullfile(root,'02_scripts'), fullfile(root,'02_scripts','model_fixes'), fullfile(root,'03_data'));
cd(fullfile(root,'01_model'));
evalin('base','init_microgrid');
mdl = 'microgrid_top_fixed';  load_system(mdl);
rep = {};
rep(end+1,:) = trystep('1. Wire SoC_coulomb (I_bat in, [SoC_Battery] out)', @() wire_soc(mdl));
rep(end+1,:) = trystep('2a. Voltage PI limit + anti-windup',              @() limit_vpi(mdl));
rep(end+1,:) = trystep('2b. Battery / SC current reference limits',       @() limit_refs(mdl));
rep(end+1,:) = trystep('2c. Duty limits 0...0.9 + anti-windup',           @() limit_duty(mdl));
save_system(mdl);
fprintf('\n===== fix_microgrid_model_v2e report =====\n');
for k = 1:size(rep,1)
    if rep{k,2}, fprintf('  OK    %s\n', rep{k,1}); else, fprintf('  FAIL  %s  ->  %s\n', rep{k,1}, rep{k,3}); end
end
fprintf('\nNext:  out = sim(''%s'',''StopTime'',''0.36'');   plot_test4(out,''short_3h'')\n\n', mdl);

function r = trystep(name, fh)
    try, fh(); r = {name, true, ''}; catch e, r = {name, false, e.message}; end
end

function wire_soc(mdl)
    bs  = find_system(mdl,'SearchDepth',1,'BlockType','BusSelector','OutputSignals','Voltage (V),Current (A),SOC (%)');
    bat = get_param([mdl '/Battery'],'PortHandles');
    bs  = bs(cellfun(@(b) any(get_param(get_param(bat.Outport(1),'Line'),'DstBlockHandle') == get_param(b,'Handle')), bs));
    if isempty(bs), error('battery bus selector not found'); end
    bsp = get_param(bs{1},'PortHandles');
    cnt = get_param([mdl '/SoC_coulomb'],'PortHandles');
    g8  = get_param([mdl '/Goto8'],'PortHandles');
    if get_param(cnt.Inport(1),'Line') < 0, add_line(mdl, bsp.Outport(2), cnt.Inport(1), 'autorouting','on'); end
    l = get_param(g8.Inport(1),'Line'); if l > 0, delete_line(l); end
    add_line(mdl, cnt.Outport(1), g8.Inport(1), 'autorouting','on');
    set_param(bsp.Outport(3),'DataLogging','off');
    set_param(cnt.Outport(1),'DataLogging','on','DataLoggingNameMode','Custom','DataLoggingName','SoC_bat', ...
              'DataLoggingDecimateData','on','DataLoggingDecimation','20');
end

function c = cc(mdl), c = [mdl '/Combined Control Battery//Supercapacitor']; end

function limit_vpi(mdl)
    set_param([cc(mdl) '/PID Controller'], 'LimitOutput','on', ...
        'UpperSaturationLimit','1.5*Pbmax*1e3/V_bat_nom + 200', ...
        'LowerSaturationLimit','-(1.5*Pbmax*1e3/V_bat_nom + 200)', 'AntiWindupMode','clamping');
end

function insert_sat(sys, srcBlk, dstBlk, dstPort, name, lim)
    s = get_param([sys '/' srcBlk],'PortHandles'); d = get_param([sys '/' dstBlk],'PortHandles');
    l = get_param(d.Inport(dstPort),'Line'); if l > 0, delete_line(l); end
    p = get_param([sys '/' srcBlk],'Position');
    add_block('simulink/Discontinuities/Saturation', [sys '/' name], 'UpperLimit',lim, 'LowerLimit',['-(' lim ')'], ...
              'Position',[p(3)+30 p(2) p(3)+60 p(4)]);
    n = get_param([sys '/' name],'PortHandles');
    add_line(sys, s.Outport(1), n.Inport(1), 'autorouting','on');
    add_line(sys, n.Outport(1), d.Inport(dstPort), 'autorouting','on');
end

function limit_refs(mdl)
    insert_sat(cc(mdl), 'Ibat_ref_tot', 'Sum1', 1, 'Ibat_ref_sat', '1.5*Pbmax*1e3/V_bat_nom');
    insert_sat(cc(mdl), 'Divide1',      'Sum2', 1, 'Isc_ref_sat',  '200');
end

function limit_duty(mdl)
    for p = {'PID Controller1','PID Controller2'}
        set_param([cc(mdl) '/' p{1}], 'LimitOutput','on','UpperSaturationLimit','0.9', ...
                  'LowerSaturationLimit','0','AntiWindupMode','clamping');
    end
    set_param([cc(mdl) '/Saturation'],  'UpperLimit','0.9');
    set_param([cc(mdl) '/Saturation1'], 'UpperLimit','0.9');
end

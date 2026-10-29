%% fix_pv_curtailment_hysteresis.m  -  stop on/off chattering of PV curtailment
% Each PV unit switches MPPT -> constant-voltage (curtailment) when SoC >= 98 %. With a plain
% comparison it toggled every few minutes around 98 %. Replaced by a Relay with hysteresis:
%   curtail ON at SoC >= 98 %, back to MPPT only when SoC <= 95 %.
m = 'microgrid_top_fixed';  load_system(m);
b = find_system(m,'LookUnderMasks','all','FollowLinks','on','Name','SOC_full');
if isempty(b), error('No SOC_full blocks found'); end
for k = 1:numel(b)
    s   = get_param(b{k},'Parent');
    pos = get_param(b{k},'Position');
    ph  = get_param(b{k},'PortHandles');
    src = get_param(get_param(ph.Inport(1),'Line'),'SrcPortHandle');
    ol  = get_param(ph.Outport(1),'Line');  dst = get_param(ol,'DstPortHandle');
    delete_line(s, src, ph.Inport(1));
    delete_line(ol);
    delete_block(b{k});
    r = [s '/SOC_full'];
    add_block('simulink/Discontinuities/Relay', r, 'Position',pos, ...
              'OnSwitchValue','98', 'OffSwitchValue','95', 'OnOutputValue','1', 'OffOutputValue','0');
    rp = get_param(r,'PortHandles');
    add_line(s, src, rp.Inport(1), 'autorouting','on');
    for d = dst(:)', add_line(s, rp.Outport(1), d, 'autorouting','on'); end
    fprintf('  %s/SOC_full -> Relay (on 98 %%, off 95 %%)\n', s);
end
save_system(m);
fprintf('Saved %s (%d PV units updated).\n', m, numel(b));

%% fix_rlc_series_rl.m  -  realistic RLC banks: series R-L (motor-like) in parallel with C
% Problem: ideal parallel inductors across an ideal source keep a permanent DC offset after
%          switching (current swung +30 / -105 A). Real loads have winding resistance.
% Each bank now = series R-L branch (carries P at the tier PF) || C (corrects to pf_corr):
%   R_s = V^2*pf^2/P,  X_s = V^2*pf^2*tan(phi)/P,  L_s = X_s/w,   tau = L_s/R_s = tan(phi)/w (~1.5-2 ms)
%   C   = P*(tan(phi) - tan(acos(pf_corr)))/(w*V^2)   (unchanged)
m = 'microgrid_top_fixed';  load_system(m);
copyfile(which([m '.slx']), strrep(which([m '.slx']),'.slx','_preSeriesRL.slx'), 'f');
S = [m '/AC Loads (RLC tier banks)'];
RLC = 'powerlib/Elements/Series RLC Branch'; load_system('powerlib');
banks = find_system(S,'SearchDepth',1,'RegExp','on','Name','^T\d_bank\d_');
n = 0;
for k = 1:numel(banks)
    nm = get_param(banks{k},'Name');
    if startsWith(nm,'RL_'), continue; end
    t  = regexp(nm,'^T(\d)_bank(\d)_','tokens','once');  j = str2double(t{1});  w = 2^(str2double(t{2})-1);
    set_param(banks{k},'BranchType','C');                        % keep only the capacitor in the old block
    rl = [S '/RL_' nm];
    if getSimulinkBlockHandle(rl) < 0
        p = get_param(banks{k},'Position');
        add_block(RLC, rl, 'Position', p + [60 0 60 0]);
        b  = get_param(banks{k},'PortHandles');  r = get_param(rl,'PortHandles');
        add_line(S, b.LConn(1), r.LConn(1), 'autorouting','on');   % same two nodes -> in parallel
        add_line(S, b.RConn(1), r.RConn(1), 'autorouting','on');
    end
    set_param(rl,'BranchType','RL', ...
        'Resistance', sprintf('V_ac^2*pf_tier(%d)^2/(%d*P_bank*1e3)', j, w), ...
        'Inductance', sprintf('V_ac^2*pf_tier(%d)^2*tan(acos(pf_tier(%d)))/(%d*P_bank*1e3*2*pi*f_ac)', j, j, w));
    n = n + 1;
end
save_system(m);
fprintf('%d banks converted to series R-L || C. Backup: %s_preSeriesRL.slx\n', n, m);

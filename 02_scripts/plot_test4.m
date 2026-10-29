function plot_test4(out, tag)
%PLOT_TEST4  Plots the integrated-model run and prints the health checks.
%   out = sim('microgrid_top_fixed','StopTime','0.36');  plot_test4(out,'short_3h')
if nargin < 2, tag = 'run'; end
root = fileparts(fileparts(mfilename('fullpath')));
t_hour = evalin('base','t_hour');
L = out.logsout;
g = @(n) L.getElement(n).Values;
get = @(n) deal(g(n).Time/t_hour, squeeze(g(n).Data));
[h,  Vdc] = get('V_DC');      [hb, Vb] = get('V_bat');   [~, Ib] = get('I_bat');  [~, SoC] = get('SoC_bat');
[hs, Vsc] = get('V_sc');      [hl, Pl] = get('P_load_meas');  [hp, Ppv] = get('P_PV');
[hr, Preq] = get('P_req_W');  [hL, Ls] = get('L');

fprintf('\n===== Test 4 health check (%s, %.2f real h) =====\n', tag, h(end));
k = h > 0.05*h(end);                                       % skip start-up transient
fprintf('V_DC          : %.1f ... %.1f V (ref 400)\n', min(Vdc(k)), max(Vdc(k)));
fprintf('Battery V     : %.1f ... %.1f V (nominal 240)\n', min(Vb(hb>0.05*h(end))), max(Vb(hb>0.05*h(end))));
fprintf('Battery SoC   : %.2f %% -> %.2f %%\n', SoC(1), SoC(end));
fprintf('Battery I     : %.1f ... %.1f A\n', min(Ib), max(Ib));
fprintf('SC voltage    : %.1f ... %.1f V\n', min(Vsc), max(Vsc));
fprintf('P_load_meas   : mean %.2f kW (requested %.2f kW)  -> sign %s\n', mean(Pl)/1e3, mean(Preq)/1e3, ...
        ternary(mean(Pl) > 0, 'OK (positive)', 'NEGATIVE: set LOAD_SIGN = -LOAD_SIGN'));
fprintf('PV power      : max %.1f kW\n', max(Ppv)/1e3);
fprintf('Load manager L: values seen %s\n', mat2str(unique(round(Ls))'));
hasAC = any(strcmp(L.getElementNames,'P_ac'));
if hasAC
    [ha, Pac] = get('P_ac'); [~, Qac] = get('Q_ac'); [~, PFac] = get('PF_ac');
    ka = ha > 0.2;
    fprintf('AC side (RLC): P_ac mean %.2f kW, Q_ac mean %.2f kvar, PF %.3f ... %.3f (when loaded)\n', ...
            mean(Pac(ka))/1e3, mean(Qac(ka))/1e3, min(PFac(ka & Pac > 500)), max(PFac(ka & Pac > 500)));
end
fprintf('\n');

f = figure('Color','w','Position',[60 40 1100 1250]);
tl = tiledlayout(f,6+hasAC,1,'TileSpacing','compact','Padding','compact');
ax = nexttile(tl); plot(ax,h,Vdc); yline(ax,400,'--r'); ylabel(ax,'V_{DC} (V)'); grid(ax,'on');
ax = nexttile(tl); yyaxis(ax,'left'); plot(ax,hb,Vb); ylabel(ax,'V_{bat} (V)');
                   yyaxis(ax,'right'); plot(ax,hb,SoC); ylabel(ax,'SoC (%)'); grid(ax,'on');
ax = nexttile(tl); plot(ax,hb,Ib); ylabel(ax,'I_{bat} (A)'); grid(ax,'on');
ax = nexttile(tl); plot(ax,hs,Vsc); ylabel(ax,'V_{SC} (V)'); grid(ax,'on');
ax = nexttile(tl); plot(ax,hp,Ppv/1e3, hl,Pl/1e3, hr,Preq/1e3,'--'); ylabel(ax,'Power (kW)');
                   legend(ax,{'P_{PV}','P_{load} measured','P_{load} requested'},'Location','best'); grid(ax,'on');
if hasAC
    ax = nexttile(tl); yyaxis(ax,'left'); plot(ax,ha,Pac/1e3,ha,Qac/1e3); ylabel(ax,'P_{ac} (kW), Q_{ac} (kvar)');
    yyaxis(ax,'right'); plot(ax,ha,PFac); ylim(ax,[0.8 1.01]); ylabel(ax,'PF'); grid(ax,'on');
    legend(ax,{'P_{ac}','Q_{ac}','PF'},'Location','best');
end
ax = nexttile(tl); stairs(ax,hL,Ls,'LineWidth',1.5); ylim(ax,[-0.2 3.2]); yticks(ax,0:3); ylabel(ax,'State L'); grid(ax,'on');
xlabel(ax,'Time of day (h)');
title(tl, sprintf('Test 4: integrated microgrid (%s)', strrep(tag,'_',' ')), 'FontWeight','bold');
od = fullfile(root,'04_results','test4_integrated_24h',tag);
if ~exist(od,'dir'), mkdir(od); end
exportgraphics(f, fullfile(od,'test4_overview.png'), 'Resolution',150);
logsout = L; save(fullfile(od,'test4_logs.mat'),'logsout','-v7.3');
if hasAC                                                   % AC current at the first shedding step
    [hv, vac] = get('v_ac'); [~, iac] = get('i_ac'); iL = find(diff(round(Ls)) > 0, 1);
    if ~isempty(iL)
        tc = hL(iL+1); w = hv > tc - 0.05/t_hour*0 - 0.4 & hv < tc + 0.6;   % +-0.5 real h around the change
        f2 = figure('Color','w','Position',[80 80 1100 500]); tl2 = tiledlayout(f2,2,1,'TileSpacing','compact');
        ax = nexttile(tl2); plot(ax,(hv(w)-tc)*t_hour*1e3, vac(w)); ylabel(ax,'v_{ac} (V)'); grid(ax,'on');
        ax = nexttile(tl2); plot(ax,(hv(w)-tc)*t_hour*1e3, iac(w)); ylabel(ax,'i_{ac} (A)'); grid(ax,'on');
        xlabel(ax,'Simulation time around the shedding step (ms)');
        title(tl2, sprintf('AC side at the shedding step L: %d -> %d (%.2f h)', round(Ls(iL)), round(Ls(iL+1)), tc), 'FontWeight','bold');
        exportgraphics(f2, fullfile(od,'test4_ac_shedding.png'), 'Resolution',150);
    end
end
fprintf('Saved: %s\n', od);
end
function v = ternary(c,a,b), if c, v = a; else, v = b; end, end

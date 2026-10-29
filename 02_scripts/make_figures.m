function make_figures()
%MAKE_FIGURES  Publication-quality figures (white background, black axes, large fonts) for PPT + report.
%   Reads the saved results in 04_results and writes PNG (300 dpi, for PPT) + PDF (vector, for LaTeX)
%   to 04_results/figures_final/.  Needs: run_test1_pv (both days), build_chb_inverter,
%   Test 4 clear_24h + cloudy_24h.
root = fileparts(fileparts(mfilename('fullpath')));
R4 = fullfile(root,'04_results');  OUT = fullfile(root,'04_results','figures_final');
if ~exist(OUT,'dir'), mkdir(OUT); end
C = struct('blue',[0 0.35 0.75],'orange',[0.90 0.45 0.05],'green',[0.10 0.55 0.20], ...
           'red',[0.80 0.10 0.10],'gray',[0.45 0.45 0.45],'light',[0.75 0.83 0.95],'purple',[0.45 0.20 0.60]);
th1 = 0.05;  th4 = 0.12;                                   % sim seconds per real hour (Test 1 / Test 4)
done = {};

%% ---------------- Test 1: weather input (NASA POWER) ----------------
try
    T = readtable(fullfile(root,'03_data','pv_daily_profile.csv'));
    f = newfig(); ax = axes(f); hold(ax,'on');
    yyaxis(ax,'left');  plot(ax,T.time_h,T.G_clear_Wm2,'-','Color',C.orange,'LineWidth',2.2);
                        plot(ax,T.time_h,T.G_cloudy_Wm2,'--','Color',C.orange,'LineWidth',2.0);
    ylabel(ax,'Irradiance G (W/m^2)'); ylim(ax,[0 1100]); ax.YColor = 'k';
    yyaxis(ax,'right'); plot(ax,T.time_h,T.Tcell_clear_C,'-','Color',C.red,'LineWidth',2.0);
                        plot(ax,T.time_h,T.T_amb_C,':','Color',C.red,'LineWidth',2.0);
    ylabel(ax,'Temperature (\circC)'); ylim(ax,[15 75]); ax.YColor = 'k';
    fmt(ax,'Time of day (h)', 'NASA POWER weather input, Coimbatore (11.02\circN, 76.96\circE)', true);
    legend(ax,{'G, clear day (9 May 2025)','G, partly cloudy (16 May 2025)','Cell temperature (clear)','Ambient (clear)'},'Location','northwest');
    done{end+1} = save2(f,OUT,'fig01_weather_input');
catch e, warning('fig01: %s', e.message); end

%% ---------------- Test 1: PV unit ----------------
try
    [hc,Pc,Vc,Ic,Dc,Bc] = pv1(fullfile(R4,'test1_pv','nasa_clear','test1_pv_clear.mat'), th1);
    [hk,Pk]             = pv1(fullfile(R4,'test1_pv','nasa_cloudy','test1_pv_cloudy.mat'), th1);
    Ec = trapz(hc,max(Pc,0)); Ek = trapz(hk,max(Pk,0));
    f = newfig(); ax = axes(f); hold(ax,'on');
    area(ax,hc,Pc,'FaceColor',C.light,'EdgeColor','none','FaceAlpha',0.6);
    plot(ax,hc,Pc,'Color',C.blue,'LineWidth',2.2); plot(ax,hk,Pk,'--','Color',C.orange,'LineWidth',2.2);
    yline(ax,19.2,'--','Rated 19.2 kW (STC)','Color',C.gray,'LineWidth',1.4,'FontSize',13,'LabelHorizontalAlignment','left');
    ylim(ax,[0 22]); ylabel(ax,'PV power P_{PV} (kW)');
    fmt(ax,'Time of day (h)', 'Test 1: one 19.2 kW PV unit with P&O MPPT', true);
    legend(ax,{'',sprintf('Clear day: peak %.1f kW, %.1f kWh',max(Pc),Ec),sprintf('Partly cloudy: peak %.1f kW, %.1f kWh',max(Pk),Ek)},'Location','northwest');
    done{end+1} = save2(f,OUT,'fig02_pv_power_clear_vs_cloudy');

    f = newfig(1400,1000); tl = tiledlayout(f,3,1,'TileSpacing','compact','Padding','compact');
    ax = nexttile(tl); plot(ax,hc,Vc,'Color',C.blue,'LineWidth',1.8); yline(ax,240,'--','V_{mp} at STC = 240 V','Color',C.gray,'FontSize',12);
    ylabel(ax,'V_{PV} (V)'); ylim(ax,[0 280]); fmt(ax,'','',true);
    ax = nexttile(tl); plot(ax,hc,Ic,'Color',C.blue,'LineWidth',1.8); yline(ax,80,'--','I_{mp} at STC = 80 A','Color',C.gray,'FontSize',12);
    ylabel(ax,'I_{PV} (A)'); ylim(ax,[0 95]); fmt(ax,'','',true);
    ax = nexttile(tl); plot(ax,hc,Dc,'Color',C.blue,'LineWidth',1.8); yline(ax,0.42,':','Night parking 0.42','Color',C.gray,'FontSize',12);
    ylabel(ax,'Duty ratio D'); ylim(ax,[0.3 0.65]); fmt(ax,'Time of day (h)','',true);
    ttl(tl,'Test 1: PV voltage, current and boost duty ratio (clear day)');
    done{end+1} = save2(f,OUT,'fig03_pv_V_I_duty_clear');

    f = newfig(); ax = axes(f); plot(ax,hc,Bc,'Color',C.blue,'LineWidth',2);
    yline(ax,400,'--','Reference 400 V','Color',C.red,'LineWidth',1.4,'FontSize',13,'LabelHorizontalAlignment','left');
    ylim(ax,[396 410]); ylabel(ax,'DC bus voltage (V)');
    fmt(ax,'Time of day (h)', sprintf('Test 1: DC bus voltage, max deviation %.1f %%', 100*(max(Bc)-400)/400), true);
    done{end+1} = save2(f,OUT,'fig04_pv_dc_bus');

    evalin('base','init_microgrid'); prof = evalin('base','prof');  Pl = sum(prof,2);  Pf = prof(:,1)+prof(:,2);
    f = newfig(); ax = axes(f); hold(ax,'on'); hh = (0:24)';
    stairs(ax,hh,[Pl;Pl(end)],'Color',C.red,'LineWidth',2.4); stairs(ax,hh,[Pf;Pf(end)],'--','Color',C.purple,'LineWidth',2);
    plot(ax,hc,2*Pc,'Color',C.blue,'LineWidth',2.2); plot(ax,hk,2*Pk,'--','Color',C.orange,'LineWidth',2.2);
    ylabel(ax,'Power (kW)'); ylim(ax,[0 36]);
    fmt(ax,'Time of day (h)', 'PV generation (2 x 19.2 kW) and demand of the 12-flat block', true);
    legend(ax,{sprintf('Total demand (%.0f kWh/day)',sum(Pl)),sprintf('Firm demand, Tiers 1+2 (%.0f kWh)',sum(Pf)), ...
               sprintf('PV clear (%.0f kWh)',2*Ec),sprintf('PV partly cloudy (%.0f kWh)',2*Ek)},'Location','northwest');
    done{end+1} = save2(f,OUT,'fig05_pv_vs_demand');
catch e, warning('Test 1 figures: %s', e.message); end

%% ---------------- Test 2: CHB inverter ----------------
try
    S = load(fullfile(R4,'test2_inverter','v2_new_model','test2_data.mat'));
    D = S.R.damped_full; U = S.R.undamped_full; f0 = S.P.f0; Tst = S.P.T_stop;
    ss = D.t > Tst - 2/f0;  tt = (D.t(ss) - D.t(find(ss,1)))*1e3;
    f = newfig(); ax = axes(f); hold(ax,'on');
    plot(ax,tt,D.vi(ss),'Color',C.light,'LineWidth',1.0); plot(ax,tt,D.vo(ss),'Color',C.blue,'LineWidth',2.4);
    ylabel(ax,'Voltage (V)'); ylim(ax,[-450 450]); yticks(ax,-400:200:400);
    fmt(ax,'Time (ms)', 'Test 2: five-level CHB inverter output', false); xlim(ax,[0 40]); xticks(ax,0:5:40);
    legend(ax,{'Inverter output (levels 0, \pm200, \pm400 V)','Filtered output, 226 V rms'},'Location','southoutside','Orientation','horizontal');
    done{end+1} = save2(f,OUT,'fig06_chb_voltage');
    f = newfig(); ax = axes(f); plot(ax,tt,D.io(ss),'Color',C.blue,'LineWidth',2.2);
    ylabel(ax,'Load current (A)'); fmt(ax,'Time (ms)','Test 2: inverter output current (4.3 kW load)',false); xlim(ax,[0 40]); xticks(ax,0:5:40);
    done{end+1} = save2(f,OUT,'fig07_chb_current');
    f = newfig(); ax = axes(f); k = 2:50;
    b = bar(ax,k,[100*U.Hv(k)/U.V1; 100*D.Hv(k)/D.V1]','grouped'); b(1).FaceColor = C.gray; b(2).FaceColor = C.blue;
    ylabel(ax,'Magnitude (% of fundamental)'); xlim(ax,[1 51]);
    T50d = 100*sqrt(sum(D.Hv(2:50).^2))/D.V1; T50u = 100*sqrt(sum(U.Hv(2:50).^2))/U.V1;
    fmt(ax,'Harmonic order', sprintf('Test 2: voltage harmonics up to the 50th (THD %.2f %%, IEEE 519 limit 8 %%)', T50d), false);
    legend(ax,{sprintf('Undamped filter (THD %.2f %%)',T50u),sprintf('Damped filter, R_d = 2 \\Omega (THD %.2f %%)',T50d)},'Location','northeast');
    done{end+1} = save2(f,OUT,'fig08_chb_harmonics');
catch e, warning('Test 2 figures (run build_chb_inverter once so it saves test2_data.mat): %s', e.message); end

%% ---------------- Test 4: integrated system ----------------
days = {'clear_24h','clear','Clear day (9 May 2025)'; 'cloudy_24h','cloudy','Partly cloudy day (16 May 2025)'};
Z = struct();
for d = 1:2
    try
        L = load(fullfile(R4,'test4_integrated_24h',days{d,1},'test4_logs.mat')); L = L.logsout;
        g = @(n) deal(L.getElement(n).Values.Time/th4, squeeze(L.getElement(n).Values.Data));
        [h,Vdc] = g('V_DC'); [hb,Ib] = g('I_bat'); [hs,SoC] = g('SoC_bat'); [hc2,Vsc] = g('V_sc');
        [hp,Ppv] = g('P_PV'); [hl,Pl] = g('P_load_meas'); [hr,Pr] = g('P_req_W'); [hL,Ls] = g('L');
        if max(SoC) > 1.5, SoC = SoC/100; end
        % clean display: remove single-sample mode-switch spikes, average the converter switching ripple (~1 real minute)
        Ppv = sm(Ppv,100); Pl = sm(Pl,100); Vdc = sm(Vdc,100); Ib = sm(Ib,100); Vsc = sm(Vsc,100);
        Z.(days{d,2}) = struct('hs',hs,'SoC',SoC,'hL',hL,'L',Ls);
        n0 = 9 + 4*(d-1);  nm = days{d,2};  dl = days{d,3};
        % (a) power balance
        f = newfig(); ax = axes(f); hold(ax,'on');
        try, prof = evalin('base','prof'); catch, evalin('base','init_microgrid'); prof = evalin('base','prof'); end
        Pd = sum(prof,2);                                            % hourly demand of the 12 flats before shedding
        plot(ax,hp,Ppv/1e3,'Color',C.blue,'LineWidth',2.2);
        stairs(ax,(0:24)',[Pd;Pd(end)],':','Color','k','LineWidth',2.2);
        plot(ax,hl,Pl/1e3,'Color',C.red,'LineWidth',2.4);
        ylabel(ax,'Power (kW)'); ylim(ax,[-2 36]);
        fmt(ax,'Time of day (h)', ['Test 4: power balance - ' dl], true);
        legend(ax,{'PV power (2 units)','Demand before shedding','Load served (DC side, incl. 4 % inverter loss)'},'Location','northwest');
        done{end+1} = save2(f,OUT,sprintf('fig%02d_t4_%s_power', n0, nm));
        % (b) SoC + load manager state
        f = newfig(1400,900); tl = tiledlayout(f,2,1,'TileSpacing','compact','Padding','compact');
        ax = nexttile(tl); hold(ax,'on'); plot(ax,hs,100*SoC,'Color',C.green,'LineWidth',2.4);
        for v = [40 30 20], yline(ax,v,'--','Color',C.gray,'LineWidth',1.2); end
        text(ax,14.6,43,'\theta_1 = 40 % (shed Tier 3)','FontSize',12,'FontName','Times New Roman');
        text(ax,14.6,33,'\theta_2 = 30 % (shed Tier 2)','FontSize',12,'FontName','Times New Roman');
        text(ax,14.6,23,'SoC_{min} = 20 % (outage)','FontSize',12,'FontName','Times New Roman');
        ylabel(ax,'Battery SoC (%)'); ylim(ax,[0 100]); fmt(ax,'','',true);
        ax = nexttile(tl); stairs(ax,hL,Ls,'Color',C.purple,'LineWidth',2.4); ylim(ax,[-0.2 3.2]); yticks(ax,0:3);
        yticklabels(ax,{'L0 normal','L1 shed T3','L2 critical','L3 outage'}); fmt(ax,'Time of day (h)','',true);
        ttl(tl,['Test 4: battery SoC and adaptive load shedding - ' dl]);
        done{end+1} = save2(f,OUT,sprintf('fig%02d_t4_%s_soc_shedding', n0+1, nm));
        % (c) DC bus voltage
        f = newfig(); ax = axes(f); plot(ax,h,Vdc,'Color',C.blue,'LineWidth',1.8);
        yline(ax,400,'--','Reference 400 V','Color',C.red,'LineWidth',1.4,'FontSize',13,'LabelHorizontalAlignment','left');
        k = h > 0.5; ylim(ax,[380 420]); ylabel(ax,'DC bus voltage (V)');
        fmt(ax,'Time of day (h)', sprintf('Test 4: DC bus voltage %.1f - %.1f V - %s', min(Vdc(k)), max(Vdc(k)), dl), true);
        done{end+1} = save2(f,OUT,sprintf('fig%02d_t4_%s_dc_bus', n0+2, nm));
        % (d) battery current + supercapacitor voltage (HESS split)
        f = newfig(1400,900); tl = tiledlayout(f,2,1,'TileSpacing','compact','Padding','compact');
        ax = nexttile(tl); plot(ax,hb,Ib,'Color',C.green,'LineWidth',1.8); yline(ax,0,':','Color',C.gray);
        ylabel(ax,'Battery current (A)'); ylim(ax,[-150 200]); fmt(ax,'','',true);
        text(ax,16,170,'+ discharge  /  - charge','FontSize',12,'FontName','Times New Roman');
        ax = nexttile(tl); plot(ax,hc2,Vsc,'Color',C.orange,'LineWidth',1.8);
        ylabel(ax,'SC voltage (V)'); ylim(ax,[248 251]); fmt(ax,'Time of day (h)','',true);
        ttl(tl,['Test 4: battery current and supercapacitor voltage - ' dl]);
        done{end+1} = save2(f,OUT,sprintf('fig%02d_t4_%s_battery_sc', n0+3, nm));
    catch e, warning('Test 4 %s: %s', days{d,1}, e.message); end
end
try    % clear vs cloudy comparison
    f = newfig(1400,900); tl = tiledlayout(f,2,1,'TileSpacing','compact','Padding','compact');
    ax = nexttile(tl); hold(ax,'on');
    plot(ax,Z.clear.hs,100*Z.clear.SoC,'Color',C.blue,'LineWidth',2.4);
    plot(ax,Z.cloudy.hs,100*Z.cloudy.SoC,'--','Color',C.orange,'LineWidth',2.4);
    yline(ax,40,':','\theta_1 = 40 %','Color',C.gray,'FontSize',12,'LabelHorizontalAlignment','left');
    ylabel(ax,'Battery SoC (%)'); ylim(ax,[20 100]); fmt(ax,'','',true); legend(ax,{'Clear day','Partly cloudy day'},'Location','south');
    ax = nexttile(tl); hold(ax,'on');                       % timeline: bar = Tier 3 shed (L >= 1)
    bars(ax, Z.clear.hL,  Z.clear.L,  2, C.blue);
    bars(ax, Z.cloudy.hL, Z.cloudy.L, 1, C.orange);
    ylim(ax,[0.4 2.6]); yticks(ax,[1 2]); yticklabels(ax,{'Partly cloudy','Clear day'});
    fmt(ax,'Time of day (h)','Tier 3 (deferrable) shed periods',true); ax.YGrid = 'off';
    ttl(tl,'Test 4: clear vs partly cloudy day - SoC and load shedding');
    done{end+1} = save2(f,OUT,'fig17_t4_clear_vs_cloudy');
catch e, warning('comparison: %s', e.message); end

fprintf('\n%d figures written to %s (PNG 300 dpi + PDF):\n', numel(done), OUT); fprintf('  %s\n', done{:});
end

%% ===================== helpers =====================
function f = newfig(w,h)
    if nargin < 1, w = 1400; h = 720; end
    f = figure('Color','w','Position',[60 60 w h],'InvertHardcopy','off');
    try, theme(f,'light'); catch, end
end
function fmt(ax, xl, tt, isDay)
    set(ax,'Color','w','XColor','k','YColor','k','FontName','Times New Roman','FontSize',15,'LineWidth',1.1, ...
        'Box','on','GridColor',[0.6 0.6 0.6],'GridAlpha',0.5,'TickDir','out');
    grid(ax,'on');
    if isDay, xlim(ax,[0 24]); xticks(ax,0:2:24); end
    if ~isempty(xl), xlabel(ax,xl,'FontSize',16,'Color','k'); end
    if ~isempty(tt), title(ax,tt,'FontSize',17,'FontWeight','bold','Color','k'); end
    ax.YLabel.FontSize = 16; ax.YLabel.Color = 'k';
end
function ttl(tl, s)
    title(tl, s, 'FontSize',18, 'FontWeight','bold', 'FontName','Times New Roman', 'Color','k');
end
function name = save2(f, OUT, name)
    lg = findobj(f,'Type','Legend');
    for k = 1:numel(lg), set(lg(k),'FontSize',13,'TextColor','k','Color','w','EdgeColor',[0.6 0.6 0.6],'FontName','Times New Roman'); end
    exportgraphics(f, fullfile(OUT,[name '.png']), 'Resolution',300, 'BackgroundColor','white');
    exportgraphics(f, fullfile(OUT,[name '.pdf']), 'ContentType','vector', 'BackgroundColor','white');
    close(f);
end
function bars(ax, h, L, y, col)
    on = round(L(:)) >= 1;  d = diff([0; on; 0]);  i1 = find(d == 1);  i2 = find(d == -1) - 1;
    for k = 1:numel(i1)
        t1 = h(i1(k));  t2 = h(min(i2(k)+1, numel(h)));
        patch(ax, [t1 t2 t2 t1], [y-0.3 y-0.3 y+0.3 y+0.3], col, 'EdgeColor','none', 'FaceAlpha',0.85);
        if t2 - t1 < 1.5, continue; end                        % too narrow for a label (e.g. 23:45-24:00)
        m1 = round(t1*60); m2 = round(t2*60);
        text(ax, (t1+t2)/2, y, sprintf('%02d:%02d - %02d:%02d', floor(m1/60), mod(m1,60), floor(m2/60), mod(m2,60)), ...
             'HorizontalAlignment','center','Color','w','FontWeight','bold','FontSize',12,'FontName','Times New Roman');
    end
end
function y = sm(x, n)
    x = x(:); y = movmean(movmedian(x,41), n);   % 41-sample median removes switching spikes
end
function [h,P,Vv,I,D,B] = pv1(file, th)
    S = load(file); pv = S.pvdata; nav = 11;
    e = @(k) squeeze(pv.getElement(k).Values.Data);
    h = pv.getElement(1).Values.Time/th;
    Vv = movmean(e(1),nav); I = movmean(e(2),nav); P = movmean(e(3),nav)/1e3; D = movmean(e(4),nav); B = movmean(e(5),nav);
end

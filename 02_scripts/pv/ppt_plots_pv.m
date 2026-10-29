%% ppt_plots_pv.m  -  slide-ready plots of the PV unit (19.2 kW, 6S x 8P), 24 h
% Makes 5 separate PNGs (one per slide) + one combined figure + the weather input.
% White background, large fonts, time axis in real hours (0-24 h).
%
% Uses the results of your last Run of PV_Unit_day.slx (variable 'out').
% If 'out' is not in the workspace, the model is simulated first (3-8 min).
%
% Run:  ppt_plots_pv

mdl    = 'PV_Unit_day';
t_hour = 0.05;          % simulated seconds per real hour
P_rated = 19.2;         % kW, one unit (6S x 8P)
navg   = 11;            % samples for the average line (~1 real minute)

%% ---------------- get the results ----------------
haveOut = evalin('base', 'exist(''out'',''var'') == 1');
if haveOut
    out = evalin('base', 'out');
    haveOut = isprop(out,'pvdata') || any(strcmp(out.who, 'pvdata'));
end
if ~haveOut
    fprintf('No results in the workspace: simulating %s (3-8 min)...\n', mdl);
    load_system(mdl);
    out = sim(mdl);
end

pv = out.pvdata;
sigk = @(k) deal(pv.getElement(k).Values.Time/t_hour, squeeze(pv.getElement(k).Values.Data));
[h, Vpv] = sigk(1);
[~, Ipv] = sigk(2);
[~, Ppv] = sigk(3);
[~, Dty] = sigk(4);
[~, Vbus] = sigk(5);
Ppv = Ppv/1000;                                  % W -> kW

E_day  = trapz(h, max(Ppv,0));                   % kWh (h already in real hours)
[Pmax, ip] = max(movmean(Ppv,navg));
Imax   = max(movmean(Ipv,navg));
day    = Ppv > 0.2;                              % daytime samples
Vnoon  = mean(Vpv(abs(h - h(ip)) < 0.5));

fprintf('\n===== PV unit, 24 h =====\n');
fprintf('Peak power   : %.1f kW at %02d:%02d\n', Pmax, floor(h(ip)), round(mod(h(ip),1)*60));
fprintf('Peak current : %.0f A\n', Imax);
fprintf('Noon voltage : %.0f V\n', Vnoon);
fprintf('Daily energy : %.1f kWh (one unit), %.1f kWh (two units)\n\n', E_day, 2*E_day);

%% ---------------- colours ----------------
c.raw  = [0.70 0.80 0.95];   % light blue: instantaneous (includes ripple)
c.avg  = [0.00 0.30 0.75];   % dark blue: average
c.ref  = [0.80 0.20 0.10];   % red: reference lines

%% ---------------- 1. PV voltage ----------------
f = newfig();
plot(h, Vpv, 'Color',c.raw, 'LineWidth',0.8); hold on;
plot(h, movmean(Vpv,navg), 'Color',c.avg, 'LineWidth',2.2);
yline(240, '--', 'V_{mp} at STC = 240 V', 'Color',c.ref, 'LineWidth',1.4, ...
      'FontSize',13, 'LabelHorizontalAlignment','left');
ylim([0 280]); ylabel('PV voltage  V_{PV}  (V)');
title(sprintf('PV Voltage: tracked by MPPT, about %.0f V at noon (hot cells)', Vnoon));
legend({'Instantaneous','Average'}, 'Location','northeast');
finish(f, 'PPT_1_PV_voltage.png');

%% ---------------- 2. PV current ----------------
f = newfig();
plot(h, Ipv, 'Color',c.raw, 'LineWidth',0.8); hold on;
plot(h, movmean(Ipv,navg), 'Color',c.avg, 'LineWidth',2.2);
yline(80, '--', 'I_{mp} at STC = 80 A', 'Color',c.ref, 'LineWidth',1.4, ...
      'FontSize',13, 'LabelHorizontalAlignment','left');
ylim([0 95]); ylabel('PV current  I_{PV}  (A)');
title(sprintf('PV Current: follows irradiance, peak %.0f A', Imax));
legend({'Instantaneous','Average'}, 'Location','northeast');
finish(f, 'PPT_2_PV_current.png');

%% ---------------- 3. PV power ----------------
f = newfig();
area(h, max(movmean(Ppv,navg),0), 'FaceColor',[0.85 0.90 0.98], 'EdgeColor','none'); hold on;
plot(h, movmean(Ppv,navg), 'Color',c.avg, 'LineWidth',2.2);
yline(P_rated, '--', sprintf('Rated %.1f kW (STC)', P_rated), 'Color',c.ref, 'LineWidth',1.4, ...
      'FontSize',13, 'LabelHorizontalAlignment','left');
ylim([0 22]); ylabel('PV power  P_{PV}  (kW)');
title(sprintf('PV Power: peak %.1f kW, %.1f kWh/day (one 19.2 kW unit)', Pmax, E_day));
legend({sprintf('Energy = %.1f kWh', E_day),'Power'}, 'Location','northeast');
finish(f, 'PPT_3_PV_power.png');

%% ---------------- 4. Duty cycle ----------------
f = newfig();
plot(h, Dty, 'Color',c.raw, 'LineWidth',0.8); hold on;
plot(h, movmean(Dty,navg), 'Color',c.avg, 'LineWidth',2.2);
yline(0.42, ':', 'Night parking D = 0.42', 'Color',[0.3 0.3 0.3], 'LineWidth',1.4, ...
      'FontSize',13, 'LabelHorizontalAlignment','left', 'LabelVerticalAlignment','bottom');
yline(0.36, '--', 'Lower limit 0.36', 'Color',c.ref, 'LineWidth',1.2, 'FontSize',12, ...
      'LabelHorizontalAlignment','right', 'LabelVerticalAlignment','bottom');
yline(0.60, '--', 'Upper limit 0.60', 'Color',c.ref, 'LineWidth',1.2, 'FontSize',12, ...
      'LabelHorizontalAlignment','right');
ylim([0.30 0.65]); ylabel('Boost duty cycle  D');
title('Duty Cycle from P&O MPPT:  V_{PV} = (1 - D) \times 400 V');
legend({'Instantaneous','Average'}, 'Location','northeast');
finish(f, 'PPT_4_duty_cycle.png');

%% ---------------- 5. DC bus voltage ----------------
f = newfig();
plot(h, Vbus, 'Color',c.raw, 'LineWidth',0.8); hold on;
plot(h, movmean(Vbus,navg), 'Color',c.avg, 'LineWidth',2.2);
yline(400, '--', 'Bus reference 400 V', 'Color',c.ref, 'LineWidth',1.4, ...
      'FontSize',13, 'LabelHorizontalAlignment','left', 'LabelVerticalAlignment','bottom');
ylim([396 410]); ylabel('DC bus voltage  V_{DC}  (V)');
title(sprintf('DC Bus Voltage: stays within %.1f %% of 400 V', 100*(max(Vbus)-400)/400));
legend({'Instantaneous','Average'}, 'Location','northeast');
finish(f, 'PPT_5_DC_bus_voltage.png');

%% ---------------- combined figure (all 5) ----------------
f = figure('Color','w','Position',[50 30 1100 1300]);
try, theme(f,'light'); end
tl = tiledlayout(f,5,1,'TileSpacing','compact','Padding','compact');
sig = {Vpv, Ipv, Ppv, Dty, Vbus};
lab = {'V_{PV} (V)','I_{PV} (A)','P_{PV} (kW)','Duty D','V_{DC} (V)'};
yl  = {[0 280],[0 95],[0 22],[0.30 0.65],[396 410]};
for k = 1:5
    ax = nexttile(tl);
    plot(ax, h, sig{k}, 'Color',c.raw, 'LineWidth',0.6); hold(ax,'on');
    plot(ax, h, movmean(sig{k},navg), 'Color',c.avg, 'LineWidth',1.8);
    ylabel(ax, lab{k}); ylim(ax, yl{k}); style(ax, 13);
    if k < 5, ax.XTickLabel = []; else, xlabel(ax,'Time of day (h)'); end
end
if evalin('base','exist(''dayLabel'',''var'')'), dl = evalin('base','dayLabel'); else, dl = 'Clear Day'; end
title(tl, ['PV Unit (19.2 kW, 6S \times 8P): 24 h ' dl ', Coimbatore'], 'FontSize',17, 'FontWeight','bold', 'Color','k');
exportgraphics(f, 'PPT_PV_all_outputs.png', 'Resolution',200, 'BackgroundColor','white');

%% ---------------- weather input (useful for the model slide) ----------------
if isprop(out,'wxdata') || any(strcmp(out.who, 'wxdata'))
    wx = out.wxdata;
    hg = wx.getElement(1).Values.Time/t_hour;
    G  = squeeze(wx.getElement(1).Values.Data);
    Tc = squeeze(wx.getElement(2).Values.Data);
    f = newfig();
    yyaxis left;  stairs(hg, G,  'Color',[0.95 0.6 0.0], 'LineWidth',2.2);
    ylabel('Irradiance  G  (W/m^2)'); ylim([0 1100]); ax = gca; ax.YColor = 'k';
    yyaxis right; stairs(hg, Tc, 'Color',[0.80 0.20 0.10], 'LineWidth',2.2);
    ylabel('Cell temperature  T_{cell}  (\circC)'); ylim([20 70]); ax.YColor = 'k';
    title('Model Input: 24 h Irradiance and Cell Temperature (15-min steps)');
    legend({'Irradiance','Cell temperature'}, 'Location','northwest');
    finish(f, 'PPT_0_weather_input.png');
end

fprintf('Saved: PPT_0_weather_input.png, PPT_1 ... PPT_5 (one per slide), PPT_PV_all_outputs.png\n');

%% =============== helpers ===============
function f = newfig()
    f = figure('Color','w','Position',[80 80 1280 620]);   % 16:9-friendly
    try, theme(f,'light'); end
    axes(f);
end

function style(ax, fs)
    set(ax, 'Color','w', 'XColor','k', 'YColor','k', 'GridColor',[0.75 0.75 0.75], ...
        'GridAlpha',0.6, 'FontSize',fs, 'LineWidth',1, 'Box','on', ...
        'XLim',[0 24], 'XTick',0:2:24);
    grid(ax,'on');  ax.Toolbar.Visible = 'off';
end

function finish(f, name)
    ax = gca;  style(ax, 15);
    xlabel(ax, 'Time of day (h)');
    ax.Title.FontSize = 17;  ax.Title.Color = 'k';
    ax.YLabel.FontSize = 16; ax.XLabel.FontSize = 16;
    lg = findobj(f,'Type','Legend');
    if ~isempty(lg), set(lg,'FontSize',13,'TextColor','k','Color','w','EdgeColor',[0.6 0.6 0.6]); end
    exportgraphics(f, name, 'Resolution',200, 'BackgroundColor','white');
end

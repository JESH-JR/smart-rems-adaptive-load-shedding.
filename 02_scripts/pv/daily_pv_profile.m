%% daily_pv_profile.m  -  RET project, Model 1: PV source (24-hour study)
% Daily PV output of the 6S x 3P, 7.2 kW array for Coimbatore, for a
% clear day and a partly cloudy day, including the cell-temperature effect.
%
% Why a separate model: the Simulink switching model uses a 1 us step, so
% 24 h would need 8.6e10 steps. This is the energy-level model; the
% switching model proves the converter + MPPT dynamics.
%
% Outputs (in the current folder):
%   PV_daily_profile.png   - figure for the report
%   pv_daily_profile.csv   - hourly data for the prediction / load models
%   pv_daily_profile.mat   - same data as MATLAB variables
%
% Run:  daily_pv_profile

clear; clc;

%% ---------------- array and loss parameters ----------------
P_stc   = 7200;     % W, array rating at STC (6S x 3P x 400 W)
gamma   = -0.0040;  % 1/degC, power temp. coefficient. Calibrated to the
                    % Simulink PV block: 7.2 kW at 25 C -> ~6.6 kW at 45 C
NOCT    = 45;       % degC, nominal operating cell temperature
eta_mppt  = 0.98;   % average P&O tracking efficiency (99% full sun, ~96% partial)
eta_boost = 0.97;   % boost converter efficiency

%% ---------------- 24-hour weather profile (Coimbatore) ----------------
dt   = 1/60;                    % 1-minute resolution (hours)
t    = (0:dt:24-dt)';           % time of day (hours)
t_rise = 6.2;  t_set = 18.1;    % sunrise ~6:12, sunset ~18:06
G_pk   = 950;                   % W/m^2, clear-sky noon irradiance

% Clear-sky irradiance: zero at night, sine-shaped bell during the day
x       = min(max((t - t_rise)/(t_set - t_rise), 0), 1);
G_clear = G_pk * sin(pi*x).^1.6;
G_clear(t <= t_rise | t >= t_set) = 0;

% Partly cloudy day: same sun, with three passing cloud events
cloud = [10.5 0.6 0.4;    % [time (h), depth (0-1), width (h)]
         13.0 0.7 0.6;
         15.5 0.5 0.3];
k_cloud = ones(size(t));
for c = 1:size(cloud,1)
    k_cloud = k_cloud .* (1 - cloud(c,2)*exp(-((t - cloud(c,1))/cloud(c,3)).^2));
end
G_cloudy = G_clear .* k_cloud;

% Ambient temperature: ~24 C before dawn, ~33 C at 2 pm
T_amb = 28.5 + 4.5*cos(2*pi*(t - 14)/24);

%% ---------------- PV output model ----------------
% Cell temperature (NOCT model): Tc = Ta + (NOCT - 20)/800 * G
% PV power at MPP:  P = P_stc * (G/1000) * [1 + gamma*(Tc - 25)]
% Power delivered to the 400 V DC bus: P_bus = P * eta_mppt * eta_boost
pv = @(G) P_stc*(G/1000).*(1 + gamma*((T_amb + (NOCT-20)/800*G) - 25)) * eta_mppt * eta_boost;

Tc_clear  = T_amb + (NOCT-20)/800*G_clear;
Tc_cloudy = T_amb + (NOCT-20)/800*G_cloudy;
P_clear   = pv(G_clear);
P_cloudy  = pv(G_cloudy);
P_ideal   = P_stc*(G_clear/1000) * eta_mppt * eta_boost;   % same day if cells stayed at 25 C

%% ---------------- daily summary ----------------
E_clear  = sum(P_clear)*dt/1000;     % kWh
E_cloudy = sum(P_cloudy)*dt/1000;
E_ideal  = sum(P_ideal)*dt/1000;
PSH      = sum(G_clear)*dt/1000;     % peak sun hours
[Pmax, i] = max(P_clear);

fprintf('\n===== Daily PV summary (7.2 kW array, Coimbatore) =====\n');
fprintf('Peak sun hours (clear day)        : %.2f h\n', PSH);
fprintf('Peak power to DC bus (clear)      : %.2f kW at %02d:%02d\n', ...
        Pmax/1000, floor(t(i)), round(mod(t(i),1)*60));
fprintf('Max cell temperature              : %.1f C\n', max(Tc_clear));
fprintf('Daily energy, clear day           : %.1f kWh\n', E_clear);
fprintf('Daily energy, partly cloudy day   : %.1f kWh\n', E_cloudy);
fprintf('Energy lost to cell heating       : %.1f kWh (%.1f %%)\n', ...
        E_ideal - E_clear, 100*(E_ideal - E_clear)/E_ideal);
fprintf('Capacity factor (clear day)       : %.1f %%\n\n', 100*E_clear/(P_stc/1000*24));

%% ---------------- figure (light theme, report-ready) ----------------
f  = figure('Color','w','Position',[100 50 900 850]);
try, theme(f,'light'); end
tl = tiledlayout(f,3,1,'TileSpacing','compact');
blue = [0 0.3 0.8];  orange = [0.85 0.4 0];  grey = [0.5 0.5 0.5];

% 1) Irradiance and ambient temperature
ax1 = nexttile(tl);
yyaxis(ax1,'left');
plot(ax1, t, G_clear, '-', 'Color',blue, 'LineWidth',1.5); hold(ax1,'on');
plot(ax1, t, G_cloudy, '-', 'Color',orange, 'LineWidth',1.2);
ylabel(ax1,'Irradiance (W/m^2)'); ax1.YColor = 'k';
yyaxis(ax1,'right');
plot(ax1, t, T_amb, '--', 'Color',grey, 'LineWidth',1.2);
ylabel(ax1,'T_{ambient} (\circC)'); ax1.YColor = 'k';
legend(ax1, {'G clear day','G partly cloudy','T ambient'}, 'Location','northwest');

% 2) Cell temperature
ax2 = nexttile(tl);
plot(ax2, t, Tc_clear, '-', 'Color',blue, 'LineWidth',1.5); hold(ax2,'on');
plot(ax2, t, Tc_cloudy, '-', 'Color',orange, 'LineWidth',1.2);
plot(ax2, t, T_amb, '--', 'Color',grey, 'LineWidth',1.2);
yline(ax2, 25, ':', 'STC 25 \circC', 'Color','k');
ylabel(ax2,'T_{cell} (\circC)');
legend(ax2, {'Clear day','Partly cloudy','Ambient'}, 'Location','northwest');

% 3) PV power delivered to the DC bus
ax3 = nexttile(tl);
plot(ax3, t, P_ideal/1000, ':', 'Color',grey, 'LineWidth',1.2); hold(ax3,'on');
plot(ax3, t, P_clear/1000, '-', 'Color',blue, 'LineWidth',1.5);
plot(ax3, t, P_cloudy/1000, '-', 'Color',orange, 'LineWidth',1.2);
yline(ax3, P_stc/1000, '--', 'Rated 7.2 kW', 'Color','k');
ylabel(ax3,'P_{PV} to bus (kW)'); xlabel(ax3,'Time of day (h)');
legend(ax3, {sprintf('If cells stayed at 25 \\circC (%.1f kWh)',E_ideal), ...
             sprintf('Clear day (%.1f kWh)',E_clear), ...
             sprintf('Partly cloudy (%.1f kWh)',E_cloudy)}, 'Location','northwest');

for ax = [ax1 ax2 ax3]
    set(ax,'Color','w','XColor','k','GridColor',[0.7 0.7 0.7], ...
        'XLim',[0 24],'XTick',0:2:24); grid(ax,'on');
end
set([ax2 ax3],'YColor','k');
title(tl, 'Daily PV generation: 7.2 kW array, Coimbatore', 'Color','k');

exportgraphics(f, 'PV_daily_profile.png', 'Resolution',300, 'BackgroundColor','white');

%% ---------------- data for teammates (prediction / load models) ----------------
T = table(t, G_clear, G_cloudy, T_amb, Tc_clear, Tc_cloudy, P_clear, P_cloudy, ...
    'VariableNames',{'time_h','G_clear_Wm2','G_cloudy_Wm2','T_amb_C', ...
                     'Tcell_clear_C','Tcell_cloudy_C','P_PV_clear_W','P_PV_cloudy_W'});
writetable(T, 'pv_daily_profile.csv');
save('pv_daily_profile.mat', 't', 'G_clear', 'G_cloudy', 'T_amb', ...
     'Tc_clear', 'Tc_cloudy', 'P_clear', 'P_cloudy');
disp('Saved PV_daily_profile.png, pv_daily_profile.csv, pv_daily_profile.mat')

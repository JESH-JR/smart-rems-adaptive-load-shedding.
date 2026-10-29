%% build_pv_day_model.m  -  RET project, Model 1: PV source over a full day IN SIMULINK
% Builds PV_Source_day.slx from PV_Source_test.slx, replacing the constant
% irradiance/temperature with a 24-hour Coimbatore weather profile:
%   Clock -> hour of day -> 15-min weather update -> G_profile lookup -> PV irradiance input
%                        -> Tamb_profile lookup  -> T_cell = T_amb + (NOCT-20)/800*G -> PV temperature input
%
% Time compression: 1 real hour = t_hour simulated seconds (default 0.05 s,
% so 24 h = 1.2 s). Valid because the PV + MPPT settle in ~18 ms, far faster
% than the weather changes. Energy is scaled back to real hours.
%
% Needs: PV_Source_test.slx (build_pv_source) and pv_daily_profile.mat (daily_pv_profile)
% Run:   build_pv_day_model      (simulation takes several minutes)

src    = 'PV_Source_test';
mdl    = 'PV_Source_day';
t_hour = 0.05;        % simulated seconds per real hour
DAY    = 'cloudy';     % 'clear' or 'cloudy'
RUN_NOW = true;       % false = only build the model

if ~exist([src '.slx'],'file'), error('PV_Source_test.slx not found. Run build_pv_source first.'); end
if ~exist('pv_daily_profile.mat','file'), error('pv_daily_profile.mat not found. Run daily_pv_profile first.'); end

%% ---------------- copy the tested model ----------------
if bdIsLoaded(src), close_system(src, 0); end
if bdIsLoaded(mdl), close_system(mdl, 0); end
if exist([mdl '.slx'],'file'), delete([mdl '.slx']); end
load_system(src);
save_system(src, [mdl '.slx']);          % loaded model is now PV_Source_day
open_system(mdl);
B = @(n) [mdl '/' n];

%% ---------------- remove the constant / step weather inputs ----------------
% Delete only the signal lines attached to these five blocks, then the blocks.
% (The electrical connections of the converter are left untouched.)
for b = {'G0','G_step1','G_step2','Irr','Temp'}
    ph = get_param(B(b{1}), 'PortHandles');
    for p = [ph.Inport, ph.Outport]
        ln = get_param(p, 'Line');
        if ln ~= -1, delete_line(ln); end
    end
    delete_block(B(b{1}));
end

%% ---------------- model settings: load the daily profile at start ----------------
init = sprintf([ ...
    'Ts = 1e-6;\n' ...
    't_hour = %g;   %% simulated seconds per real hour\n' ...
    'DAY = ''%s'';  %% ''clear'' or ''cloudy''\n' ...
    'S = load(''pv_daily_profile.mat'');\n' ...
    't_day = S.t;  T_amb_day = S.T_amb;\n' ...
    'if strcmp(DAY,''cloudy''), G_day = S.G_cloudy; else, G_day = S.G_clear; end\n'], t_hour, DAY);
set_param(mdl, 'InitFcn', init, 'StopTime', num2str(24*t_hour));

%% ---------------- 24-hour weather blocks ----------------
add_block('simulink/Sources/Clock', B('Clock'), 'Position',[-230 140 -200 170]);
add_block('simulink/Math Operations/Gain', B('Hour_of_day'), 'Gain','1/t_hour', 'Position',[-170 140 -120 170]);
add_block('simulink/Lookup Tables/1-D Lookup Table', B('G_profile'), ...
    'BreakpointsForDimension1','t_day', 'Table','G_day', 'Position',[-70 110 -20 150]);
add_block('simulink/Lookup Tables/1-D Lookup Table', B('Tamb_profile'), ...
    'BreakpointsForDimension1','t_day', 'Table','T_amb_day', 'Position',[-70 240 -20 280]);
try, set_param(B('G_profile'),   'ExtrapMethod','Clip'); end
try, set_param(B('Tamb_profile'),'ExtrapMethod','Clip'); end
add_block('simulink/Math Operations/Gain', B('NOCT_heating'), 'Gain','(45-20)/800', 'Position',[30 185 80 210]);
add_block('simulink/Math Operations/Sum', B('T_cell'), 'Inputs','++', 'Position',[120 220 140 260]);

% Weather is updated every 15 real minutes (held constant in between), like
% 15-min weather data. Keeps the sun's change between MPPT samples small
% enough for P&O to track despite the time compression.
add_block('simulink/Discrete/Zero-Order Hold', B('Weather_15min'), ...
    'SampleTime','t_hour/4', 'Position',[-110 195 -80 225]);
add_line(mdl,'Clock/1','Hour_of_day/1','autorouting','on');
add_line(mdl,'Hour_of_day/1','Weather_15min/1','autorouting','on');
add_line(mdl,'Weather_15min/1','G_profile/1','autorouting','on');
add_line(mdl,'Weather_15min/1','Tamb_profile/1','autorouting','on');
add_line(mdl,'G_profile/1','PV/1','autorouting','on');            % irradiance -> PV
add_line(mdl,'G_profile/1','NOCT_heating/1','autorouting','on');
add_line(mdl,'NOCT_heating/1','T_cell/1','autorouting','on');
add_line(mdl,'Tamb_profile/1','T_cell/2','autorouting','on');
add_line(mdl,'T_cell/1','PV/2','autorouting','on');                % cell temperature -> PV

% Scope for the weather inputs
add_block('simulink/Sinks/Scope', B('Weather_Scope'), 'NumInputPorts','2', 'Position',[60 20 100 80]);
add_line(mdl,'G_profile/1','Weather_Scope/1','autorouting','on');
add_line(mdl,'T_cell/1','Weather_Scope/2','autorouting','on');

% P&O with night parking: below 50 W (night / very weak light) hold D at
% 0.42 (V_PV ~ 232 V, about 0.8*Voc) so the PV starts producing at sunrise
% instead of sitting at open circuit. Only this day model is changed.
pando = strjoin({ ...
    'function D = PandO(Vpv, Ipv)'
    '% P&O MPPT with night parking, for a boost converter on a 400 V bus.'
    '% Vpv = (1 - D) * Vbus, so lowering D raises the PV voltage.'
    'persistent Vold Pold Dold'
    'if isempty(Vold), Vold = 0; Pold = 0; Dold = 0.42; end'
    'dD = 0.002;  Pmin = 50;  D_park = 0.42;'
    'P  = Vpv*Ipv;  dV = Vpv - Vold;  dP = P - Pold;'
    'if P < Pmin          % night or very weak light: park near 0.8*Voc'
    '    D = D_park;'
    'elseif dP == 0'
    '    D = Dold;'
    'elseif dP*dV > 0     % left of MPP: raise Vpv by lowering D'
    '    D = Dold - dD;'
    'else                 % right of MPP: lower Vpv by raising D'
    '    D = Dold + dD;'
    'end'
    '% Voltage window: Vpv command 160-256 V (D 0.36-0.60). Covers every MPP'
    '% of the day (~195-245 V) but never asks for more than Voc (~255+ V),'
    '% so P&O cannot drift to open circuit when irradiance rises at sunrise.'
    'D = min(max(D, 0.36), 0.60);'
    'Vold = Vpv; Pold = P; Dold = D;'
    }, newline);
rt = sfroot;
ch = rt.find('-isa','Stateflow.EMChart', 'Path', B('PandO'));
ch.Script = pando;

% Log both scopes to the workspace (every 100th point is plenty)
for sc = {'PV_Scope','Weather_Scope'}
    if strcmp(sc{1},'PV_Scope'), vn = 'pvdata'; dec = '100';   % 1 us signals: keep 1 in 100
    else,                        vn = 'wxdata'; dec = '1';     % 15-min steps: keep all
    end
    set_param(B(sc{1}), 'DataLogging','on', 'DataLoggingVariableName',vn, ...
        'DataLoggingSaveFormat','Dataset', 'DataLoggingLimitDataPoints','off', ...
        'DataLoggingDecimateData','on', 'DataLoggingDecimation',dec);
end
save_system(mdl);
fprintf('\n%s.slx built: PV driven by a 24 h %s-day profile (1 h = %.2f s).\n', mdl, DAY, t_hour);

if ~RUN_NOW, return; end

%% ---------------- run the day ----------------
fprintf('Simulating 24 h (%.1f s of simulation). This takes several minutes...\n', 24*t_hour);
out = sim(mdl);

p  = out.pvdata.getElement(3).Values;   P  = squeeze(p.Data);  ts = p.Time;
v  = out.pvdata.getElement(1).Values;   V  = squeeze(v.Data);
g  = out.wxdata.getElement(1).Values;   tc = out.wxdata.getElement(2).Values;
h  = ts / t_hour;                        % real hour of day

E_sim = trapz(ts, max(P,0)) * (3600/t_hour) / 3.6e6;     % kWh, scaled to real time

% Formula from daily_pv_profile, at the PV terminals (no converter losses)
S = load('pv_daily_profile.mat');
if strcmp(DAY,'cloudy'), Gd = S.G_cloudy; else, Gd = S.G_clear; end
Tcd = S.T_amb + (45-20)/800*Gd;
P_f = 7200*(Gd/1000).*(1 - 0.004*(Tcd - 25));
E_f = sum(P_f)/60/1000;

fprintf('\n===== 24 h result (%s day) =====\n', DAY);
fprintf('Daily energy, Simulink switching model : %.1f kWh\n', E_sim);
fprintf('Daily energy, formula (PV terminals)   : %.1f kWh\n', E_f);
fprintf('Difference                             : %+.1f %%\n', 100*(E_sim - E_f)/E_f);
fprintf('Peak P_PV (Simulink)                   : %.2f kW\n', max(P)/1000);
fprintf('Peak cell temperature                  : %.1f C\n\n', max(squeeze(tc.Data)));

%% ---------------- figure ----------------
f  = figure('Color','w','Position',[100 50 900 850]);
try, theme(f,'light'); end
tl = tiledlayout(f,3,1,'TileSpacing','compact');
blue = [0 0.3 0.8];  orange = [0.85 0.4 0];  grey = [0.5 0.5 0.5];

ax1 = nexttile(tl);
yyaxis(ax1,'left');  plot(ax1, g.Time/t_hour, squeeze(g.Data), '-', 'Color',blue, 'LineWidth',1.4);
ylabel(ax1,'Irradiance (W/m^2)'); ax1.YColor = 'k';
yyaxis(ax1,'right'); plot(ax1, tc.Time/t_hour, squeeze(tc.Data), '-', 'Color',orange, 'LineWidth',1.4);
ylabel(ax1,'T_{cell} (\circC)'); ax1.YColor = 'k';
legend(ax1, {'Irradiance into PV block','Cell temperature into PV block'}, 'Location','northwest');

ax2 = nexttile(tl);
plot(ax2, h, P/1000, '-', 'Color',blue, 'LineWidth',1.2); hold(ax2,'on');
plot(ax2, S.t, P_f/1000, '--', 'Color',grey, 'LineWidth',1.4);
ylabel(ax2,'P_{PV} (kW)');
legend(ax2, {sprintf('Simulink switching model (%.1f kWh)',E_sim), ...
             sprintf('Formula (%.1f kWh)',E_f)}, 'Location','northwest');

ax3 = nexttile(tl);
plot(ax3, h, V, '-', 'Color',blue, 'LineWidth',1.0);
ylabel(ax3,'V_{PV} (V)'); xlabel(ax3,'Time of day (h)');
legend(ax3, {'PV operating voltage set by MPPT'}, 'Location','northwest');

for ax = [ax1 ax2 ax3]
    set(ax,'Color','w','XColor','k','GridColor',[0.7 0.7 0.7],'XLim',[0 24],'XTick',0:2:24);
    grid(ax,'on');  ax.Toolbar.Visible = 'off';
end
set([ax2 ax3],'YColor','k');
title(tl, sprintf('Simulink PV model over a 24 h %s day, Coimbatore (1 h = %.2f s simulated)', DAY, t_hour), 'Color','k');
exportgraphics(f, sprintf('PV_day_simulink_%s.png', DAY), 'Resolution',300, 'BackgroundColor','white');
fprintf('Saved PV_day_simulink_%s.png\n', DAY);

%% resize_pv_for_load.m  -  resize the PV source for the 12-flat load
% Makes PV_Unit_day.slx from PV_Source_day.slx (original is not changed):
%   one PV unit = 6S x 8P = 19.2 kW, L = 0.30 mH, C_in = C_out = 270 uF,
%   night-parking threshold 150 W. The microgrid uses 2 identical units
%   (38.4 kW). Then runs a 24 h day and compares 2 x P_PV with the load.
%
% Needs in the current folder: PV_Source_day.slx, pv_daily_profile.mat
% Run:  resize_pv_for_load        (simulation takes several minutes)

src = 'PV_Source_day';
mdl = 'PV_Unit_day';
DAY = 'clear';          % 'clear' or 'cloudy'
n_units = 2;

if ~exist([src '.slx'],'file'), error('PV_Source_day.slx not found in the current folder.'); end
if ~exist('pv_daily_profile.mat','file'), error('pv_daily_profile.mat not found in the current folder.'); end

%% ---------------- copy the working day model ----------------
if bdIsLoaded(src), close_system(src,0); end
if bdIsLoaded(mdl), close_system(mdl,0); end
if exist([mdl '.slx'],'file'), delete([mdl '.slx']); end
load_system(src);
save_system(src, [mdl '.slx']);          % loaded model is now PV_Unit_day
open_system(mdl);
B = @(n) [mdl '/' n];

%% ---------------- the 5 changes for a 19.2 kW unit ----------------
set_param(B('PV'),    'Npar', '8');            % 6S x 8P = 19.2 kW
set_param(B('L'),     'Inductance',  '0.30e-3');
set_param(B('C_in'),  'Capacitance', '270e-6');
set_param(B('C_out'), 'Capacitance', '270e-6');
rt = sfroot;
ch = rt.find('-isa','Stateflow.EMChart', 'Path', B('PandO'));
ch.Script = strrep(ch.Script, 'Pmin = 50;', 'Pmin = 150;');

% InitFcn: choose the day and load the weather from the model's own folder
init = sprintf([ ...
    'Ts = 1e-6;\n' ...
    't_hour = 0.05;   %% simulated seconds per real hour\n' ...
    'DAY = ''%s'';  %% ''clear'' or ''cloudy''\n' ...
    'S = load(fullfile(fileparts(get_param(bdroot,''FileName'')), ''pv_daily_profile.mat''));\n' ...
    't_day = S.t;  T_amb_day = S.T_amb;\n' ...
    'if strcmp(DAY,''cloudy''), G_day = S.G_cloudy; else, G_day = S.G_clear; end\n'], DAY);
set_param(mdl, 'InitFcn', init, 'StopTime', '1.2');
set_param(B('PV_Scope'), 'DataLogging','on', 'DataLoggingVariableName','pvdata', ...
    'DataLoggingSaveFormat','Dataset', 'DataLoggingLimitDataPoints','off', ...
    'DataLoggingDecimateData','on', 'DataLoggingDecimation','100');
save_system(mdl);
fprintf('\n%s.slx: one 19.2 kW PV unit (6S x 8P, L 0.30 mH, C 270 uF).\n', mdl);

%% ---------------- 12-flat load (same appliance model as init_microgrid.m) ----------------
N = 12;
A = { ...
 'Fridge',1,N,0.15,[0 24 0.35]; 'Router/Wi-Fi',1,N,0.01,[0 24 1.00];
 'CCTV + security',1,1,0.20,[0 24 1.00]; 'Common/emergency lighting',1,1,0.50,[18 24 1.0; 0 6 1.0];
 'Flat lighting (LED)',2,N,0.20,[5 7 0.4; 18 23 0.8; 23 24 0.3];
 'Ceiling fans (3/flat)',2,N,0.225,[0 6 0.5; 6 9 0.3; 9 18 0.35; 18 24 0.6];
 'TV + plug loads',2,N,0.30,[7 9 0.3; 9 18 0.15; 18 23 0.7];
 'Kitchen appliances',2,N,1.50,[6 8 0.25; 12 13 0.2; 19 21 0.15];
 'Lift',2,1,3.70,[7 10 0.3; 10 17 0.1; 17 21 0.3];
 'Split AC 1.5 t',3,N,1.50,[21 24 0.5; 0 5 0.45; 13 16 0.15];
 'Geyser',3,N,2.00,[5 8 0.12]; 'Washing machine',3,N,0.50,[9 12 0.15];
 'Iron',3,N,1.00,[8 9 0.2]; 'Water pump',3,1,1.50,[6 8 1.0; 17 18 1.0] };
Ph = zeros(3,24);
for k = 1:size(A,1)
    s = zeros(1,24);  w = A{k,5};
    for r = 1:size(w,1), s(w(r,1)+1:w(r,2)) = w(r,3); end
    Ph(A{k,2},:) = Ph(A{k,2},:) + A{k,3}*A{k,4}*s;
end
E_firm = sum(sum(Ph(1:2,:)));  E_load = sum(Ph(:));

%% ---------------- run the day ----------------
fprintf('Simulating 24 h %s day (1.2 s). This takes several minutes...\n', DAY);
out = sim(mdl);
p  = out.pvdata.getElement(3).Values;  P1 = squeeze(p.Data);  ts = p.Time;
i1 = squeeze(out.pvdata.getElement(2).Values.Data);
h  = ts / 0.05;                                    % real hour of day
E_unit  = trapz(ts, max(P1,0)) * (3600/0.05) / 3.6e6;   % kWh per unit
E_total = n_units * E_unit;

fprintf('\n===== PV for the 12-flat load (%s day) =====\n', DAY);
fprintf('Per unit (19.2 kW):  peak %.1f kW, peak current %.0f A, %.0f kWh/day\n', max(P1)/1e3, max(i1), E_unit);
fprintf('Total (%d units, 38.4 kW): peak %.1f kW, %.0f kWh/day\n', n_units, n_units*max(P1)/1e3, E_total);
fprintf('Firm load (G1+G2): %.0f kWh/day  -> PV covers it %.1f times\n', E_firm, E_total/E_firm);
fprintf('Total load:        %.0f kWh/day  -> PV covers %.0f %%; rest = deferrable load shed/shifted\n\n', ...
        E_load, 100*E_total/E_load);

%% ---------------- figure: generation vs load ----------------
f = figure('Color','w','Position',[100 80 950 520]);
try, theme(f,'light'); end
ax = axes(f); hold(ax,'on');
hh = [0:23, 24];
area(ax, hh, [sum(Ph(1:2,:),1), sum(Ph(1:2,1))], 'FaceColor',[0.75 0.85 0.95], 'EdgeColor','none');
stairs(ax, hh, [sum(Ph,1), sum(Ph(:,1))], '-', 'Color',[0.85 0.4 0], 'LineWidth',1.6);
plot(ax, h, n_units*P1/1e3, '-', 'Color',[0 0.3 0.8], 'LineWidth',1.2);
xlabel(ax,'Time of day (h)'); ylabel(ax,'Power (kW)');
legend(ax, {sprintf('Firm load G1+G2 (%.0f kWh)', E_firm), ...
            sprintf('Total load (%.0f kWh)', E_load), ...
            sprintf('PV, 2 x 19.2 kW units (%.0f kWh)', E_total)}, 'Location','northwest');
set(ax,'Color','w','XColor','k','YColor','k','GridColor',[0.7 0.7 0.7], ...
    'XLim',[0 24],'XTick',0:2:24); grid(ax,'on'); ax.Toolbar.Visible = 'off';
title(ax, sprintf('38.4 kW PV vs 12-flat load, %s day, Coimbatore', DAY), 'Color','k');
exportgraphics(f, sprintf('PV_vs_load_%s.png', DAY), 'Resolution',300, 'BackgroundColor','white');
fprintf('Saved PV_vs_load_%s.png\n', DAY);

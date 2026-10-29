%% spot_check.m  -  validate the daily-profile formula against Simulink
% Runs PV_Source_test.slx at fixed irradiance/temperature points taken from
% the daily profile and compares the Simulink PV power with the formula
%   P = 7.2 kW * (G/1000) * [1 - 0.004*(T_cell - 25)]
% The model file is NOT modified: values are overridden per run with
% Simulink.SimulationInput.
%
% Run:  spot_check        (takes about 1-3 minutes in total)

mdl = 'PV_Source_test';
if ~exist([mdl '.slx'],'file'), error('PV_Source_test.slx not found. Run build_pv_source first.'); end
load_system(mdl);
% Log the scope data to the workspace (changes the loaded copy only; not saved)
set_param([mdl '/PV_Scope'], 'DataLogging','on', ...
    'DataLoggingVariableName','pvdata', 'DataLoggingSaveFormat','Dataset', ...
    'DataLoggingLimitDataPoints','off', 'DataLoggingDecimateData','on', ...
    'DataLoggingDecimation','10');

% Operating points: [G (W/m^2), T_cell (degC)]  - picked from the daily profile
pts = [1000 25;     % STC reference
        400 40;     % ~8:30 am
        700 50;     % ~10 am
        950 62];    % noon (hottest cells)
labels = {'STC','Morning','Mid-morning','Noon'};

P_stc = 7200;  gamma = -0.004;
t_stop = 0.1;          % s, long enough for P&O to settle (starts at D = 0.6)
t_avg  = 0.06;         % s, average P_PV from here to the end

n = size(pts,1);
P_sim = zeros(n,1);  P_formula = zeros(n,1);  V_sim = zeros(n,1);

for k = 1:n
    G = pts(k,1);  Tc = pts(k,2);
    in = Simulink.SimulationInput(mdl);
    in = in.setModelParameter('StopTime', num2str(t_stop));
    in = in.setBlockParameter([mdl '/G0'],      'Value', num2str(G));
    in = in.setBlockParameter([mdl '/G_step1'], 'After', '0');   % no irradiance steps
    in = in.setBlockParameter([mdl '/G_step2'], 'After', '0');
    in = in.setBlockParameter([mdl '/Temp'],    'Value', num2str(Tc));

    fprintf('Run %d/%d: G = %4d W/m^2, T = %2d C ... ', k, n, G, Tc);
    out = sim(in);

    p  = out.pvdata.getElement(3).Values;   % P_PV
    v  = out.pvdata.getElement(1).Values;   % V_PV
    m  = p.Time >= t_avg;
    P_sim(k) = mean(squeeze(p.Data(m)));
    V_sim(k) = mean(squeeze(v.Data(v.Time >= t_avg)));
    P_formula(k) = P_stc*(G/1000)*(1 + gamma*(Tc - 25));
    fprintf('done\n');
end

err = 100*(P_sim - P_formula)./P_formula;

%% ---------------- results table ----------------
fprintf('\n===== Formula vs Simulink (power at PV terminals) =====\n');
fprintf('%-12s %6s %6s %12s %12s %9s %8s\n', 'Point','G','Tcell','Formula(W)','Simulink(W)','V_PV(V)','Diff(%)');
for k = 1:n
    fprintf('%-12s %6d %6d %12.0f %12.0f %9.1f %8.1f\n', labels{k}, pts(k,1), pts(k,2), ...
            P_formula(k), P_sim(k), V_sim(k), err(k));
end
fprintf('\nSimulink includes real P&O tracking losses, so it should sit about\n');
fprintf('1-4%% below the formula. Within ~5%% = the two models agree.\n\n');

%% ---------------- comparison figure ----------------
f = figure('Color','w','Position',[150 150 750 420]);
try, theme(f,'light'); end
ax = axes(f);
b = bar(ax, categorical(labels, labels), [P_formula P_sim]/1000);
b(1).FaceColor = [0.6 0.6 0.6];  b(2).FaceColor = [0 0.3 0.8];
for k = 1:n
    text(ax, k+0.15, P_sim(k)/1000 + 0.15, sprintf('%+.1f%%', err(k)), ...
        'HorizontalAlignment','center', 'Color','k', 'FontSize',9);
end
set(ax,'Color','w','XColor','k','YColor','k','GridColor',[0.7 0.7 0.7]); grid(ax,'on');
ax.Toolbar.Visible = 'off';
ylabel(ax,'PV power (kW)','Color','k');
legend(ax, {'Daily-profile formula','Simulink switching model'}, 'Location','northeast');
title(ax, 'Validation: daily-profile formula vs Simulink PV model', 'Color','k');
exportgraphics(f, 'PV_formula_validation.png', 'Resolution',300, 'BackgroundColor','white');
disp('Saved PV_formula_validation.png')

% init_microgrid.m  -- parameters for microgrid_top_fixed.slx
% 12 flats | PV 38.4 kW (2 x 19.2 kW) | battery 240 V, 130 kWh | SC 10 F, 250 V
% 400 V DC bus | time-compressed 24 h day.
% Needs pv_daily_profile.csv (or .mat) in the same folder.

clc;   % no 'clear': this script is also called from other scripts and the model InitFcn

%% 1. Time base (ONE base for every subsystem)
Ts_pwr = 1e-6;            % [s] power stage, PWM, powergui
t_hour = 0.12;            % [s] simulated seconds per real hour -> 24 h = 2.88 s
dt     = 0.25;            % [h] macro step (15 min): loads, weather, energy bookkeeping
nDays  = 1;

Ts_ems = t_hour/60;       % [s] EMS / Stateflow step = 1 real minute  (2 ms)
Ts_fc  = dt*t_hour;       % [s] 15-min update as a Simulink sample time (30 ms)
assert(abs(Ts_ems/Ts_pwr - round(Ts_ems/Ts_pwr)) < 1e-9, 'Ts_ems must be a multiple of Ts_pwr');
assert(abs(Ts_fc/Ts_pwr  - round(Ts_fc/Ts_pwr))  < 1e-9, 'Ts_fc must be a multiple of Ts_pwr');

T_stop = nDays*24*t_hour; % [s]
Ts = Ts_pwr;  T_end = T_stop;
t   = (0:dt:24*nDays-dt)';  tod = mod(t,24);

%% 2. Residential loads: 12 flats, appliance-level schedules (summer design day)
% Calibrated to measured data: AC homes in a tropical wet-and-dry climate use
% ~15 kWh/day in summer, AC ~39 %. Result: 15.5 kWh/day per flat + common loads.
N = 12;
% { Name, Tier, Quantity, Rated kW, [start end duty; ...] }  hours 0-24
A = { ...
 'Fridge',                     1, N, 0.15,  [0 24 0.35];
 'Router/Wi-Fi',               1, N, 0.01,  [0 24 1.00];
 'CCTV + security',            1, 1, 0.20,  [0 24 1.00];
 'Common/emergency lighting',  1, 1, 0.50,  [18 24 1.0; 0 6 1.0];
 'Flat lighting (LED)',        2, N, 0.20,  [5 7 0.4; 18 23 0.8; 23 24 0.3];
 'Ceiling fans (3/flat)',      2, N, 0.225, [0 6 0.5; 6 9 0.3; 9 18 0.35; 18 24 0.6];
 'TV + plug loads',            2, N, 0.30,  [7 9 0.3; 9 18 0.15; 18 23 0.7];
 'Kitchen appliances',         2, N, 1.50,  [6 8 0.25; 12 13 0.2; 19 21 0.15];
 'Lift',                       2, 1, 3.70,  [7 10 0.3; 10 17 0.1; 17 21 0.3];
 'Split AC 1.5 t',             3, N, 1.50,  [21 24 0.5; 0 5 0.45; 13 16 0.15];
 'Geyser',                     3, N, 2.00,  [5 8 0.12];
 'Washing machine',            3, N, 0.50,  [9 12 0.15];
 'Iron',                       3, N, 1.00,  [8 9 0.2];
 'Water pump',                 3, 1, 1.50,  [6 8 1.0; 17 18 1.0] };
Ph = zeros(3,24);                         % [kW] hourly demand per tier
for k = 1:size(A,1)
    s = zeros(1,24);  w = A{k,5};
    for r = 1:size(w,1), s(w(r,1)+1:w(r,2)) = w(r,3); end
    Ph(A{k,2},:) = Ph(A{k,2},:) + A{k,3}*A{k,4}*s;
end
prof     = Ph';                           % [kW] 24 x 3 -> loads_func uses prof(hour, tier)
Pmax     = max(Ph,[],2)';                 % [kW] tier maxima [1.45 9.87 9.00]
Pmax_tot = sum(Pmax);
Pscale   = 1;                             % full load
sig  = [0.03 0.10 0.15];  Tc = 2;  Emax = 10;
par = struct();   % reset so leftovers from other scripts cannot clash
par.load_names = ["Critical (Group 1)","Essential (Group 2)","Deferrable (Group 3)"];
par.load_kW    = Pmax;

E_tier = sum(Ph,2)';  E_load = sum(E_tier);  E_firm = E_tier(1) + E_tier(2);
P_peak = max(sum(Ph,1));

% Optional: total load as a timeseries (for tests WITHOUT the Load Manager)
P_tot_W   = 1000*Pscale*sum(prof,2);
P_load_ts = timeseries([P_tot_W; P_tot_W(1)], (0:24)'*t_hour);
P_load_ts.DataInfo.Interpolation = tsdata.interpolation('zoh');

eta_inv   = 0.96;     % inverter efficiency (AC load -> DC bus power)
LOAD_SIGN = +1;       % DC-equivalent load source sign; flip to +1 if P_load_meas is negative

%% 3. PV (2 identical units)
if ~exist('DAY','var'), DAY = 'clear'; end   % 'clear' or 'cloudy' (NASA POWER 9 / 16 May 2025)
try
    pv_table     = readtable('pv_daily_profile.csv');
    t_day        = pv_table.time_h;
    T_amb_day    = pv_table.T_amb_C;
    G_clear_day  = pv_table.G_clear_Wm2;
    G_cloudy_day = pv_table.G_cloudy_Wm2;
    T_amb_cloudy_day = pv_table.T_amb_cloudy_C;
catch
    S = load('pv_daily_profile.mat');
    t_day = S.t;  T_amb_day = S.T_amb;  G_clear_day = S.G_clear;  G_cloudy_day = S.G_cloudy;  T_amb_cloudy_day = S.T_amb_cloudy;
end
if strcmp(DAY,'cloudy'), G_day = G_cloudy_day; T_amb_day = T_amb_cloudy_day; else, G_day = G_clear_day; end

pv = struct();   % reset (a Test 1 run leaves a Dataset called pv in the workspace)
pv.n_units = 2;  pv.Nser = 6;  pv.Npar = 8;          % 2 x 19.2 kW = 38.4 kW
pv.L = 0.30e-3;  pv.C_in = 270e-6;  pv.C_out = 270e-6;  pv.P_park = 150;
pv.P_stc = pv.n_units*pv.Npar*pv.Nser*400;

%% 4. Battery: 240 V, 130 kWh, capacity scaled to the compressed day
V_bat_nom = 240;                          % [V] boost ratio 400/240 = 1.67 (D = 0.4)
E_bat_kWh = 130;                          % [kWh] (68 kWh firm night + 30 kWh reserve)/(0.8 x 0.95)
Q_real_Ah = E_bat_kWh*1e3/V_bat_nom;      % 542 Ah real
k_scale   = t_hour/3600;                  % energy compression factor
Q_sim_Ah  = Q_real_Ah*k_scale;            % 0.018 Ah in the Battery block
R_bat     = 0.05;                         % [ohm] pack internal resistance (real value, not scaled)

par.E_nom = E_bat_kWh;  par.Pb_max = 25;  par.eta_c = 0.95;  par.eta_d = 0.95;  par.eta_inv = eta_inv;
par.SoC_min = 0.20;  par.SoC_max = 0.90;  par.dSoC = 0.08;  par.SoC_0 = 0.80;
Enom = par.E_nom;  Pbmax = par.Pb_max;  eta_c = par.eta_c;  eta_d = par.eta_d;
SoCmin = par.SoC_min;  SoCmax = par.SoC_max;  SoC0 = par.SoC_0;

%% 5. Supercapacitor
C_sc = 10;  V_sc_nom = 250;  V_sc_init = 250;

%% 6. DC bus
V_dc_ref = 400;  C_dc = 25e-3;            % 20 kW for 10 ms with 5 % dip

%% 7. EMS power split
% Low-pass split time constant in SIMULATION seconds. For the compressed 24 h day
% use a small value so the battery carries the energy; use 0.2 for real-time tests.
tau_lpf = 2e-3;

%% 8. Controller gains (starting values; verify with the real-time step test)
f_sw   = 20e3;                            % [Hz] PWM frequency of both storage converters
fc_i   = f_sw/10;                         % current-loop bandwidth
fv     = 20;                              % voltage-loop bandwidth
L_bat  = 0.30e-3;                         % battery converter inductor
L_sc   = 0.355e-3;                        % SC converter inductor (check L_Boost1 in that subsystem)
Kp_ib  = 2*pi*fc_i*L_bat/V_dc_ref;   Ki_ib  = Kp_ib*2*pi*fc_i/10;    % ~0.0094 / 11.8
Kp_isc = 2*pi*fc_i*L_sc/V_dc_ref;    Ki_isc = Kp_isc*2*pi*fc_i/10;   % ~0.011 / 14
Kp_v   = 2*pi*fv*C_dc*V_dc_ref/V_sc_nom;  Ki_v = Kp_v*2*pi*fv/10;   % ~5.0 / 63

%% 9. Load manager
par.th1 = 0.40;  par.th2 = 0.30;  par.d = 0.08;  par.Th = 2;  par.rrec = 0;  par.alpha = 0.5;
th1 = par.th1;  th2 = par.th2;  th1_act = th1;  th2_act = th2;
SoC_min = par.SoC_min;  d = par.d;  Th = par.Th;  rrec = par.rrec;  alpha = par.alpha;
if ~exist('use_benchmark_profile','var'), use_benchmark_profile = 1; end


%% 9b. OPTIONAL AC side: RLC tier load banks (only used by 02_scripts/rlc_option; main model uses R-equivalent DC load)
V_ac    = 230;              % [V rms]  inverter output (ideal source = average model; switching detail in Test 2)
f_ac    = 50;               % [Hz]
P_bank  = 0.5;              % [kW] smallest bank; banks are binary weighted 1,2,4,8,16 x P_bank
bank_bits = [2 5 5];        % banks per tier -> max 1.5 / 15.5 / 15.5 kW
pf_tier = [0.90 0.90 0.85]; % tier power factor before correction (motors: fridges/fans/lift, AC compressors/pump)
pf_corr = 0.95;             % after the capacitive part of each bank

%% 10. Summary
fprintf('\n===== Microgrid parameters =====\n');
fprintf('Time: 1 h = %.2f s, stop %.2f s, Ts %g s, Ts_ems %g s, Ts_fc %g s\n', t_hour, T_stop, Ts, Ts_ems, Ts_fc);
fprintf('Load: %.0f kWh/day (firm %.0f), peak %.1f kW\n', E_load, E_firm, P_peak);
fprintf('PV: %.1f kW (%d x %dS x %dP) | Battery: %d V, %.0f Ah real -> %.4f Ah in block\n', ...
        pv.P_stc/1e3, pv.n_units, pv.Nser, pv.Npar, V_bat_nom, Q_real_Ah, Q_sim_Ah);
fprintf('Gains: V loop Kp %.3f Ki %.1f | I_bat Kp %.4f Ki %.1f | I_sc Kp %.4f Ki %.1f\n\n', ...
        Kp_v, Ki_v, Kp_ib, Ki_ib, Kp_isc, Ki_isc);

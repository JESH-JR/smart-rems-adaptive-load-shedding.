%% build_pv_shading.m  -  RET project, Model 1: PV source under PARTIAL SHADING
% Builds PV_Source_shading.slx and compares two MPPTs on the same event:
%   0 = standard P&O        (gets trapped on a local peak)
%   1 = Global MPPT          (event-triggered scan + P&O, finds the true peak)
%
% Array: one 19.2 kW unit. Each string = 4 sunny modules (PV_A) + 2 shadable
%        modules (PV_B) in series, 8 strings in parallel (6S x 8P),
%        with a bypass diode across each group.
% Test : 0 - 0.15 s  uniform 1000 W/m^2
%        0.15 - 0.35 s PV_B shaded to 30 % (300 W/m^2)
%        0.35 - 0.5 s  shading removed
%
% Run:  build_pv_shading      (two simulations, a few minutes in total)

clear; clc;
mdl     = 'PV_Source_shading';
Ts      = 1e-6;     % powergui + solver step (s)
Ts_mppt = 1e-4;     % MPPT update period (s)
fsw     = 20e3;     % switching frequency (Hz)
Vbus    = 400;      % stand-in DC bus (V)
shade   = 0.3;      % shaded modules get 30 % of the irradiance
t_on = 0.15;  t_off = 0.35;  t_stop = 0.5;

% Port polarity (same as the working PV_Source_test on R2025a)
PV_SWAP = false;  BUS_SWAP = true;  DIODE_SWAP = false;

%% ---------------- start clean ----------------
assignin('base','Ts',Ts);
if bdIsLoaded(mdl), close_system(mdl,0); end
if exist([mdl '.slx'],'file'), delete([mdl '.slx']); end
new_system(mdl); open_system(mdl);
set_param(mdl, 'StopTime',num2str(t_stop), ...
    'SolverType','Fixed-step', 'Solver','FixedStepDiscrete', 'FixedStep','Ts', ...
    'SolverMode','SingleTasking', 'AutoInsertRateTranBlk','on', ...
    'InitFcn', sprintf('Ts = %g;', Ts));
B = @(n) [mdl '/' n];

load_system('spspowerguiLib');
add_block('spspowerguiLib/powergui', B('powergui'), 'Position',[20 20 110 60]);
setp(B('powergui'), 'SimulationMode', 'Discrete');
setp(B('powergui'), 'SampleTime', 'Ts');

%% ---------------- PV array split into sunny + shadable groups ----------------
load_system('spsPVArrayLib');
add_block('spsPVArrayLib/PV Array', B('PV_A_sunny'),  'Position',[220 100 300 190]);
add_block('spsPVArrayLib/PV Array', B('PV_B_shaded'), 'Position',[220 260 300 350]);
modp = {'ModuleName','User-defined'; 'Npar','8'; 'Ncell','72'; ...
       'Voc','48'; 'Isc','10.5'; 'Vm','40'; 'Im','10'};
for k = 1:size(modp,1)
    setp(B('PV_A_sunny'),  modp{k,1}, modp{k,2});
    setp(B('PV_B_shaded'), modp{k,1}, modp{k,2});
end
setp(B('PV_A_sunny'),  'Nser','4');     % 4 modules per string, always sunny (x 8 strings)
setp(B('PV_B_shaded'), 'Nser','2');     % 2 modules per string, can be shaded

% Bypass diodes across each group (as in real modules)
add_block(sps('^Diode$'), B('BD_A'), 'Position',[150 120 190 150], 'Orientation','up');
add_block(sps('^Diode$'), B('BD_B'), 'Position',[150 280 190 310], 'Orientation','up');

% Irradiance and shading signal
add_block('simulink/Sources/Constant', B('G0'), 'Value','1000', 'Position',[-200 110 -160 130]);
add_block('simulink/Sources/Constant', B('One'), 'Value','1', 'Position',[-260 230 -230 250]);
add_block('simulink/Sources/Step', B('Shade_on'),  'Time',num2str(t_on),  'Before','0', 'After',num2str(shade-1), 'Position',[-260 270 -230 300]);
add_block('simulink/Sources/Step', B('Shade_off'), 'Time',num2str(t_off), 'Before','0', 'After',num2str(1-shade), 'Position',[-260 320 -230 350]);
add_block('simulink/Math Operations/Sum', B('Shade_factor'), 'Inputs','+++', 'Position',[-190 260 -170 320]);
add_block('simulink/Math Operations/Product', B('G_shaded'), 'Position',[-120 270 -90 300]);
add_block('simulink/Sources/Constant', B('Temp'), 'Value','25', 'Position',[-120 190 -80 210]);
add_line(mdl,'One/1','Shade_factor/1','autorouting','on');
add_line(mdl,'Shade_on/1','Shade_factor/2','autorouting','on');
add_line(mdl,'Shade_off/1','Shade_factor/3','autorouting','on');
add_line(mdl,'G0/1','G_shaded/1','autorouting','on');
add_line(mdl,'Shade_factor/1','G_shaded/2','autorouting','on');
add_line(mdl,'G0/1','PV_A_sunny/1','autorouting','on');
add_line(mdl,'G_shaded/1','PV_B_shaded/1','autorouting','on');
add_line(mdl,'Temp/1','PV_A_sunny/2','autorouting','on');
add_line(mdl,'Temp/1','PV_B_shaded/2','autorouting','on');

%% ---------------- boost converter + stand-in bus (as in PV_Source_test) ----------------
add_block(sps('^Current Measurement$'), B('I_meas'),     'Position',[360 100 390 130]);
add_block(sps('^Voltage Measurement$'), B('V_meas_PV'),  'Position',[360 400 390 430]);
add_block(sps('^Series RLC Branch$'),   B('C_in'),  'BranchType','C', 'Capacitance','270e-6', 'Position',[430 200 460 240]);
add_block(sps('^Series RLC Branch$'),   B('L'),     'BranchType','L', 'Inductance','0.30e-3', 'Position',[490 100 530 130]);
add_block(sps('^Ideal Switch$'),        B('SW'),    'Position',[570 200 610 240]);
add_block(sps('^Diode$'),               B('D'),     'Position',[630 100 670 130]);
add_block(sps('^Series RLC Branch$'),   B('C_out'), 'BranchType','C', 'Capacitance','270e-6', 'Position',[710 200 740 240]);
add_block(sps('^Series RLC Branch$'),   B('R_bus'), 'BranchType','R', 'Resistance','0.1',     'Position',[770 100 810 130]);
add_block(sps('^DC Voltage Source$'),   B('Vbus'),  'Amplitude', num2str(Vbus),               'Position',[850 190 890 240]);
add_block(sps('^Voltage Measurement$'), B('V_meas_bus'), 'Position',[730 400 760 430]);

pa   = phys(B('PV_A_sunny'));  if PV_SWAP, pa = pa([2 1]); end
pb   = phys(B('PV_B_shaded')); if PV_SWAP, pb = pb([2 1]); end
bda  = phys(B('BD_A'));  if DIODE_SWAP, bda = bda([2 1]); end   % [anode cathode]
bdb  = phys(B('BD_B'));  if DIODE_SWAP, bdb = bdb([2 1]); end
im   = phys(B('I_meas'));
vpv  = phys(B('V_meas_PV'));
cin  = phys(B('C_in'));
Lp   = phys(B('L'));
sw   = phys(B('SW'));
dd   = phys(B('D'));     if DIODE_SWAP, dd  = dd([2 1]);  end
cout = phys(B('C_out'));
rb   = phys(B('R_bus'));
src  = phys(B('Vbus'));  if BUS_SWAP,   src = src([2 1]); end
vb   = phys(B('V_meas_bus'));

% String: (+) PV_A_sunny (-) -> (+) PV_B_shaded (-); bypass diode across each
wire(mdl, [pa(1) im(1) bda(2)]);                      % array + : PV_A +, BD_A cathode
wire(mdl, [pa(2) pb(1) bda(1) bdb(2)]);               % middle node
wire(mdl, [im(2) cin(1) Lp(1) vpv(1)]);               % PV terminal node (after sensor)
wire(mdl, [Lp(2) sw(1) dd(1)]);                       % switching node
wire(mdl, [dd(2) cout(1) rb(1) vb(1)]);               % DC bus +
wire(mdl, [rb(2) src(1)]);                            % to 400 V source +
wire(mdl, [pb(2) bdb(1) cin(2) sw(2) cout(2) src(2) vpv(2) vb(2)]);   % common negative

%% ---------------- MPPT: selectable standard P&O / Global MPPT ----------------
add_block('simulink/Discrete/Zero-Order Hold', B('ZOH_V'), 'SampleTime',num2str(Ts_mppt), 'Position',[440 480 470 510]);
add_block('simulink/Discrete/Zero-Order Hold', B('ZOH_I'), 'SampleTime',num2str(Ts_mppt), 'Position',[440 530 470 560]);
add_block('simulink/Sources/Constant', B('MPPT_select'), 'Value','1', 'Position',[430 590 480 610]);
add_block('simulink/User-Defined Functions/MATLAB Function', B('MPPT'), 'Position',[520 475 620 615]);
setScript(mdl, 'MPPT', strjoin({ ...
    'function D = MPPT(Vpv, Ipv, useG)'
    '% useG = 0 : standard P&O'
    '% useG = 1 : Global MPPT = event-triggered full scan + P&O'
    '% Boost on a 400 V bus: Vpv = (1 - D)*400, lowering D raises Vpv.'
    'persistent mstate Dold Vold Pold k Dbest Pbest Pref holdc Psum'
    'if isempty(mstate)'
    '    Vold = 0; Pold = 0; k = 0; Pbest = 0; Pref = 0; holdc = 0; Psum = 0;'
    '    if useG > 0.5, mstate = 1; Dold = 0.70; Dbest = 0.70;'
    '    else,          mstate = 0; Dold = 0.40; Dbest = 0.40; end'
    'end'
    'dD = 0.002;  P = Vpv*Ipv;'
    ''
    'if useG < 0.5   % ---------- standard P&O ----------'
    '    dV = Vpv - Vold;  dP = P - Pold;'
    '    if dP == 0, D = Dold; elseif dP*dV > 0, D = Dold - dD; else, D = Dold + dD; end'
    '    D = min(max(D, 0.05), 0.85);'
    '    Vold = Vpv; Pold = P; Dold = D;'
    '    return'
    'end'
    ''
    '% ---------- Global MPPT ----------'
    'Dlo = 0.30; Dhi = 0.70;      % scan range: Vpv = 280 V ... 120 V'
    'dscan = 0.025; nset = 40; navg = 10;   % 17 points x 4 ms = ~70 ms scan'
    'if mstate == 1               % SCAN: step D, wait to settle, record power'
    '    k = k + 1;'
    '    if k > nset - navg, Psum = Psum + P; end'
    '    if k >= nset'
    '        Pm = Psum/navg;'
    '        if Pm > Pbest, Pbest = Pm; Dbest = Dold; end'
    '        k = 0; Psum = 0;'
    '        D = Dold - dscan;'
    '        if D < Dlo - 1e-9     % scan done: jump to the best (global) point'
    '            D = Dbest; mstate = 0; Pref = Pbest; holdc = 300;'
    '        end'
    '    else'
    '        D = Dold;'
    '    end'
    '    Vold = Vpv; Pold = P; Dold = D;'
    '    return'
    'end'
    '% P&O around the global peak'
    'dV = Vpv - Vold;  dP = P - Pold;'
    'if dP == 0, D = Dold; elseif dP*dV > 0, D = Dold - dD; else, D = Dold + dD; end'
    'D = min(max(D, Dlo), Dhi);'
    'if holdc > 0'
    '    holdc = holdc - 1;'
    'elseif Pref > 0 && abs(P - Pref) > 0.15*Pref   % sudden change (shading) -> rescan'
    '    mstate = 1; k = 0; Psum = 0; Pbest = 0; D = Dhi;'
    'else'
    '    Pref = 0.995*Pref + 0.005*P;               % follow slow changes'
    'end'
    'Vold = Vpv; Pold = P; Dold = D;'
    }, newline));
add_line(mdl,'V_meas_PV/1','ZOH_V/1','autorouting','on');
add_line(mdl,'I_meas/1','ZOH_I/1','autorouting','on');
add_line(mdl,'ZOH_V/1','MPPT/1','autorouting','on');
add_line(mdl,'ZOH_I/1','MPPT/2','autorouting','on');
add_line(mdl,'MPPT_select/1','MPPT/3','autorouting','on');

% PWM
add_block('simulink/Sources/Repeating Sequence', B('Carrier'), ...
    'rep_seq_t', sprintf('[0 %g]', 1/fsw), 'rep_seq_y', '[0 1]', 'Position',[660 570 700 600]);
add_block('simulink/Logic and Bit Operations/Relational Operator', B('PWM'), 'Operator','>', 'Position',[720 520 750 560]);
add_block('simulink/Signal Attributes/Data Type Conversion', B('Gate'), 'OutDataTypeStr','double', 'Position',[780 525 820 555]);
add_line(mdl,'MPPT/1','PWM/1','autorouting','on');
add_line(mdl,'Carrier/1','PWM/2','autorouting','on');
add_line(mdl,'PWM/1','Gate/1','autorouting','on');
add_line(mdl,'Gate/1','SW/1','autorouting','on');

% Measurements + scope
add_block('simulink/Math Operations/Product', B('P_PV'), 'Position',[900 400 930 440]);
add_block('simulink/Sinks/Scope', B('PV_Scope'), 'NumInputPorts','5', 'Position',[980 380 1020 520]);
add_line(mdl,'V_meas_PV/1','P_PV/1','autorouting','on');
add_line(mdl,'I_meas/1','P_PV/2','autorouting','on');
add_line(mdl,'V_meas_PV/1','PV_Scope/1','autorouting','on');
add_line(mdl,'I_meas/1','PV_Scope/2','autorouting','on');
add_line(mdl,'P_PV/1','PV_Scope/3','autorouting','on');
add_line(mdl,'MPPT/1','PV_Scope/4','autorouting','on');
add_line(mdl,'V_meas_bus/1','PV_Scope/5','autorouting','on');
set_param(B('PV_Scope'), 'DataLogging','on', 'DataLoggingVariableName','pvdata', ...
    'DataLoggingSaveFormat','Dataset', 'DataLoggingLimitDataPoints','off', ...
    'DataLoggingDecimateData','on', 'DataLoggingDecimation','20');
save_system(mdl);
fprintf('\n%s.slx built (MPPT_select: 0 = P&O, 1 = Global MPPT).\n', mdl);

%% ---------------- run both MPPTs on the same shading event ----------------
names = {'Standard P&O','Global MPPT'};
res = struct();
for m = 0:1
    fprintf('Running %s ... ', names{m+1});
    in  = Simulink.SimulationInput(mdl);
    in  = in.setBlockParameter(B('MPPT_select'), 'Value', num2str(m));
    out = sim(in);
    p = out.pvdata.getElement(3).Values;  v = out.pvdata.getElement(1).Values;
    res(m+1).t = p.Time;  res(m+1).P = squeeze(p.Data);  res(m+1).V = squeeze(v.Data);
    fprintf('done\n');
end

%% ---------------- available power from the P-V curves ----------------
[Vu, Pu] = pvcurve(1000, 4, 1000,        2);   % uniform
[Vs, Ps] = pvcurve(1000, 4, 1000*shade,  2);   % shaded
P_av_u = max(Pu);  P_av_s = max(Ps);

w = @(r) r.t >= t_on + 0.1 & r.t < t_off;       % settled part of the shaded window
for m = 1:2
    res(m).Psh = mean(res(m).P(w(res(m))));
    res(m).Vsh = mean(res(m).V(w(res(m))));
    ws = res(m).t >= t_on & res(m).t < t_off;   % whole shaded window, incl. scan
    res(m).Esh = trapz(res(m).t(ws), res(m).P(ws));
end
E_av = P_av_s*(t_off - t_on);

fprintf('\n===== Partial shading: 2 of 6 modules per string at %d W/m^2 =====\n', 1000*shade);
fprintf('Available maximum (global peak)     : %.2f kW at about %.0f V\n', P_av_s/1000, Vs(Ps==P_av_s));
for m = 1:2
    fprintf('%-14s settled power        : %.2f kW at %.0f V  (%.0f %% of available)\n', ...
        names{m}, res(m).Psh/1000, res(m).Vsh, 100*res(m).Psh/P_av_s);
end
for m = 1:2
    fprintf('%-14s energy while shaded   : %.0f %% of available (includes scan time)\n', ...
        names{m}, 100*res(m).Esh/E_av);
end
fprintf('Gain of Global MPPT while shaded    : %+.0f %%\n\n', 100*(res(2).Psh/res(1).Psh - 1));

%% ---------------- figure ----------------
f  = figure('Color','w','Position',[80 40 950 900]);
try, theme(f,'light'); end
tl = tiledlayout(f,3,1,'TileSpacing','compact');
red = [0.85 0.2 0.1];  blue = [0 0.3 0.8];  grey = [0.4 0.4 0.4];

ax1 = nexttile(tl);
plot(ax1, res(1).t, res(1).P/1000, 'Color',red,  'LineWidth',1.1); hold(ax1,'on');
plot(ax1, res(2).t, res(2).P/1000, 'Color',blue, 'LineWidth',1.1);
stairs(ax1, [0 t_on t_off t_stop], [P_av_u P_av_s P_av_u P_av_u]/1000, '--', 'Color',grey, 'LineWidth',1.2);
xline(ax1, [t_on t_off], ':', {'shading on','shading off'}, 'Color','k');
ylabel(ax1,'P_{PV} (kW)');
legend(ax1, {'Standard P&O','Global MPPT (scan + P&O)','Maximum available'}, 'Location','southeast');

ax2 = nexttile(tl);
plot(ax2, res(1).t, res(1).V, 'Color',red,  'LineWidth',1.1); hold(ax2,'on');
plot(ax2, res(2).t, res(2).V, 'Color',blue, 'LineWidth',1.1);
xline(ax2, [t_on t_off], ':', 'Color','k');
ylabel(ax2,'V_{PV} (V)'); xlabel(ax2,'Time (s)');
legend(ax2, {'Standard P&O','Global MPPT'}, 'Location','southeast');

ax3 = nexttile(tl);
plot(ax3, Vu, Pu/1000, '-', 'Color',grey, 'LineWidth',1.2); hold(ax3,'on');
plot(ax3, Vs, Ps/1000, '-', 'Color','k', 'LineWidth',1.6);
plot(ax3, res(1).Vsh, res(1).Psh/1000, 'o', 'MarkerSize',9, 'MarkerFaceColor',red,  'MarkerEdgeColor','k');
plot(ax3, res(2).Vsh, res(2).Psh/1000, 's', 'MarkerSize',9, 'MarkerFaceColor',blue, 'MarkerEdgeColor','k');
xlabel(ax3,'Array voltage (V)'); ylabel(ax3,'P (kW)'); xlim(ax3,[0 300]);
legend(ax3, {'Uniform 1000 W/m^2','Shaded (2 of 6 modules at 30 %)', ...
             'P&O ends here (local peak)','Global MPPT ends here (global peak)'}, 'Location','northwest');

for ax = [ax1 ax2 ax3]
    set(ax,'Color','w','XColor','k','YColor','k','GridColor',[0.7 0.7 0.7]);
    grid(ax,'on'); ax.Toolbar.Visible = 'off';
end
title(tl, 'Partial shading on one 19.2 kW unit (6S \times 8P): standard P&O vs Global MPPT', 'Color','k');
exportgraphics(f, 'PV_shading_GMPPT.png', 'Resolution',300, 'BackgroundColor','white');
disp('Saved PV_shading_GMPPT.png')

%% =============== local helper functions ===============
function [V, P] = pvcurve(GA, nA, GB, nB)
% P-V curve of 8 parallel strings, each = nA modules at GA + nB modules at GB,
% bypass diode (0.7 V) across each group. Single-diode model with the
% parameters computed by the Simulink PV Array block for this module.
    I  = linspace(0, 10.55, 4000)';
    VA = max(vmod(I, GA), -0.7) * nA;
    VB = max(vmod(I, GB), -0.7) * nB;
    V  = VA + VB;  P = 8 * V .* I;
    keep = V > 0;  V = V(keep);  P = P(keep);
end

function V = vmod(I, G)
% Module voltage for current I at irradiance G, 25 C (Newton iteration).
    IL = 10.576*G/1000;  I0 = 3.9433e-10;  Rs = 0.20021;  Rsh = 821.7644;
    Vt = 1.0809 * 1.381e-23 * 298.15 / 1.602e-19 * 72;
    V  = 40*ones(size(I));
    for it = 1:200
        e  = exp((V + I*Rs)/Vt);
        fV = IL - I0*(e - 1) - (V + I*Rs)/Rsh - I;
        dV = -I0*e/Vt - 1/Rsh;
        V  = min(max(V - fV./dV, -5), 60);
    end
end

function p = sps(pattern)
    persistent libs
    name = regexprep(pattern, '^\^|\$$', '');
    if isempty(libs)
        f = [dir(fullfile(matlabroot,'toolbox','physmod','**','sps*Lib.slx')); ...
             dir(fullfile(matlabroot,'toolbox','physmod','**','sps*Lib.mdl'))];
        libs = unique(regexprep({f.name}, '\.(slx|mdl)$', ''), 'stable');
    end
    key  = ['sps' regexprep(name,'[^A-Za-z0-9]','') 'Lib'];
    hit  = libs(strcmpi(libs, key));
    cand = [hit, libs(~strcmpi(libs, key))];
    for k = 1:numel(cand)
        try
            load_system(cand{k});
            b = find_system(cand{k}, 'SearchDepth',1, 'Name',name);
            if ~isempty(b), p = b{1}; return; end
        catch
        end
    end
    error('Block "%s" not found in any sps*Lib library. Send this error to Claude.', name);
end

function p = phys(blk)
    ph = get_param(blk, 'PortHandles');
    p  = [ph.LConn, ph.RConn];
end

function wire(mdl, ports)
    for k = 2:numel(ports)
        add_line(mdl, ports(1), ports(k), 'autorouting','on');
    end
end

function setp(blk, name, val)
    try
        set_param(blk, name, val);
    catch e
        warning('Could not set "%s" on %s (%s). Set it in the block dialog.', name, blk, e.message);
    end
end

function setScript(mdl, blk, code)
    rt = sfroot;
    ch = rt.find('-isa','Stateflow.EMChart', 'Path',[mdl '/' blk]);
    ch.Script = code;
end

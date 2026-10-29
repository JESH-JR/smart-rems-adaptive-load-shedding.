function build_chb_inverter()
%BUILD_CHB_INVERTER  Builds and tests a new 5-level CHB inverter model in MATLAB R2025a (Test 2 v2).
%   Two H-bridge cells (200 V each) in series, unipolar phase-shifted carrier PWM (carriers 90 deg
%   apart -> effective switching 4 kHz), LC output filter with a series damping resistor, resistive load.
%   Creates 01_model/CHB_inverter_v2.slx, runs 3 cases and computes THD up to the 50th harmonic
%   (IEEE 519) and wideband THD (to 10 kHz). Results -> 04_results/test2_inverter_v2/
root = fileparts(fileparts(mfilename('fullpath')));
cd(fullfile(root,'01_model'));
mdl = 'CHB_inverter_v2';

%% ---------------- design parameters ----------------
P.Ts     = 1e-6;     % [s]  solver step
P.T_stop = 0.10;     % [s]  5 cycles (last 2 analysed)
P.f0     = 50;       % [Hz] output frequency
P.Vdc    = 200;      % [V]  per cell (2 cells -> levels 0, +-200, +-400 V)
P.m      = 0.8;      % modulation index -> 320 V peak, 226 V rms
P.fc     = 1000;     % [Hz] carrier per cell (2 cells unipolar -> 4 kHz effective)
P.Lf     = 2e-3;     % [H]  filter inductor
P.RLf    = 0.05;     % [ohm] inductor resistance
P.Cf     = 20e-6;    % [F]  filter capacitor  -> f_res = 1/(2*pi*sqrt(Lf*Cf)) = 796 Hz
P.Rd     = 2;        % [ohm] series damping resistor in the capacitor branch
P.Rload  = 11.8;     % [ohm] 4.3 kW at 226 V rms
fprintf('Filter resonance %.0f Hz, effective switching %.0f Hz\n', 1/(2*pi*sqrt(P.Lf*P.Cf)), 4*P.fc);
push(P);

%% ---------------- build ----------------
if bdIsLoaded(mdl), close_system(mdl,0); end
if exist([mdl '.slx'],'file'), delete([mdl '.slx']); end
new_system(mdl); open_system(mdl);
set_param(mdl,'Solver','FixedStepDiscrete','FixedStep','Ts','StopTime','T_stop', ...
          'SignalLogging','off','ReturnWorkspaceOutputs','on');
B = @(n) [mdl '/' n];
add_block(lib('powergui','powerlib/powergui'), B('powergui'), 'Position',[20 20 100 60]);
set_param(B('powergui'),'SimulationMode','Discrete','SampleTime','Ts');

% sources and bridges
for k = 1:2
    y = 120 + (k-1)*220;
    add_block(lib('DC Voltage Source','powerlib/Electrical Sources/DC Voltage Source'), B(sprintf('Vdc%d',k)), ...
              'Amplitude','Vdc', 'Position',[60 y 100 y+60]);
    add_block(lib('Universal Bridge','powerlib/Power Electronics/Universal Bridge'), B(sprintf('Cell%d',k)), ...
              'Position',[200 y 280 y+80]);
    set_param(B(sprintf('Cell%d',k)),'Arms','2');
    try, set_param(B(sprintf('Cell%d',k)),'Device','IGBT / Diodes'); catch, end
end
% PWM
add_block('simulink/Sources/Digital Clock', B('Clock'), 'SampleTime','Ts', 'Position',[20 600 60 630]);
add_block('simulink/User-Defined Functions/MATLAB Function', B('PWM'), 'Position',[100 580 220 650]);
ch = sfroot().find('-isa','Stateflow.EMChart','Path',B('PWM'));
ch.Script = sprintf([ ...
 'function [g1, g2] = PWM(t)\n' ...
 '%% Unipolar phase-shifted carrier PWM, 2 cells, carriers 90 deg apart\n' ...
 'ref = %g*sin(2*pi*%g*t);\n' ...
 'c1 = (2/pi)*asin(sin(2*pi*%g*t));\n' ...
 'c2 = (2/pi)*asin(sin(2*pi*%g*t + pi/2));\n' ...
 'a1 = double(ref > c1);  b1 = double(-ref > c1);\n' ...
 'a2 = double(ref > c2);  b2 = double(-ref > c2);\n' ...
 'g1 = [a1; 1-a1; b1; 1-b1];   %% [upper A; lower A; upper B; lower B]\n' ...
 'g2 = [a2; 1-a2; b2; 1-b2];\n'], P.m, P.f0, P.fc, P.fc);
ch.SampleTime = 'Ts';
add_line(mdl,'Clock/1','PWM/1','autorouting','on');
add_line(mdl,'PWM/1','Cell1/1','autorouting','on');
add_line(mdl,'PWM/2','Cell2/1','autorouting','on');

% filter, load, measurements
RLC = lib('Series RLC Branch','powerlib/Elements/Series RLC Branch');
add_block(RLC, B('Lf'),    'Position',[380 120 420 150]);  set_param(B('Lf'),'BranchType','RL','Resistance','RLf','Inductance','Lf');
add_block(RLC, B('Cf_Rd'), 'Position',[480 200 510 260], 'Orientation','down');
set_param(B('Cf_Rd'),'BranchType','RC','Resistance','max(Rd,1e-6)','Capacitance','Cf');
add_block(RLC, B('Rload'), 'Position',[620 200 650 260], 'Orientation','down'); set_param(B('Rload'),'BranchType','R','Resistance','Rload');
add_block(lib('Current Measurement','powerlib/Measurements/Current Measurement'), B('I_load'), 'Position',[560 120 590 150]);
VM = lib('Voltage Measurement','powerlib/Measurements/Voltage Measurement');
add_block(VM, B('V_out'), 'Position',[720 200 750 240]);
add_block(VM, B('V_inv'), 'Position',[380 400 410 440]);
add_block(lib('Ground','powerlib/Elements/Ground'), B('Ground'), 'Position',[600 480 630 510]);
for s = {'vo','V_out';'io','I_load';'vinv','V_inv'}'
    add_block('simulink/Sinks/To Workspace', B(['TW_' s{1}]), 'VariableName',s{1}, ...
              'SaveFormat','Structure With Time', 'Position',[820 0 880 30]);
    add_line(mdl,[s{2} '/1'],['TW_' s{1} '/1'],'autorouting','on');
end

% electrical wiring:  P = Cell1.A, Cell1.B = Cell2.A, N = Cell2.B
h = @(n) phys(B(n));          % [LConn RConn]
c1 = h('Cell1'); c2 = h('Cell2'); d1 = h('Vdc1'); d2 = h('Vdc2');   % bridge: [A B + -], DC: [- +]
W = @(a,b) add_line(mdl,a,b,'autorouting','on');
W(d1(2),c1(3)); W(d1(1),c1(4)); W(d2(2),c2(3)); W(d2(1),c2(4));   % DC source: LConn = '-', RConn = '+' (checked with diag_chb)
W(c1(2),c2(1));                                   % series connection of the cells
P_ = c1(1);  N_ = c2(2);
lf = h('Lf'); cr = h('Cf_Rd'); rl = h('Rload'); im = h('I_load'); vo = h('V_out'); vi = h('V_inv'); g = h('Ground');
W(P_,lf(1)); W(lf(2),cr(1)); W(lf(2),im(1)); W(im(2),rl(1));
W(cr(2),N_); W(rl(2),N_); W(g(1),N_);
W(vo(1),lf(2)); W(vo(2),N_); W(vi(1),P_); W(vi(2),N_);
save_system(mdl);
fprintf('%s.slx built (%s)\n', mdl, version('-release'));

%% ---------------- run 3 cases ----------------
cases = { 'damped_full',   P.Rd, P.Rload;
          'undamped_full', 0,    P.Rload;
          'damped_light',  P.Rd, 200 };
od = fullfile(root,'04_results','test2_inverter','v2_new_model'); if ~exist(od,'dir'), mkdir(od); end
diary(fullfile(od,'summary.txt')); diary on;
fprintf('\n===== Test 2 v2: 5-level CHB inverter (Lf %.1f mH, Cf %.0f uF, f_res %.0f Hz) =====\n', ...
        P.Lf*1e3, P.Cf*1e6, 1/(2*pi*sqrt(P.Lf*P.Cf)));
R = struct();
for k = 1:size(cases,1)
    Q = P; Q.Rd = cases{k,2}; Q.Rload = cases{k,3}; push(Q);
    out = sim(mdl);
    [t,vo_]  = sig(out,'vo'); [~,io_] = sig(out,'io'); [~,vi_] = sig(out,'vinv');
    [V1,TV50,TV200,Hv] = thd(t,vo_,P.f0); [I1,TI50] = thd(t,io_,P.f0); [~,TVinv50,TVinv200] = thd(t,vi_,P.f0);
    ss = t > P.T_stop - 2/P.f0;
    fprintf(['%-14s Rd %4.1f ohm, Rload %5.1f ohm: V1 %5.1f V pk (%5.1f V rms), I1 %5.2f A rms, P %4.2f kW\n' ...
             '               peak |vo| steady %5.1f V, incl. start-up %5.1f V\n' ...
             '               THD_v (to 50th) %5.2f %%,  THD_v (to 10 kHz) %5.2f %%,  THD_i (to 50th) %5.2f %%\n' ...
             '               unfiltered 5-level: THD to 50th %4.2f %%, to 10 kHz %5.1f %%\n'], ...
            cases{k,1}, Q.Rd, Q.Rload, V1, V1/sqrt(2), I1/sqrt(2), (V1/sqrt(2))^2/Q.Rload/1e3, ...
            max(abs(vo_(ss))), max(abs(vo_)), TV50, TV200, TI50, TVinv50, TVinv200);
    R.(cases{k,1}) = struct('t',t,'vo',vo_,'io',io_,'vi',vi_,'Hv',Hv,'V1',V1);
end
diary off;
save(fullfile(od,'test2_data.mat'),'R','P');   % for make_figures

%% ---------------- figures ----------------
D = R.damped_full; U = R.undamped_full; ss = D.t > P.T_stop - 2/P.f0; tt = (D.t(ss)-D.t(find(ss,1)))*1e3;
f = figure('Color','w','Position',[60 60 1100 900]); tl = tiledlayout(f,3,1,'TileSpacing','compact');
ax = nexttile(tl); plot(ax,tt,D.vi(ss),'Color',[0.7 0.8 0.95]); hold(ax,'on'); plot(ax,tt,D.vo(ss),'b','LineWidth',1.6);
ylabel(ax,'Voltage (V)'); legend(ax,{'5-level inverter output','filtered output (damped)'},'Location','best'); grid(ax,'on');
title(ax,'Output voltage, two 50 Hz cycles');
ax = nexttile(tl); plot(ax,tt,D.io(ss),'b','LineWidth',1.4); ylabel(ax,'Load current (A)'); grid(ax,'on');
ax = nexttile(tl); k = 2:50; bar(ax,k,[100*U.Hv(k)/U.V1; 100*D.Hv(k)/D.V1]','grouped');
xlabel(ax,'Harmonic order'); ylabel(ax,'% of fundamental'); legend(ax,{'undamped','damped (R_d = 2 \Omega)'}); grid(ax,'on');
title(ax,'Voltage harmonics up to the 50th (IEEE 519 range)');
xlabel(tl,'Time (ms)'); title(tl,'Test 2 v2: 5-level CHB inverter with damped LC filter','FontWeight','bold');
exportgraphics(f, fullfile(od,'test2_chb_v2.png'),'Resolution',150);
fprintf('Results saved in %s\n', od);
end

%% ===================== helpers =====================
function push(P), fn = fieldnames(P); for k = 1:numel(fn), assignin('base',fn{k},P.(fn{k})); end, end
function [t,x] = sig(out,n), s = out.get(n); t = s.time(:); x = squeeze(s.signals.values); x = x(:); end
function [X1,T50,T200,H] = thd(t,x,f0)
    dt = t(2)-t(1); N = round(2/f0/dt); s = x(end-N+1:end);
    A = abs(fft(s))*2/N; H = zeros(1,200);
    for k = 1:200, H(k) = A(2*k+1); end           % 2 cycles -> harmonic k at bin 2k
    X1 = H(1); T50 = 100*sqrt(sum(H(2:50).^2))/X1; T200 = 100*sqrt(sum(H(2:200).^2))/X1;
end
function p = phys(blk), ph = get_param(blk,'PortHandles'); p = [ph.LConn, ph.RConn]; end
function p = lib(name, classic)
    try, load_system(strtok(classic,'/')); if getSimulinkBlockHandle(classic) > 0, p = classic; return; end, catch, end
    f = [dir(fullfile(matlabroot,'toolbox','physmod','**','sps*Lib.slx')); dir(fullfile(matlabroot,'toolbox','physmod','**','sps*Lib.mdl'))];
    libs = unique(regexprep({f.name},'\.(slx|mdl)$',''),'stable');
    key = ['sps' regexprep(name,'[^A-Za-z0-9]','') 'Lib'];
    cand = [libs(strcmpi(libs,key)), libs(~strcmpi(libs,key))];
    for k = 1:numel(cand)
        try, load_system(cand{k}); b = find_system(cand{k},'SearchDepth',1,'Name',name); if ~isempty(b), p = b{1}; return; end, catch, end
    end
    error('Library block "%s" not found', name);
end

%% build_pv_source.m  -  RET project, Model 1: PV source
% Builds PV_Source_test.slx from scratch:
%   PV array (6S x 3P, 400 W modules, 7.2 kW)
%   -> boost converter (L = 0.8 mH, Cin = Cout = 100 uF, 20 kHz)
%   -> 400 V stand-in DC bus (DC source + 0.1 ohm)
%   P&O MPPT (updates every 0.1 ms) + CV mode when SOC >= 98 %
% Uses Specialized Power Systems (powerlib) blocks.
%
% HOW TO RUN: save this file in your working folder, then type
%   build_pv_source
% in the Command Window. Then press Run in the model.

%% ---------------- settings ----------------
mdl     = 'PV_Source_test';
Ts      = 1e-6;     % powergui + solver step (s)
Ts_mppt = 1e-4;     % MPPT update period (s)
fsw     = 20e3;     % boost switching frequency (Hz)
Vbus    = 400;      % stand-in DC bus voltage (V)

% Port polarity flags. Port order of SPS blocks can differ between
% MATLAB versions. If a scope shows the wrong sign, set the flag to
% true and run the script again.
PV_SWAP    = false;   % V_PV comes out negative
BUS_SWAP   = true;    % V_bus comes out negative (about -400 V) -> confirmed on R2025a
DIODE_SWAP = false;   % P_PV stays near 0 W

%% ---------------- start clean ----------------
assignin('base','Ts',Ts);
if bdIsLoaded(mdl), close_system(mdl,0); end
if exist([mdl '.slx'],'file'), delete([mdl '.slx']); end
new_system(mdl); open_system(mdl);
set_param(mdl, 'StopTime','0.5', ...
    'SolverType','Fixed-step', 'Solver','FixedStepDiscrete', 'FixedStep','Ts', ...
    'SolverMode','SingleTasking', 'AutoInsertRateTranBlk','on', ...
    'InitFcn', sprintf('Ts = %g;', Ts));
B = @(n) [mdl '/' n];

%% ---------------- powergui ----------------
load_system('spspowerguiLib');
add_block('spspowerguiLib/powergui', B('powergui'), 'Position',[20 20 110 60]);
setp(B('powergui'), 'SimulationMode', 'Discrete');
setp(B('powergui'), 'SampleTime', 'Ts');

%% ---------------- PV array ----------------
load_system('spsPVArrayLib');
add_block('spsPVArrayLib/PV Array', B('PV'), 'Position',[200 150 280 250]);
pvp = {'ModuleName','User-defined'; 'Nser','6'; 'Npar','3'; 'Ncell','72'; ...
       'Voc','48'; 'Isc','10.5'; 'Vm','40'; 'Im','10'; ...
       'beta_Voc','-0.3'; 'alpha_Isc','0.05'};
for k = 1:size(pvp,1), setp(B('PV'), pvp{k,1}, pvp{k,2}); end

% Irradiance: 1000 -> 600 (t = 0.2 s) -> 800 W/m^2 (t = 0.35 s)
add_block('simulink/Sources/Constant', B('G0'), 'Value','1000', 'Position',[20 110 60 130]);
add_block('simulink/Sources/Step', B('G_step1'), 'Time','0.2', 'Before','0', 'After','-400', 'Position',[20 150 50 180]);
add_block('simulink/Sources/Step', B('G_step2'), 'Time','0.35', 'Before','0', 'After','200', 'Position',[20 200 50 230]);
add_block('simulink/Math Operations/Sum', B('Irr'), 'Inputs','+++', 'Position',[110 140 130 200]);
add_block('simulink/Sources/Constant', B('Temp'), 'Value','25', 'Position',[100 230 140 250]);
add_line(mdl,'G0/1','Irr/1','autorouting','on');
add_line(mdl,'G_step1/1','Irr/2','autorouting','on');
add_line(mdl,'G_step2/1','Irr/3','autorouting','on');
add_line(mdl,'Irr/1','PV/1','autorouting','on');
add_line(mdl,'Temp/1','PV/2','autorouting','on');

%% ---------------- boost converter + stand-in bus ----------------
add_block(sps('^Current Measurement$'), B('I_meas'),     'Position',[330 130 360 160]);
add_block(sps('^Voltage Measurement$'), B('V_meas_PV'),  'Position',[330 300 360 330]);
add_block(sps('^Series RLC Branch$'),   B('C_in'),  'BranchType','C', 'Capacitance','100e-6', 'Position',[400 200 430 240]);
add_block(sps('^Series RLC Branch$'),   B('L'),     'BranchType','L', 'Inductance','0.8e-3',  'Position',[460 130 500 160]);
add_block(sps('^Ideal Switch$'),        B('SW'),    'Position',[540 200 580 240]);
add_block(sps('^Diode$'),               B('D'),     'Position',[600 130 640 160]);
add_block(sps('^Series RLC Branch$'),   B('C_out'), 'BranchType','C', 'Capacitance','100e-6', 'Position',[680 200 710 240]);
add_block(sps('^Series RLC Branch$'),   B('R_bus'), 'BranchType','R', 'Resistance','0.1',     'Position',[740 130 780 160]);
add_block(sps('^DC Voltage Source$'),   B('Vbus'),  'Amplitude', num2str(Vbus),               'Position',[820 190 860 240]);
add_block(sps('^Voltage Measurement$'), B('V_meas_bus'), 'Position',[700 300 730 330]);

pv   = phys(B('PV'));     if PV_SWAP,    pv  = pv([2 1]);  end
im   = phys(B('I_meas'));
vpv  = phys(B('V_meas_PV'));
cin  = phys(B('C_in'));
Lp   = phys(B('L'));
sw   = phys(B('SW'));
dd   = phys(B('D'));      if DIODE_SWAP, dd  = dd([2 1]);  end
cout = phys(B('C_out'));
rb   = phys(B('R_bus'));
src  = phys(B('Vbus'));   if BUS_SWAP,   src = src([2 1]); end
vb   = phys(B('V_meas_bus'));

wire(mdl, [pv(1) im(1)]);                                   % PV+ -> current sensor
wire(mdl, [im(2) cin(1) Lp(1) vpv(1)]);                     % PV terminal node
wire(mdl, [Lp(2) sw(1) dd(1)]);                             % switching node
wire(mdl, [dd(2) cout(1) rb(1) vb(1)]);                     % DC bus +
wire(mdl, [rb(2) src(1)]);                                  % to 400 V source +
wire(mdl, [pv(2) cin(2) sw(2) cout(2) src(2) vpv(2) vb(2)]);% common negative

%% ---------------- MPPT (P&O) ----------------
add_block('simulink/Discrete/Zero-Order Hold', B('ZOH_V'), 'SampleTime',num2str(Ts_mppt), 'Position',[420 380 450 410]);
add_block('simulink/Discrete/Zero-Order Hold', B('ZOH_I'), 'SampleTime',num2str(Ts_mppt), 'Position',[420 430 450 460]);
add_block('simulink/User-Defined Functions/MATLAB Function', B('PandO'), 'Position',[500 375 580 465]);
setScript(mdl, 'PandO', strjoin({ ...
    'function D = PandO(Vpv, Ipv)'
    '% Perturb & Observe MPPT for a boost converter on a fixed DC bus.'
    '% Vpv = (1 - D) * Vbus, so lowering D raises the PV voltage.'
    'persistent Vold Pold Dold'
    'if isempty(Vold), Vold = 0; Pold = 0; Dold = 0.4; end'
    'dD = 0.002;'
    'P  = Vpv*Ipv;  dV = Vpv - Vold;  dP = P - Pold;'
    'if dP == 0'
    '    D = Dold;'
    'elseif dP*dV > 0      % left of MPP: raise Vpv by lowering D'
    '    D = Dold - dD;'
    'else                  % right of MPP: lower Vpv by raising D'
    '    D = Dold + dD;'
    'end'
    'D = min(max(D, 0.05), 0.85);'
    'Vold = Vpv; Pold = P; Dold = D;'
    }, newline));
add_line(mdl,'V_meas_PV/1','ZOH_V/1','autorouting','on');
add_line(mdl,'I_meas/1','ZOH_I/1','autorouting','on');
add_line(mdl,'ZOH_V/1','PandO/1','autorouting','on');
add_line(mdl,'ZOH_I/1','PandO/2','autorouting','on');

%% ---------------- CV mode (battery full) + mode switch ----------------
add_block('simulink/Sources/Constant', B('V_ref'), 'Value',num2str(Vbus), 'Position',[420 500 460 520]);
add_block('simulink/Math Operations/Sum', B('V_err'), 'Inputs','+-', 'Position',[500 500 520 540]);
add_block('simulink/Discrete/Discrete PID Controller', B('PI_CV'), ...
    'Controller','PI', 'P','0.001', 'I','0.05', 'SampleTime',num2str(Ts_mppt), 'Position',[550 500 600 540]);
add_block('simulink/Discontinuities/Saturation', B('Sat_CV'), 'UpperLimit','0.85', 'LowerLimit','0.05', 'Position',[630 505 660 535]);
add_block('simulink/Sources/Constant', B('SOC_B'), 'Value','50', 'Position',[500 560 540 580]);
add_block('simulink/Logic and Bit Operations/Compare To Constant', B('SOC_full'), ...
    'relop','>=', 'const','98', 'Position',[560 555 610 585]);
add_block('simulink/Signal Routing/Switch', B('Mode'), 'Criteria','u2 ~= 0', 'Position',[700 420 740 480]);
% PWM: compare duty D with a 0-1 sawtooth carrier at fsw (gate = D > carrier)
add_block('simulink/Sources/Repeating Sequence', B('Carrier'), ...
    'rep_seq_t', sprintf('[0 %g]', 1/fsw), 'rep_seq_y', '[0 1]', 'Position',[700 520 740 550]);
add_block('simulink/Logic and Bit Operations/Relational Operator', B('PWM'), ...
    'Operator','>', 'Position',[780 430 810 470]);
add_block('simulink/Signal Attributes/Data Type Conversion', B('Gate'), ...
    'OutDataTypeStr','double', 'Position',[840 435 880 465]);

add_line(mdl,'V_ref/1','V_err/1','autorouting','on');
add_line(mdl,'V_meas_bus/1','V_err/2','autorouting','on');
add_line(mdl,'V_err/1','PI_CV/1','autorouting','on');
add_line(mdl,'PI_CV/1','Sat_CV/1','autorouting','on');
add_line(mdl,'Sat_CV/1','Mode/1','autorouting','on');      % CV duty (SOC >= 98 %)
add_line(mdl,'SOC_B/1','SOC_full/1','autorouting','on');
add_line(mdl,'SOC_full/1','Mode/2','autorouting','on');
add_line(mdl,'PandO/1','Mode/3','autorouting','on');       % MPPT duty (normal)
add_line(mdl,'Mode/1','PWM/1','autorouting','on');          % duty D
add_line(mdl,'Carrier/1','PWM/2','autorouting','on');       % sawtooth carrier
add_line(mdl,'PWM/1','Gate/1','autorouting','on');
add_line(mdl,'Gate/1','SW/1','autorouting','on');           % gate signal

%% ---------------- measurements + scope ----------------
add_block('simulink/Math Operations/Product', B('P_PV'), 'Position',[880 300 910 340]);
add_block('simulink/Sinks/Scope', B('PV_Scope'), 'NumInputPorts','5', 'Position',[960 280 1000 420]);
setp(B('PV_Scope'), 'LayoutDimensions', '[5 1]');   % one plot per signal
add_line(mdl,'V_meas_PV/1','P_PV/1','autorouting','on');
add_line(mdl,'I_meas/1','P_PV/2','autorouting','on');
add_line(mdl,'V_meas_PV/1','PV_Scope/1','autorouting','on');   % V_PV
add_line(mdl,'I_meas/1','PV_Scope/2','autorouting','on');      % I_PV
add_line(mdl,'P_PV/1','PV_Scope/3','autorouting','on');        % P_PV
add_line(mdl,'Mode/1','PV_Scope/4','autorouting','on');        % duty D
add_line(mdl,'V_meas_bus/1','PV_Scope/5','autorouting','on');  % V_bus

save_system(mdl);
fprintf('\n%s.slx built and saved.\n', mdl);
fprintf('1) Open the PV block, check the module data, click Apply, then Plot.\n');
fprintf('   The MPP should be about 240 V, 30 A, 7.2 kW.\n');
fprintf('2) Press Run. Expect P_PV about 7.2 kW -> 4.3 kW -> 5.8 kW.\n\n');

%% =============== local helper functions ===============
function p = sps(pattern)
% Find a Specialized Power Systems library block by name (version-proof).
% R2025a keeps each Specialized Power Systems block in its own library,
% e.g. 'spsPVArrayLib/PV Array'. Find that library file and use its block.
    persistent libs
    name = regexprep(pattern, '^\^|\$$', '');          % '^Diode$' -> 'Diode'
    if isempty(libs)
        f = [dir(fullfile(matlabroot,'toolbox','physmod','**','sps*Lib.slx')); ...
             dir(fullfile(matlabroot,'toolbox','physmod','**','sps*Lib.mdl'))];
        libs = unique(regexprep({f.name}, '\.(slx|mdl)$', ''), 'stable');
    end
    key  = ['sps' regexprep(name,'[^A-Za-z0-9]','') 'Lib'];   % 'spsCurrentMeasurementLib'
    hit  = libs(strcmpi(libs, key));
    cand = [hit, libs(~strcmpi(libs, key))];           % best guess first, then the rest
    if isempty(hit)
        fprintf('Searching all SPS libraries for "%s" (may take a minute)...\n', name);
    end
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
% Physical (electrical) port handles of a block, left side first.
    ph = get_param(blk, 'PortHandles');
    p  = [ph.LConn, ph.RConn];
end

function wire(mdl, ports)
% Connect all given physical ports to one electrical node.
    for k = 2:numel(ports)
        add_line(mdl, ports(1), ports(k), 'autorouting','on');
    end
end

function setp(blk, name, val)
% set_param that warns instead of stopping if a parameter name differs.
    try
        set_param(blk, name, val);
    catch e
        warning('Could not set "%s" on %s (%s). Set it in the block dialog.', ...
                name, blk, e.message);
    end
end

function setScript(mdl, blk, code)
% Put code into a MATLAB Function block.
    rt = sfroot;
    ch = rt.find('-isa','Stateflow.EMChart', 'Path',[mdl '/' blk]);
    ch.Script = code;
end

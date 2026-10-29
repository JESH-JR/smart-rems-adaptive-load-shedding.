%% fix_microgrid_model.m  -  applies the integration fixes to a COPY of microgrid_top.slx
% Creates microgrid_top_fixed.slx (the original is not changed). Each fix runs on
% its own; failures are listed at the end with what to do by hand.
%
% Needs in the current folder: microgrid_top.slx, init_microgrid.m,
%                               pv_daily_profile.csv (or .mat)
% Run:  fix_microgrid_model

evalin('base', 'init_microgrid');                 % parameters into the base workspace (run FIRST)

src = 'microgrid_top';
mdl = 'microgrid_top_fixed';
if ~exist([src '.slx'],'file'), error('microgrid_top.slx not found in the current folder.'); end

if bdIsLoaded(src), close_system(src,0); end
if bdIsLoaded(mdl), close_system(mdl,0); end
if exist([mdl '.slx'],'file'), delete([mdl '.slx']); end
load_system(src);
save_system(src, [mdl '.slx']);                   % loaded model is now microgrid_top_fixed
open_system(mdl);

B   = @(p) [mdl '/' p];
CC  = [mdl '/Combined Control Battery//Supercapacitor'];   % '/' in a block name is written '//'
rep = {};                                         % report: {step, ok, note}

%% 1. loads_func: real hour of day + t_hour parameter
rep(end+1,:) = trystep('loads_func uses t/t_hour', @() fix_loads_func(mdl));

%% 2. Loads clock at the 15-min rate
rep(end+1,:) = trystep('Loads Digital Clock = Ts_fc', @() set_param(B('Loads/Digital Clock'),'SampleTime','Ts_fc'));

%% 3. Total load power -> Goto [Pr_L] (EMS input)
rep(end+1,:) = trystep('Pact -> [Pr_L] in W', @() add_PrL(mdl));

%% 4. Load Manager runs at the EMS rate
rep(end+1,:) = trystep('Load Manager sample time = Ts_ems', @() set_chart_ts([mdl '/Load Manager'], 'Ts_ems'));

%% 5. DC-equivalent dynamic load on the DC bus
rep(end+1,:) = trystep('Controlled Current Source load on DC bus', @() add_dc_load(mdl));

%% 6. Take the CHB inverter + fixed RLC loads off the bus (avoid double load)
rep(end+1,:) = trystep('Comment out inverter (Subsystem)', @() set_param(B('Subsystem'),'Commented','on'));

%% 7. Battery 240 V, scaled capacity
rep(end+1,:) = trystep('Battery NomV = V_bat_nom',  @() set_param(B('Battery'),'NomV','V_bat_nom'));
rep(end+1,:) = trystep('Battery NomQ = Q_sim_Ah',   @() set_param(B('Battery'),'NomQ','Q_sim_Ah'));
rep(end+1,:) = trystep('Battery MaxQ = Q_sim_Ah',   @() set_param(B('Battery'),'MaxQ','Q_sim_Ah'));
rep(end+1,:) = trystep('Battery SOC = SoC0*100',    @() set_param(B('Battery'),'SOC','SoC0*100'));
rep(end+1,:) = trystep('Battery R = R_bat',         @() set_param(B('Battery'),'R','R_bat'));

%% 8. Supercapacitor 10 F, 250 V
rep(end+1,:) = trystep('Supercap C = C_sc',         @() set_param(B('Supercapacitor'),'C','C_sc'));
rep(end+1,:) = trystep('Supercap Vinit = V_sc_init',@() set_param(B('Supercapacitor'),'Vinit','V_sc_init'));

%% 9. DC-link capacitor
rep(end+1,:) = trystep('C_DC_Link = C_dc',          @() set_param(B('C_DC_Link'),'Capacitance','C_dc'));

%% 10. EMS low-pass split time constant
rep(end+1,:) = trystep('BESS LPF tau = tau_lpf', @() set_param(B('BESS/Transfer Fcn'), ...
    'Numerator','[1-exp(-Ts/tau_lpf)]', 'Denominator','[1 -exp(-Ts/tau_lpf)]'));

%% 11. PI gains for 240/250 V -> 400 V
rep(end+1,:) = trystep('Voltage loop gains',  @() set_param([CC '/PID Controller'], 'P','Kp_v',  'I','Ki_v'));
rep(end+1,:) = trystep('Battery current gains',@() set_param([CC '/PID Controller1'],'P','Kp_ib', 'I','Ki_ib'));
rep(end+1,:) = trystep('SC current gains',    @() set_param([CC '/PID Controller2'], 'P','Kp_isc','I','Ki_isc'));
rep(end+1,:) = trystep('Battery PWM = f_sw',  @() set_param([CC '/PWM Generator (DC-DC)'], 'Fsw','f_sw'));
rep(end+1,:) = trystep('SC PWM = f_sw',       @() set_param([CC '/PWM Generator (DC-DC)1'],'Fsw','f_sw'));

%% 12. PV unit -> 19.2 kW, correct weather rate
P = @(p) [mdl '/PV Generation/' p];
rep(end+1,:) = trystep('PV Npar = 8',            @() set_param(P('PV'),'Npar','8'));
rep(end+1,:) = trystep('PV L = 0.30 mH',         @() set_param(P('L'),'Inductance','0.30e-3'));
rep(end+1,:) = trystep('PV C_in = 270 uF',       @() set_param(P('C_in'),'Capacitance','270e-6'));
rep(end+1,:) = trystep('PV C_out = 270 uF',      @() set_param(P('C_out'),'Capacitance','270e-6'));
rep(end+1,:) = trystep('PV weather = Ts_fc',     @() set_param(P('Weather_15min'),'SampleTime','Ts_fc'));
rep(end+1,:) = trystep('PV irradiance = G_day',  @() set_param(P('G_profile'),'Table','G_day'));
rep(end+1,:) = trystep('PV night parking 150 W', @() set_pando_pmin([mdl '/PV Generation/PandO']));

%% 13. Second PV unit + total P_PV
rep(end+1,:) = trystep('Second PV unit (PV Generation 2)', @() add_pv_unit2(mdl));

%% 14. Model settings
rep(end+1,:) = trystep('InitFcn = init_microgrid', @() set_param(mdl,'InitFcn','init_microgrid;'));
rep(end+1,:) = trystep('Stop time = T_stop',       @() set_param(mdl,'StopTime','T_stop'));

save_system(mdl);

%% ---------------- report ----------------
fprintf('\n===== fix_microgrid_model report (%s.slx) =====\n', mdl);
for k = 1:size(rep,1)
    if rep{k,2}, fprintf('  OK    %s\n', rep{k,1});
    else,        fprintf('  FAIL  %s  ->  %s\n', rep{k,1}, rep{k,3}); end
end
fprintf(['\nNext:\n  1) Fix any FAIL lines by hand (send them to Claude if unsure).\n' ...
         '  2) Set the Supercapacitor RATED voltage to 250 V in its dialog.\n' ...
         '  3) Real-time step test first (see the guide), then the 24 h run.\n' ...
         '  4) Check Load_scope: P_load_meas must be POSITIVE. If negative, set LOAD_SIGN = +1 in init_microgrid.m.\n\n']);

%% =============== helper functions ===============
function r = trystep(name, fh)
    try
        fh();  r = {name, true, ''};
    catch e
        r = {name, false, e.message};
    end
end

function fix_loads_func(mdl)
    rt = sfroot;
    ch = rt.find('-isa','Stateflow.EMChart', 'Path',[mdl '/Loads/MATLAB Function']);
    if isempty(ch), error('Loads/MATLAB Function not found'); end
    s = ch.Script;
    s = regexprep(s, 'function \[Preq, Pact, Edef_out\] = loads_func\(([^)]*)\)', ...
                     'function [Preq, Pact, Edef_out] = loads_func($1, t_hour)', 'once');
    s = strrep(s, 'mod(t / 3600, 24)', 'mod(t / t_hour, 24)');
    ch.Script = s;
    dd = ch.find('-isa','Stateflow.Data','Name','t_hour');
    if isempty(dd), dd = Stateflow.Data(ch); dd.Name = 't_hour'; end
    dd.Scope = 'Parameter';
end

function add_PrL(mdl)
    L = [mdl '/Loads'];
    add_block('simulink/Math Operations/Sum of Elements', [L '/P_total_kW'], 'Position',[700 60 740 90]);
    add_block('simulink/Math Operations/Gain', [L '/kW_to_W'], 'Gain','1000*Pscale', 'Position',[770 60 820 90]);
    add_block('simulink/Signal Routing/Goto', [L '/Goto_PrL'], 'GotoTag','Pr_L', ...
              'TagVisibility','global', 'Position',[850 60 910 90]);
    add_line(L, 'MATLAB Function/2', 'P_total_kW/1', 'autorouting','on');   % Pact (kW, 3 tiers)
    add_line(L, 'P_total_kW/1', 'kW_to_W/1', 'autorouting','on');
    add_line(L, 'kW_to_W/1', 'Goto_PrL/1', 'autorouting','on');
end

function set_chart_ts(path, ts)
    rt = sfroot;
    ch = rt.find('-isa','Stateflow.Chart', 'Path', path);
    if isempty(ch), ch = rt.find('-isa','Stateflow.EMChart', 'Path', path); end
    if isempty(ch), error('chart not found at %s', path); end
    ch.SampleTime = ts;
end

function add_dc_load(mdl)
    B = @(p) [mdl '/' p];
    x = 200; y = 1400;
    add_block('simulink/Signal Routing/From', B('From_PrL_load'), 'GotoTag','Pr_L', 'Position',[x y x+60 y+30]);
    add_block('simulink/Math Operations/Gain', B('Load_DC_equiv'), 'Gain','LOAD_SIGN/eta_inv', 'Position',[x+100 y x+160 y+30]);
    add_block('simulink/Signal Routing/From', B('From_VDC_load'), 'GotoTag','V_DC', 'Position',[x y+60 x+60 y+90]);
    add_block('simulink/Discontinuities/Saturation', B('Vdc_limit'), 'UpperLimit','450', 'LowerLimit','300', 'Position',[x+100 y+60 x+140 y+90]);
    add_block('simulink/Math Operations/Product', B('I_load_ref'), 'Inputs','*/', 'Position',[x+200 y+20 x+240 y+70]);
    add_block(sps('Controlled Current Source'), B('Load_DC_equivalent'), 'Position',[x+300 y+10 x+340 y+80]);
    add_block(sps('Current Measurement'), B('I_load_meas'), 'Position',[x+400 y-60 x+430 y-30]);
    add_block('simulink/Math Operations/Product', B('P_load_meas'), 'Position',[x+480 y-40 x+510 y-10]);
    add_block('simulink/Sinks/Scope', B('Load_scope'), 'NumInputPorts','2', 'Position',[x+560 y-50 x+600 y]);
    add_line(mdl,'From_PrL_load/1','Load_DC_equiv/1','autorouting','on');
    add_line(mdl,'Load_DC_equiv/1','I_load_ref/1','autorouting','on');
    add_line(mdl,'From_VDC_load/1','Vdc_limit/1','autorouting','on');
    add_line(mdl,'Vdc_limit/1','I_load_ref/2','autorouting','on');
    add_line(mdl,'I_load_ref/1','Load_DC_equivalent/1','autorouting','on');
    add_line(mdl,'I_load_meas/1','P_load_meas/1','autorouting','on');
    add_line(mdl,'Vdc_limit/1','P_load_meas/2','autorouting','on');
    add_line(mdl,'P_load_meas/1','Load_scope/1','autorouting','on');
    add_line(mdl,'From_PrL_load/1','Load_scope/2','autorouting','on');
    % electrical: DC_Bus+ -> current meter -> source -> DC_Bus-
    bp = phys(B('DC_Bus+'));  bn = phys(B('DC_Bus-'));
    im = phys(B('I_load_meas'));  cs = phys(B('Load_DC_equivalent'));
    add_line(mdl, bp(1), im(1), 'autorouting','on');
    add_line(mdl, im(2), cs(1), 'autorouting','on');
    add_line(mdl, cs(2), bn(1), 'autorouting','on');
end

function set_pando_pmin(path)
    rt = sfroot;
    ch = rt.find('-isa','Stateflow.EMChart', 'Path', path);
    if isempty(ch), error('PandO not found'); end
    if ~contains(ch.Script, 'Pmin = 50'), error('"Pmin = 50" not found in PandO code'); end
    ch.Script = strrep(ch.Script, 'Pmin = 50;', 'Pmin = 150;');
end

function add_pv_unit2(mdl)
    B = @(p) [mdl '/' p];
    pos = get_param(B('PV Generation'),'Position');
    add_block(B('PV Generation'), B('PV Generation 2'), 'Position', pos + [0 220 0 220]);
    for sc = {'PV_Scope','Weather_Scope'}          % avoid duplicate logging names
        try, set_param(B(['PV Generation 2/' sc{1}]), 'DataLogging','off'); catch, end
    end
    % electrical: same DC bus
    p2 = phys(B('PV Generation 2'));  bp = phys(B('DC_Bus+'));  bn = phys(B('DC_Bus-'));
    add_line(mdl, p2(1), bp(1), 'autorouting','on');
    add_line(mdl, p2(2), bn(1), 'autorouting','on');
    % measurement of unit 2 (same chain as unit 1) and total power
    add_block(B('Bus Selector'), B('Bus Selector PV2'));
    add_block(B('Product'),      B('Product PV2'));
    add_line(mdl, 'PV Generation 2/1', 'Bus Selector PV2/1', 'autorouting','on');
    add_line(mdl, 'Bus Selector PV2/1', 'Product PV2/1', 'autorouting','on');
    add_line(mdl, 'Bus Selector PV2/2', 'Product PV2/2', 'autorouting','on');
    lh = get_param(B('Product'),'LineHandles');
    delete_line(lh.Outport(1));                      % Product -> Goto [P_PV]
    add_block('simulink/Math Operations/Sum', B('P_PV_total'), 'Inputs','++');
    add_line(mdl, 'Product/1', 'P_PV_total/1', 'autorouting','on');
    add_line(mdl, 'Product PV2/1', 'P_PV_total/2', 'autorouting','on');
    add_line(mdl, 'P_PV_total/1', 'Goto4/1', 'autorouting','on');
end

function p = phys(blk)
    ph = get_param(blk,'PortHandles');
    p  = [ph.LConn, ph.RConn];
end

function p = sps(name)
    persistent libs
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
    error('Library block "%s" not found', name);
end

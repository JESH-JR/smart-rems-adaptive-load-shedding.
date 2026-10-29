%% add_rlc_loads.m  -  AC side with switched RLC tier banks in microgrid_top_fixed.slx (R2025a)
%  * inverter average model: ideal 230 V / 50 Hz controlled voltage source
%  * per tier binary-weighted parallel RLC banks (0.5,1,2,4,8 kW) with tier PF, corrected to 0.95
%  * banks follow the active tier power P_act from the Loads function (profile + shedding L), every 15 min
%  * AC active power P_ac (one-cycle moving average) drives the DC load: I_dc = P_ac/(eta_inv*V_dc)
%  * reactive power Q_ac and power factor PF_ac logged
root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(fullfile(root,'01_model'), fullfile(root,'01_model','_rebuild_source'), fullfile(root,'02_scripts'), fullfile(root,'02_scripts','model_fixes'), fullfile(root,'03_data'));
cd(fullfile(root,'01_model'));
evalin('base','init_microgrid');
m = 'microgrid_top_fixed';
if bdIsLoaded(m), close_system(m,0); end
copyfile([m '.slx'], [m '_preRLC.slx'], 'f');
load_system(m);
rep = {};
rep(end+1,:) = trystep('1. Goto [Pact_tiers] from Loads function', @() pact_goto(m));
rep(end+1,:) = trystep('2. AC Loads subsystem (source, 12 RLC banks, P/Q/PF)', @() build_ac(m));
rep(end+1,:) = trystep('3. DC load now driven by measured P_ac', @() repoint_dc(m));
save_system(m);
fprintf('\n===== add_rlc_loads report =====\n');
for k = 1:size(rep,1)
    if rep{k,2}, fprintf('  OK    %s\n', rep{k,1}); else, fprintf('  FAIL  %s  ->  %s\n', rep{k,1}, rep{k,3}); end
end
fprintf('Backup: %s_preRLC.slx\nNext: out = sim(''%s'',''StopTime'',''0.36''); plot_test4(out,''short_3h_rlc'')\n\n', m, m);

function r = trystep(name, fh)
    try, fh(); r = {name, true, ''}; catch e, r = {name, false, e.message}; end
end

function pact_goto(m)
    L = [m '/Loads'];
    if getSimulinkBlockHandle([L '/Goto_Pact']) > 0, return; end
    add_block('simulink/Signal Routing/Goto', [L '/Goto_Pact'], 'GotoTag','Pact_tiers', ...
              'TagVisibility','global', 'Position',[850 120 910 150]);
    f = get_param([L '/MATLAB Function'],'PortHandles'); g = get_param([L '/Goto_Pact'],'PortHandles');
    add_line(L, f.Outport(2), g.Inport(1), 'autorouting','on');      % Pact (3 tiers, kW)
end

function repoint_dc(m)
    f = find_system(m,'LookUnderMasks','all','FollowLinks','on','BlockType','From','GotoTag','Pr_L');
    f = f(contains(f,'From_PrL_load'));
    if isempty(f), error('From_PrL_load not found'); end
    set_param(f{1},'GotoTag','P_ac_W');
end

function build_ac(m)
    S = [m '/AC Loads (RLC tier banks)'];
    if getSimulinkBlockHandle(S) > 0, return; end
    add_block('built-in/Subsystem', S, 'Position',[1060 300 1240 400], 'BackgroundColor','orange');
    lib = @(n,c) sps_lib(n,c);
    ph  = @(b) get_param([S '/' b],'PortHandles');
    el  = @(b) [ph(b).LConn ph(b).RConn];
    W   = @(a,b) add_line(S,a,b,'autorouting','on');
    % source (average-model inverter) and measurements
    add_block('simulink/Sources/Sine Wave', [S '/Inverter_ref'], 'Amplitude','V_ac*sqrt(2)', ...
              'Frequency','2*pi*f_ac', 'SampleTime','Ts', 'Position',[20 60 60 90]);
    add_block(lib('Controlled Voltage Source','powerlib/Electrical Sources/Controlled Voltage Source'), ...
              [S '/Inverter_230V'], 'Position',[100 50 140 110]);
    add_block(lib('Current Measurement','powerlib/Measurements/Current Measurement'), [S '/I_ac'], 'Position',[200 40 230 70]);
    add_block(lib('Voltage Measurement','powerlib/Measurements/Voltage Measurement'), [S '/V_ac_meas'], 'Position',[200 140 230 180]);
    add_block(lib('Ground','powerlib/Elements/Ground'), [S '/Gnd_ac'], 'Position',[130 400 160 430]);
    W(ph('Inverter_ref').Outport(1), ph('Inverter_230V').Inport(1));
    src = el('Inverter_230V'); im = el('I_ac'); vm = el('V_ac_meas'); gd = el('Gnd_ac');
    W(src(1), im(1));  A = im(2);  B = src(2);                  % AC bus node A, return node B
    W(vm(1), A); W(vm(2), B); W(gd(1), B);
    % banks
    bits = evalin('base','bank_bits');
    add_block('simulink/User-Defined Functions/MATLAB Function', [S '/BankLogic'], 'Position',[300 260 400 320]);
    ch = sfroot().find('-isa','Stateflow.EMChart','Path',[S '/BankLogic']);
    ch.Script = sprintf([ ...
      'function g = BankLogic(Pact)\n' ...
      '%% Binary-weighted RLC banks per tier: bank b of tier j = 2^(b-1) x %g kW\n' ...
      'bits = [%d %d %d];  Pb = %g;\n' ...
      'g = zeros(%d,1);  k = 0;\n' ...
      'for j = 1:3\n' ...
      '    n = min(round(max(Pact(j),0)/Pb), 2^bits(j)-1);\n' ...
      '    for b = 1:bits(j)\n' ...
      '        k = k + 1;  g(k) = double(bitand(uint32(n), uint32(2^(b-1))) > 0);\n' ...
      '    end\n' ...
      'end\n'], evalin('base','P_bank'), bits, evalin('base','P_bank'), sum(bits));
    ch.SampleTime = 'Ts_fc';
    add_block('simulink/Signal Routing/From', [S '/From_Pact'], 'GotoTag','Pact_tiers', 'Position',[220 275 270 305]);
    W(ph('From_Pact').Outport(1), ph('BankLogic').Inport(1));
    add_block('simulink/Signal Routing/Demux', [S '/Gates'], 'Outputs', num2str(sum(bits)), 'Position',[440 240 445 600]);
    W(ph('BankLogic').Outport(1), ph('Gates').Inport(1));
    SW  = lib('Ideal Switch','powerlib/Power Electronics/Ideal Switch');
    RLC = lib('Parallel RLC Branch','powerlib/Elements/Parallel RLC Branch');
    k = 0;
    for j = 1:3
        for b = 1:bits(j)
            k = k + 1;  w = 2^(b-1);  y = 40 + 70*(k-1);  nm = sprintf('T%d_bank%d_%gkW', j, b, w*evalin('base','P_bank'));
            add_block(SW,  [S '/SW_' nm], 'Position',[520 y 560 y+40]);
            add_block(RLC, [S '/' nm],    'Position',[620 y 650 y+40]);
            set_param([S '/' nm], 'BranchType','RLC', ...
                'Resistance', sprintf('V_ac^2/(%d*P_bank*1e3)', w), ...
                'Inductance', sprintf('V_ac^2/(2*pi*f_ac*%d*P_bank*1e3*tan(acos(pf_tier(%d))))', w, j), ...
                'Capacitance',sprintf('%d*P_bank*1e3*(tan(acos(pf_tier(%d)))-tan(acos(pf_corr)))/(2*pi*f_ac*V_ac^2)', w, j));
            W(ph('Gates').Outport(k), ph(['SW_' nm]).Inport(1));
            s = el(['SW_' nm]); r = el(nm);
            W(A, s(1)); W(s(2), r(1)); W(r(2), B);
            if ~isempty(ph(['SW_' nm]).Outport)
                add_block('simulink/Sinks/Terminator', [S '/T_' nm], 'Position',[580 y+45 590 y+55]);
                W(ph(['SW_' nm]).Outport(1), ph(['T_' nm]).Inport(1));
            end
        end
    end
    % P and Q: one-cycle moving averages (integral minus integral delayed by one period)
    add_block('simulink/Math Operations/Product', [S '/p_inst'], 'Position',[300 60 330 90]);
    W(ph('V_ac_meas').Outport(1), ph('p_inst').Inport(1)); W(ph('I_ac').Outport(1), ph('p_inst').Inport(2));
    add_block('simulink/Discrete/Delay', [S '/v_lag90'], 'DelayLength','round(1/(4*f_ac*Ts))', 'Position',[300 130 340 160]);
    W(ph('V_ac_meas').Outport(1), ph('v_lag90').Inport(1));
    add_block('simulink/Math Operations/Product', [S '/q_inst'], 'Position',[370 130 400 160]);
    W(ph('v_lag90').Outport(1), ph('q_inst').Inport(1)); W(ph('I_ac').Outport(1), ph('q_inst').Inport(2));
    movavg(S, 'p_inst', 'Pavg', 60);  movavg(S, 'q_inst', 'Qavg', 130);
    add_block('simulink/User-Defined Functions/MATLAB Function', [S '/PQ_PF'], 'Position',[760 60 860 160]);
    ch = sfroot().find('-isa','Stateflow.EMChart','Path',[S '/PQ_PF']);
    ch.Script = sprintf(['function [P, Q, PF] = PQ_PF(Pavg, Qavg)\n' ...
        '%% sign follows the measured direction of power flow (load side positive)\n' ...
        's = 1; if Pavg < 0, s = -1; end\n' ...
        'P = s*Pavg;  Q = s*Qavg;\n' ...
        'S = sqrt(P^2 + Q^2);  if S > 1, PF = P/S; else, PF = 1; end\n']);
    W(ph('Pavg_out').Outport(1), ph('PQ_PF').Inport(1)); W(ph('Qavg_out').Outport(1), ph('PQ_PF').Inport(2));
    tags = {'P_ac_W','Q_ac_var','PF_ac'};  logn = {'P_ac','Q_ac','PF_ac'};
    for k = 1:3
        add_block('simulink/Signal Routing/Goto', [S '/Goto_' tags{k}], 'GotoTag',tags{k}, 'TagVisibility','global', ...
                  'Position',[920 40+50*k 990 65+50*k]);
        o = ph('PQ_PF').Outport(k);  W(o, ph(['Goto_' tags{k}]).Inport(1));
        set_param(o,'DataLogging','on','DataLoggingNameMode','Custom','DataLoggingName',logn{k}, ...
                  'DataLoggingDecimateData','on','DataLoggingDecimation','200');
    end
    o = ph('V_ac_meas').Outport(1); set_param(o,'DataLogging','on','DataLoggingNameMode','Custom','DataLoggingName','v_ac', ...
                  'DataLoggingDecimateData','on','DataLoggingDecimation','5');
    o = ph('I_ac').Outport(1);      set_param(o,'DataLogging','on','DataLoggingNameMode','Custom','DataLoggingName','i_ac', ...
                  'DataLoggingDecimateData','on','DataLoggingDecimation','5');
end

function movavg(S, in, out, y)
    ph = @(b) get_param([S '/' b],'PortHandles');  W = @(a,b) add_line(S,a,b,'autorouting','on');
    add_block('simulink/Discrete/Discrete-Time Integrator', [S '/' out '_int'], 'SampleTime','Ts', 'Position',[440 y 480 y+30]);
    add_block('simulink/Discrete/Delay', [S '/' out '_dly'], 'DelayLength','round(1/(f_ac*Ts))', 'Position',[520 y+40 560 y+70]);
    add_block('simulink/Math Operations/Sum', [S '/' out '_diff'], 'Inputs','+-', 'Position',[600 y 620 y+30]);
    add_block('simulink/Math Operations/Gain', [S '/' out '_out'], 'Gain','f_ac', 'Position',[660 y 700 y+30]);
    W(ph(in).Outport(1), ph([out '_int']).Inport(1));
    W(ph([out '_int']).Outport(1), ph([out '_diff']).Inport(1));
    W(ph([out '_int']).Outport(1), ph([out '_dly']).Inport(1));
    W(ph([out '_dly']).Outport(1), ph([out '_diff']).Inport(2));
    W(ph([out '_diff']).Outport(1), ph([out '_out']).Inport(1));
end

function p = sps_lib(name, classic)
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

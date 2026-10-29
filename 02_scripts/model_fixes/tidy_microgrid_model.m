%% tidy_microgrid_model.m  -  clean, readable top level for microgrid_top_fixed.slx (R2025a)
% Run LAST (after v2 ... v2h). Behaviour is unchanged except one bug fix:
%   * all top-level Goto tags -> global (PV curtailment could not see [SoC_Battery] before)
% Layout:
%   * old scattered scopes + their feeders, broken tags, commented old inverter removed
%   * blocks grouped into named, colour-coded subsystems (power stage top row, control bottom row)
%   * one 'Monitoring' subsystem with a 6-channel scope
root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(fullfile(root,'01_model'), fullfile(root,'01_model','_rebuild_source'), fullfile(root,'02_scripts'), fullfile(root,'02_scripts','model_fixes'), fullfile(root,'03_data'));
cd(fullfile(root,'01_model'));
evalin('base','init_microgrid');
m = 'microgrid_top_fixed';
if bdIsLoaded(m), close_system(m,0); end
copyfile([m '.slx'], [m '_preTidy.slx'], 'f');                 % backup
load_system(m);
rep = {};
rep(end+1,:) = trystep('1. All top-level Goto tags -> global', @() globalize(m));
rep(end+1,:) = trystep('2. Remove old scopes, broken tags, old inverter', @() declutter(m));
G = groups();
for k = 1:size(G,1)
    rep(end+1,:) = trystep(sprintf('3.%d Group: %s', k, G{k,1}), @() group(m, G{k,:})); %#ok<AGROW>
end
rep(end+1,:) = trystep('4. Monitoring subsystem (6-channel scope)', @() monitoring(m));
rep(end+1,:) = trystep('5. Layout, colours, labels', @() layout(m));
save_system(m);
fprintf('\n===== tidy_microgrid_model report =====\n');
for k = 1:size(rep,1)
    if rep{k,2}, fprintf('  OK    %s\n', rep{k,1}); else, fprintf('  FAIL  %s  ->  %s\n', rep{k,1}, rep{k,3}); end
end
fprintf('\nBackup: %s_preTidy.slx.  Next: short test  out = sim(''%s'',''StopTime'',''0.36''); plot_test4(out,''short_3h_tidy'')\n\n', m, m);

%% ===================== helpers =====================
function r = trystep(name, fh)
    try, fh(); r = {name, true, ''}; catch e, r = {name, false, e.message}; end
end
function h = blk(m, name)          % find a top-level block by name (line breaks / double spaces ignored)
    b = find_system(m,'SearchDepth',1,'LookUnderMasks','all','FollowLinks','on');
    nm = cellfun(@(x) strtrim(regexprep(get_param(x,'Name'),'\s+',' ')), b, 'UniformOutput',false);
    i = find(strcmp(nm, name), 1);
    if isempty(i), error('block "%s" not found', name); end
    h = get_param(b{i},'Handle');
end
function globalize(m)
    g = find_system(m,'SearchDepth',1,'BlockType','Goto');
    for k = 1:numel(g), set_param(g{k},'TagVisibility','global'); end
end
function declutter(m)
    del = {'Battery_scope','Supercapacitor_scope','P_scope','PV_Scope','PV Voltage Current','Scope','Load_scope', ...
           'From','From3','From6','From10','From11','From12','From23','From24','From25','From26','From29', ...
           'From34','From35','From37','From38','From4','Mux','Subsystem','Current Measurement','Goto12'};
    for k = 1:numel(del)
        try
            h = blk(m, del{k});
            lh = get_param(h,'LineHandles'); f = fieldnames(lh);
            for j = 1:numel(f), l = lh.(f{j}); l = l(l > 0); if ~isempty(l), delete_line(l); end, end
            delete_block(h);
        catch
        end
    end
    l = find_system(m,'SearchDepth',1,'FindAll','on','Type','line','Connected','off');  % dangling stubs
    for k = 1:numel(l), try, delete_line(l(k)); catch, end, end
end
function G = groups()
    G = { 'PV Array (2 x 19.2 kW)', {'PV Generation','PV Generation 2','Bus Selector','Bus Selector PV2','Product','Product PV2','P_PV_total','Goto4'}, 'lightBlue';
          'Battery Pack + DC-DC', {'Battery','Bidirectional DC-DC converter For Battery','Bus Selector1','Goto6','Goto7','I_bat_neg','SoC_coulomb','Goto8','From17','From18'}, 'green';
          'Supercapacitor + DC-DC', {'Supercapacitor','Bidirectional DC-DC converter For Supercapacitor','Bus Selector2','Goto14','Goto15','Goto16','From32','From33'}, 'magenta';
          'DC Link 400 V', {'C_DC_Link','Voltage Measurement','Goto9'}, 'gray';
          'DC Load (inverter equivalent)', {'Load_DC_equivalent','I_load_meas','P_load_meas','I_load_ref','Load_DC_equiv','Vdc_limit','VDC_delay','From_PrL_load','From_VDC_load'}, 'orange';
          'EMS (LPF power split)', {'BESS','From1','From48','From49','From52','From53','From7','Goto','Goto2','Goto3'}, 'cyan';
          'Converter Control', {'Combined Control Battery/Supercapacitor','From15','From16','From30','From31','From36','From39','From42','V_DC_Ref','Goto10','Goto11','Goto18','Goto19'}, 'cyan';
          'Load Manager (adaptive shedding)', {'Load Manager','SoC_ZOH','SoC_pu','Discrete Derivative','dSoC_per_hour','Pdef_kW','From2','From5','L_delay','Goto1'}, 'yellow' };
end
function group(m, name, members, colour)
    h = [];
    for k = 1:numel(members)
        try, h(end+1) = blk(m, members{k}); catch, end %#ok<AGROW>
    end
    if isempty(h), error('none of the blocks found'); end
    before = find_system(m,'SearchDepth',1,'BlockType','SubSystem');
    Simulink.BlockDiagram.createSubsystem(h);
    after = find_system(m,'SearchDepth',1,'BlockType','SubSystem');
    s = setdiff(after, before);
    set_param(s{1},'Name',strrep(name,'/','-'),'BackgroundColor',colour);
    try, Simulink.BlockDiagram.arrangeSystem([m '/' strrep(name,'/','-')]); catch, end
end
function monitoring(m)
    s = [m '/Monitoring'];
    if getSimulinkBlockHandle(s) > 0, return; end
    add_block('built-in/Subsystem', s, 'BackgroundColor','white');
    tags = {'V_DC','V_Bat','SoC_Battery','P_PV','Pr_L','L'};
    add_block('simulink/Sinks/Scope', [s '/System Scope'], 'NumInputPorts', num2str(numel(tags)), ...
              'Position',[300 40 360 40+60*numel(tags)]);
    for k = 1:numel(tags)
        y = 40 + 60*(k-1);
        add_block('simulink/Signal Routing/From', [s '/From_' tags{k}], 'GotoTag',tags{k}, 'Position',[80 y 160 y+25]);
        add_line(s, ['From_' tags{k} '/1'], sprintf('System Scope/%d',k));
    end
end
function layout(m)
    P = @(n) [m '/' n];
    pos = { 'PV Array (2 x 19.2 kW)',          [ 80 120 260 260];
            'DC Link 400 V',                   [420 120 560 260];
            'Battery Pack + DC-DC',            [720  60 900 180];
            'Supercapacitor + DC-DC',          [720 220 900 340];
            'DC Load (inverter equivalent)',   [1060 120 1240 260];
            'EMS (LPF power split)',           [ 80 480 260 600];
            'Converter Control',               [340 480 520 600];
            'Load Manager (adaptive shedding)',[620 480 800 600];
            'Loads',                           [880 480 1060 600];
            'Monitoring',                      [1140 480 1280 600];
            'powergui',                        [ 20  10 100  50] };
    for k = 1:size(pos,1), try, set_param(P(pos{k,1}),'Position',pos{k,2}); catch, end, end
    for n = {'DC_Bus+','DC_Bus-'}, try, p = get_param(P(n{1}),'Position'); set_param(P(n{1}),'Position',[480 300+20*strcmp(n{1},'DC_Bus-') 510 314+20*strcmp(n{1},'DC_Bus-')]); catch, end, end
    try, set_param(P('Loads'),'BackgroundColor','yellow'); catch, end
    try
        l = find_system(m,'SearchDepth',1,'FindAll','on','Type','line');
        Simulink.BlockDiagram.routeLine(l);
    catch
    end
    note(m, 'POWER STAGE  -  PV, storage and load on the 400 V DC bus', [80 20 900 45]);
    note(m, 'CONTROL & ENERGY MANAGEMENT  -  signals exchanged through global Goto/From tags', [80 420 1100 445]);
    note(m, sprintf(['Microgrid for 12 flats  |  PV 38.4 kW  |  Battery 240 V / 130 kWh  |  SC 10 F / 250 V  |  ' ...
                     'Time compression: 1 h = %g s  |  Run init_microgrid / setup_paths first'], evalin('base','t_hour')), [80 650 1200 675]);
end
function note(m, txt, pos)
    try
        a = Simulink.Annotation(m, txt);
        a.Position = pos; a.FontSize = 14; a.FontWeight = 'bold';
    catch
    end
end

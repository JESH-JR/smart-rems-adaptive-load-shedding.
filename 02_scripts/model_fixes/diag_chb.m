%% diag_chb.m - where does the signal stop in CHB_inverter_v2?
m = 'CHB_inverter_v2'; if bdIsLoaded(m), close_system(m,0); end; load_system(m); B = @(n) [m '/' n];
lib = 'powerlib/Measurements/Voltage Measurement'; load_system('powerlib');
add_block(lib, B('dbg_Vdc1'), 'Position',[60 60 90 90]);  add_block(lib, B('dbg_VAB1'), 'Position',[300 60 330 90]);
for s = {'g1','PWM';'vdc1','dbg_Vdc1';'vab1','dbg_VAB1'}'
    add_block('simulink/Sinks/To Workspace', B(['TW_' s{1}]), 'VariableName',['d_' s{1}], 'SaveFormat','Array');
    add_line(m,[s{2} '/1'],['TW_' s{1} '/1'],'autorouting','on');
end
ph = @(n) get_param(B(n),'PortHandles'); d = ph('Vdc1'); c = ph('Cell1'); a = ph('dbg_Vdc1'); b = ph('dbg_VAB1');
add_line(m,d.LConn(1),a.LConn(1)); add_line(m,d.RConn(1),a.LConn(2));
add_line(m,c.LConn(1),b.LConn(1)); add_line(m,c.LConn(2),b.LConn(2));
out = sim(m,'StopTime','0.02');
g = out.get('d_g1'); if ndims(g) == 3, g = reshape(g, size(g,1)*size(g,2), []).'; end
v = out.get('d_vdc1'); ab = out.get('d_vab1');
fprintf('\nVdc base value = %g\n', evalin('base','Vdc'));
fprintf('gate g1: size %s, min %g, max %g, mean of each pulse %s\n', mat2str(size(g)), min(g(:)), max(g(:)), mat2str(mean(g,1),3));
fprintf('V across Vdc1      : min %g  max %g\n', min(v), max(v));
fprintf('V across Cell1 A-B : min %g  max %g\n', min(ab), max(ab));
fprintf('Cell1 ports: LConn %d, RConn %d | Universal Bridge mask params: %s\n', numel(c.LConn), numel(c.RConn), strjoin(get_param(B('Cell1'),'MaskNames')',', '));
close_system(m,0);   % do not save the debug blocks

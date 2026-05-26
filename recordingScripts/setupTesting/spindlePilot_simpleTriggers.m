% FastStimScript.m - Low-latency LSL + DAQ trigger loop

% Initialize LSL
lib = lsl_loadlib();
info = lsl_streaminfo(lib, 'StimMarkers', 'Markers', 1, 0, 'cf_string', 'StimMarkerUnique');
outlet = lsl_outlet(info);

s = daq.createSession('ni');


s.addDigitalChannel('Dev1', 'port1/line0:1', 'OutputOnly');
s.addDigitalChannel('Dev1','port1/line2','OutputOnly');

condition = 'DEFAULT';
%%
while true
    % START
    outlet.push_sample({[condition '_START']});
    s.outputSingleScan([1 0 1]);
    s.outputSingleScan([0 0 0]);
    disp('Start marker sent');

    pause(0.5 + rand() * 19.5);

    outlet.push_sample({[condition '_END']});
    s.outputSingleScan([1 0 1]);
    s.outputSingleScan([0 0 0]);
    disp('Start marker sent');

    pause(2);  % fixed 2s before next START
end
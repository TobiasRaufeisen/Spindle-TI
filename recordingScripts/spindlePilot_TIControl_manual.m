%% Set Up Lab Streaming Layer (LSL) Marker Outlet
disp('Setting up LSL Marker stream...');
lib = lsl_loadlib();
info = lsl_streaminfo(lib, 'StimulationMarkers', 'Markers', 1, 0, 'cf_string', 'StimulationMarkerID');
markerOutlet = lsl_outlet(info);

%% Set Up NIDAQ Triggering
disp('Setting up NIDAQ...');
d = daq("ni");
addoutput(d, "Dev1", "Port1/Line0:1", "Digital");

%% Start stimulation HFC
markerString = 'TIStim_HFC_Start';
disp(['Sending marker: ' markerString]);
markerOutlet.push_sample({markerString});
disp('Sending trigger to NIDAQ...');
% write(d, [0 0]);
% pause(0.1);
% write(d, [1 0]);
% pause(0.1);
% write(d, [0 0]);

%% End stimulation HFC
markerString = 'TIStim_HFC_End';
disp(['Sending marker: ' markerString]);
markerOutlet.push_sample({markerString});
disp('Sending trigger to NIDAQ...');
% write(d, [0 0]);
% pause(0.1);
% write(d, [1 0]);
% pause(0.1);
% write(d, [0 0]);

%% Start stimulation 6Hz
markerString = 'TIStim_6Hz_Start';
disp(['Sending marker: ' markerString]);
markerOutlet.push_sample({markerString});
disp('Sending trigger to NIDAQ...');
% write(d, [0 0]);
% pause(0.1);
% write(d, [1 0]);
% pause(0.1);
% write(d, [0 0]);

%% End stimulation 6Hz
markerString = 'TIStim_6Hz_End';
disp(['Sending marker: ' markerString]);
markerOutlet.push_sample({markerString});
disp('Sending trigger to NIDAQ...');
% write(d, [0 0]);
% pause(0.1);
% write(d, [1 0]);
% pause(0.1);
% write(d, [0 0]);
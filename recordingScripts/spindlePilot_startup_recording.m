function spindlePilot_startup_recording()
    % SPINDLEPILOT_STARTUP_RECORDING  Environment setup used on the RECORDING
    % computer during data acquisition.
    %
    % ARCHIVAL: preserved to document the experiment-time setup. It is NOT part
    % of the analysis pipeline (use the root spindlePilot_startup.m for analysis)
    % and references the original recording-PC file system (D:).

    fprintf('Setting up spindlePilot RECORDING environment...\n');

    % Repo root (parent of this recordingScripts folder)
    project_root = fileparts(fileparts(mfilename('fullpath')));

    % Toolboxes lived under D:\matlab\toolboxes on the recording PC; add
    % the equivalent location for your own machine here if needed.

    addpath(genpath(project_root));
    addpath(fullfile(project_root, 'config'));

    % Data directories as used on the recording PC (original locations):
    data_paths.raw       = 'D:\data\SpindlePilot';
    data_paths.processed = 'D:\data\SpindlePilot\processed_data';
    assignin('base', 'data_paths', data_paths);

    analysis_config();
    fprintf('Recording environment ready!\n');
end

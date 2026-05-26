function spindlePilot_launchBrowser(subject, session)
% spindlePilot_launchBrowser - Launch enhanced EEG browser for sleep data
%
% This function launches the enhanced browser using pre-loaded data from workspace.
% Make sure to run spindlePilot_loadData first to load all data.
%
% Features:
% - Channel-specific event visualization (spindles/slowwaves show only on their detected channels)
% - Sleep stage filtering (show only selected stages, skip others)
% - Experimental condition visualization (optional timeline)
% - Interactive navigation and controls
% - Hypnogram overview with current position indicator
%
% Inputs:
%   subject - Subject ID (e.g., 'sub10')
%   session - Session ID (e.g., 'ses1')
%
% Usage:
%   % First load data:
%   spindlePilot_loadData
%   
%   % Then launch browser:
%   spindlePilot_launchBrowser('sub10', 'ses1')
%
% Required workspace variables (created by spindlePilot_loadData):
%   - analysisData_saved
%   - all_spindles
%   - all_slowwaves
%   - all_sleep_stages

fprintf('=== SPINDLEPILOT ENHANCED BROWSER ===\n');

%% Check inputs
if nargin < 2
    error('Usage: spindlePilot_launchBrowser(subject, session)\nExample: spindlePilot_launchBrowser(''sub10'', ''ses1'')');
end

%% Check if required data is loaded in workspace
required_vars = {'analysisData_saved', 'all_spindles', 'all_slowwaves', 'all_sleep_stages'};
missing_vars = {};

for i = 1:length(required_vars)
    if ~evalin('base', sprintf('exist(''%s'', ''var'')', required_vars{i}))
        missing_vars{end+1} = required_vars{i};
    end
end

if ~isempty(missing_vars)
    fprintf('ERROR: Missing required data in workspace!\n');
    fprintf('Missing variables: %s\n', strjoin(missing_vars, ', '));
    fprintf('\nPlease run spindlePilot_loadData first to load the data.\n');
    fprintf('Or load from saved file: load(''spindlePilot_loadedData.mat'')\n');
    return;
end

%% Get data from workspace
try
    analysisData_saved = evalin('base', 'analysisData_saved');
    all_spindles = evalin('base', 'all_spindles');
    all_slowwaves = evalin('base', 'all_slowwaves');
    all_sleep_stages = evalin('base', 'all_sleep_stages');
    
    fprintf('Successfully loaded data from workspace.\n');
catch ME
    fprintf('Error accessing workspace data: %s\n', ME.message);
    return;
end

%% Validate subject and session
try
    if ~isfield(analysisData_saved, subject)
        fprintf('ERROR: Subject ''%s'' not found in data.\n', subject);
        fprintf('Available subjects: %s\n', strjoin(fieldnames(analysisData_saved), ', '));
        return;
    end
    
    if ~isfield(analysisData_saved.(subject), session)
        fprintf('ERROR: Session ''%s'' not found for subject ''%s''.\n', session, subject);
        fprintf('Available sessions: %s\n', strjoin(fieldnames(analysisData_saved.(subject)), ', '));
        return;
    end
    
    subj_data = analysisData_saved.(subject).(session);
    eeg_data = subj_data.eeg;
    
    fprintf('Found data for %s, %s\n', subject, session);
    
catch ME
    fprintf('Error validating data: %s\n', ME.message);
    return;
end

%% Filter data for this subject
try
    fprintf('Filtering events for subject...\n');
    
    subj_spindles = all_spindles(strcmp(all_spindles.Subject, subject), :);
    subj_slowwaves = all_slowwaves(strcmp(all_slowwaves.Subject, subject), :);
    subj_sleep_stages = all_sleep_stages(strcmp(all_sleep_stages.Subject, subject), :);
    
    fprintf('  Spindles: %d\n', height(subj_spindles));
    fprintf('  Slow waves: %d\n', height(subj_slowwaves));
    fprintf('  Sleep stages: %d epochs\n', height(subj_sleep_stages));
    
catch ME
    fprintf('Error filtering data: %s\n', ME.message);
    return;
end

conditions_data = [];

%% Create and launch browser
try
    fprintf('Creating enhanced browser...\n');
    
    browser = spindlePilot_EnhancedBrowser(eeg_data, subj_spindles, subj_slowwaves, subj_sleep_stages, conditions_data, subject);
    
    fprintf('Launching GUI...\n');
    browser.createGUI();
    
    fprintf('✓ Browser launched successfully!\n');
    fprintf('\n=== KEYBOARD SHORTCUTS ===\n');
    fprintf('  ← →       Navigate (5s steps)\n');
    fprintf('  Shift+← → Navigate (30s steps)\n');
    fprintf('  ↑ ↓       Zoom in/out\n');
    fprintf('  Space     Jump to next spindle\n');
    fprintf('  S         Toggle sleep stage filtering\n');
    if ~isempty(conditions_data)
        fprintf('  C         Toggle condition display\n');
    end
    fprintf('  Mouse     Scroll to zoom\n');
    fprintf('=============================\n');
    
catch ME
    fprintf('Error creating browser: %s\n', ME.message);
    if length(ME.stack) > 0
        fprintf('Error in: %s (line %d)\n', ME.stack(1).name, ME.stack(1).line);
    end
end

end
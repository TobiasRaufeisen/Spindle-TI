function allData = spindlePilot_rejectArtifactsSeparated(allData, mode, varargin)
% spindlePilot_rejectArtifactsSeparated - Manual or automatic artifact rejection with zero replacement
%
% This function allows either manual marking of artifacts or automatic detection
% based on amplitude thresholds. Artifacts are replaced with zeros instead of removed.
%
% Usage:
%   allData = spindlePilot_rejectArtifactsSeparated(allData, 'manual')
%   allData = spindlePilot_rejectArtifactsSeparated(allData, 'automatic')
%   allData = spindlePilot_rejectArtifactsSeparated(allData, 'automatic', 'threshold', 200)
%   allData = spindlePilot_rejectArtifactsSeparated(allData, 'automatic', 'threshold', 200, 'min_duration', 0.1)
%
% Inputs:
%   allData - FieldTrip data structure
%   mode - 'manual' or 'automatic'
%   
% Optional parameters for automatic mode:
%   'threshold' - Amplitude threshold in microvolts (default: 150)
%   'min_duration' - Minimum artifact duration in seconds (default: 0.05)
%   'method' - 'peak' (single sample) or 'window' (sustained) (default: 'window')
%   'channels' - 'any' or 'all' channels must exceed threshold (default: 'any')

if nargin < 2
    mode = 'manual';
end

% Parse optional parameters for automatic mode
p = inputParser;
addParameter(p, 'threshold', 150, @isnumeric);      % microvolts
addParameter(p, 'min_duration', 0.05, @isnumeric);  % seconds  
addParameter(p, 'method', 'window', @ischar);       % 'peak' or 'window'
addParameter(p, 'channels', 'any', @ischar);        % 'any' or 'all'
parse(p, varargin{:});

auto_params = p.Results;

fprintf('Running artifact rejection in %s mode...\n', mode);
if strcmp(mode, 'automatic')
    fprintf('  Threshold: %.1f µV\n', auto_params.threshold);
    fprintf('  Min duration: %.3f seconds\n', auto_params.min_duration);
    fprintf('  Method: %s\n', auto_params.method);
    fprintf('  Channel criterion: %s\n', auto_params.channels);
end

subjects = fieldnames(allData);

for iSub = 1:numel(subjects)
    subject = subjects{iSub};
    sessions = fieldnames(allData.(subject));
    
    for iSes = 1:numel(sessions)
        session = sessions{iSes};
        
        % Check if main EEG data exists
        if ~isfield(allData.(subject).(session), 'eeg_main') || ...
           isempty(allData.(subject).(session).eeg_main)
            fprintf('No main EEG data found for %s, %s. Skipping.\n', subject, session);
            continue;
        end
        
        fprintf('\n===== Processing %s %s =====\n', subject, session);
        eeg_main = allData.(subject).(session).eeg_main;
        
        % For continuous data, there's typically only one trial
        if numel(eeg_main.trial) == 1
            fprintf('Processing continuous data for artifact rejection...\n');
            
            switch lower(mode)
                case 'manual'
                    artifactMatrix = manualArtifactDetection(eeg_main);
                    
                case 'automatic'
                    artifactMatrix = automaticArtifactDetection(eeg_main, auto_params);
                    
                otherwise
                    error('Mode must be either "manual" or "automatic"');
            end
            
            % Apply artifact rejection if any artifacts were found
            if ~isempty(artifactMatrix)
                fprintf('Found %d artifact segments.\n', size(artifactMatrix, 1));
                
                % Apply artifact rejection (zero replacement) to main EEG data
                [eeg_main_clean, artifact_info] = applyArtifactZeroReplacement(eeg_main, artifactMatrix, 'Main EEG');
                allData.(subject).(session).eeg_main = eeg_main_clean;
                
                % Apply same artifact rejection to excluded channels if they exist
                if isfield(allData.(subject).(session), 'eeg_excluded') && ...
                   ~isempty(allData.(subject).(session).eeg_excluded)
                    
                    eeg_excluded = allData.(subject).(session).eeg_excluded;
                    [eeg_excluded_clean, ~] = applyArtifactZeroReplacement(eeg_excluded, artifactMatrix, 'Excluded channels');
                    allData.(subject).(session).eeg_excluded = eeg_excluded_clean;
                end
                
                % Store artifact information
                allData.(subject).(session).artifactTimes = artifact_info.times;
                allData.(subject).(session).artifactSamples = artifactMatrix;
                allData.(subject).(session).artifactDuration = artifact_info.total_duration;
                allData.(subject).(session).artifactPercentage = artifact_info.percentage;
                allData.(subject).(session).artifactMask = artifact_info.artifact_mask;
                allData.(subject).(session).artifactMethod = mode;
                if strcmp(mode, 'automatic')
                    allData.(subject).(session).artifactParams = auto_params;
                end
                
                fprintf('Artifact replacement summary:\n');
                fprintf('  Total artifacts: %d\n', size(artifactMatrix, 1));
                fprintf('  Total duration replaced with zeros: %.2f seconds (%.1f%%)\n', ...
                        artifact_info.total_duration, artifact_info.percentage);
                
            else
                % No artifacts found
                fprintf('No artifacts were detected. Data remains unchanged.\n');
                allData.(subject).(session).artifactTimes = [];
                allData.(subject).(session).artifactSamples = [];
                allData.(subject).(session).artifactDuration = 0;
                allData.(subject).(session).artifactPercentage = 0;
                allData.(subject).(session).artifactMask = [];
                allData.(subject).(session).artifactMethod = mode;
            end
            
        else
            % Multiple trials - probably not continuous data
            fprintf('Warning: Found %d trials in the data. This function is designed for continuous data.\n', numel(eeg_main.trial));
            fprintf('Skipping %s %s\n', subject, session);
        end
        
        fprintf('Finished processing %s %s.\n', subject, session);
    end
end

fprintf('\nArtifact rejection (%s mode) completed for all subjects and sessions.\n', mode);
end

function artifactMatrix = manualArtifactDetection(eeg_data)
% Manual artifact detection using visual interface
fprintf('Instructions for artifact marking:\n');
fprintf('1. Use left mouse button to mark the beginning of an artifact\n');
fprintf('2. Use right mouse button to mark the end of an artifact\n');
fprintf('3. Press "q" when finished to save and continue\n\n');

cfg = [];
cfg.viewmode = 'butterfly';
cfg.continuous = 'yes';
cfg.blocksize = 30;
cfg.ylim = 'maxmin';

% Launch databrowser for marking artifacts
cfg = ft_databrowser(cfg, eeg_data);

% Check if artifacts were marked
if isfield(cfg, 'artfctdef') && ...
   isfield(cfg.artfctdef, 'visual') && ...
   isfield(cfg.artfctdef.visual, 'artifact')
    
    artifactMatrix = cfg.artfctdef.visual.artifact; % [start end] in samples
else
    artifactMatrix = [];
end
end

function artifactMatrix = automaticArtifactDetection(eeg_data, params)
% Automatic artifact detection using amplitude thresholds
fprintf('Running automatic artifact detection...\n');

data = eeg_data.trial{1};
fs = eeg_data.fsample;
time = eeg_data.time{1};
[n_channels, n_samples] = size(data);

threshold = params.threshold;
min_duration = params.min_duration;
min_samples = round(min_duration * fs);

fprintf('  Analyzing %d channels, %d samples\n', n_channels, n_samples);
fprintf('  Data range: %.1f to %.1f µV\n', min(data(:)), max(data(:)));

% Initialize artifact mask
artifact_mask = false(1, n_samples);

switch params.method
    case 'peak'
        % Single-sample threshold crossing
        switch params.channels
            case 'any'
                % Any channel exceeds threshold
                exceed_mask = any(abs(data) > threshold, 1);
            case 'all'
                % All channels exceed threshold
                exceed_mask = all(abs(data) > threshold, 1);
        end
        
        % Find continuous segments that meet minimum duration
        artifact_mask = findContinuousSegments(exceed_mask, min_samples);
        
    case 'window'
        % Sustained amplitude in sliding window
        window_size = round(0.1 * fs); % 100ms windows
        step_size = round(window_size / 4); % 25% overlap
        
        for i = 1:step_size:n_samples-window_size+1
            window_end = min(i + window_size - 1, n_samples);
            window_data = data(:, i:window_end);
            
            % Check if window exceeds threshold
            switch params.channels
                case 'any'
                    if any(max(abs(window_data), [], 2) > threshold)
                        artifact_mask(i:window_end) = true;
                    end
                case 'all'
                    if all(max(abs(window_data), [], 2) > threshold)
                        artifact_mask(i:window_end) = true;
                    end
            end
        end
        
        % Ensure minimum duration
        artifact_mask = findContinuousSegments(artifact_mask, min_samples);
end

% Convert mask to artifact matrix [start, end] in samples
artifactMatrix = maskToArtifactMatrix(artifact_mask);

% Report results
if ~isempty(artifactMatrix)
    total_artifact_samples = sum(artifact_mask);
    total_artifact_duration = total_artifact_samples / fs;
    artifact_percentage = total_artifact_samples / n_samples * 100;
    
    fprintf('  Detected %d artifact segments\n', size(artifactMatrix, 1));
    fprintf('  Total artifact duration: %.2f seconds (%.1f%%)\n', ...
            total_artifact_duration, artifact_percentage);
    
    % Show individual artifacts
    for i = 1:size(artifactMatrix, 1)
        start_time = time(artifactMatrix(i, 1));
        end_time = time(artifactMatrix(i, 2));
        duration = end_time - start_time;
        fprintf('    Artifact %d: %.2f - %.2f sec (%.3f sec)\n', ...
                i, start_time, end_time, duration);
    end
else
    fprintf('  No artifacts detected above threshold\n');
end
end

function continuous_mask = findContinuousSegments(binary_mask, min_length)
% Find continuous segments in binary mask that meet minimum length requirement
continuous_mask = false(size(binary_mask));

% Find transitions
diff_mask = [false, diff(binary_mask) ~= 0];
transitions = find(diff_mask);

if binary_mask(1)
    transitions = [1, transitions];
end
if binary_mask(end)
    transitions = [transitions, length(binary_mask) + 1];
end

% Process segments
for i = 1:2:length(transitions)-1
    start_idx = transitions(i);
    end_idx = transitions(i+1) - 1;
    
    if end_idx - start_idx + 1 >= min_length
        continuous_mask(start_idx:end_idx) = true;
    end
end
end

function artifactMatrix = maskToArtifactMatrix(artifact_mask)
% Convert binary mask to [start, end] matrix
if ~any(artifact_mask)
    artifactMatrix = [];
    return;
end

% Find artifact boundaries
diff_mask = [false, diff(artifact_mask)];
starts = find(diff_mask == 1);
ends = find(diff_mask == -1) - 1;

% Handle edge cases
if artifact_mask(1)
    starts = [1, starts];
end
if artifact_mask(end)
    ends = [ends, length(artifact_mask)];
end

artifactMatrix = [starts', ends'];
end

function [eeg_clean, artifact_info] = applyArtifactZeroReplacement(eeg_data, artifactMatrix, data_type)
% Helper function to replace artifacts with zeros in EEG data
% This maintains the original time structure of the data

% Create a copy of the data
eeg_clean = eeg_data;
trial_length = length(eeg_data.time{1});

% Create artifact mask (true = artifact, false = good data)
artifact_mask = false(1, trial_length);

% Mark artifact segments and replace with zeros
total_artifact_duration = 0;
artifact_times = [];

for iArt = 1:size(artifactMatrix, 1)
    art_start = max(artifactMatrix(iArt, 1), 1);
    art_end = min(artifactMatrix(iArt, 2), trial_length);
    
    % Calculate indices for this specific artifact
    artifact_indices = art_start:art_end;
    
    % Mark these indices as artifacts
    artifact_mask(artifact_indices) = true;
    
    % Replace artifact segments with zeros
    eeg_clean.trial{1}(:, artifact_indices) = 0;
    
    % Calculate duration of this artifact
    art_duration = (art_end - art_start + 1) / eeg_data.fsample;
    total_artifact_duration = total_artifact_duration + art_duration;
    
    % Store artifact times
    artifact_times(end+1, :) = [eeg_data.time{1}(art_start), eeg_data.time{1}(art_end)];
    
    fprintf('  %s - Artifact %d: %.2f to %.2f seconds (%.2f seconds) - REPLACED WITH ZEROS\n', ...
        data_type, iArt, eeg_data.time{1}(art_start), eeg_data.time{1}(art_end), art_duration);
end

% Calculate statistics
original_duration = eeg_data.time{1}(end) - eeg_data.time{1}(1);
replaced_percentage = total_artifact_duration / original_duration * 100;

% Store artifact information
artifact_info = struct();
artifact_info.times = artifact_times;
artifact_info.total_duration = total_artifact_duration;
artifact_info.percentage = replaced_percentage;
artifact_info.artifact_mask = artifact_mask; % Store the mask for future reference

fprintf('  %s - Replaced %.2f seconds with zeros (%.1f%%)\n', data_type, total_artifact_duration, replaced_percentage);
fprintf('  Original data length preserved: %d samples\n', trial_length);
end
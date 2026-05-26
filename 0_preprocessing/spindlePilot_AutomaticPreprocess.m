%% Automatic Preprocessing Pipeline for Multiple Participants
% This script runs the complete automatic preprocessing pipeline for multiple
% participants, processing one at a time to manage memory efficiently.
%
% FEATURES:
% - Loops over specified participants automatically
% - Clears memory between participants to prevent memory overflow
% - Saves progress after each participant
% - Can run without user intervention
%
% USAGE:
%   1. Configure participants, sessions, and paths below
%   2. Run this script
%   3. After completion, run spindlePilot_ManualTrialRejection.m for trial QC


%% ===== CONFIGURATION =====
% Initialize environment
scriptFile = mfilename('fullpath');
if isempty(scriptFile) || startsWith(scriptFile, tempdir)
    scriptFile = matlab.desktop.editor.getActiveFilename;
end
REPO_ROOT = fileparts(fileparts(scriptFile));  % repo root (portable)
cd(REPO_ROOT);
spindlePilot_startup()

% =========================================================================
% PATH CONFIGURATION
% =========================================================================
rawDataPath  = fullfile(REPO_ROOT, 'data', 'raw');  % in-repo, gitignored (see README "Data Availability")
% spindlePilot_finalizeAndSave creates `analysis/` and `EDF/` subfolders under saveDataPath.
saveDataPath = fullfile(REPO_ROOT, 'data');
% =========================================================================

% Define participants and sessions to process
participants = [17];  % Participant numbers to process
sessions = [1];         % Session numbers to process

% Preprocessing parameters
excludedChannelPatterns = {'AUX', 'Markers', 'XX', 'XXX'};
refChannel = {'TP9','TP10'};  % Reference channels (or 'all' for average reference)

% Create log file to track progress
logFile = fullfile(saveDataPath, sprintf('preprocessing_log_%s.txt', datestr(now, 'yyyy-mm-dd_HH-MM-SS')));
diary(logFile);

%% ===== MAIN PROCESSING LOOP =====
fprintf('========================================\n');
fprintf('AUTOMATIC PREPROCESSING PIPELINE\n');
fprintf('========================================\n');
fprintf('Start time: %s\n', datestr(now));
fprintf('Participants: %s\n', mat2str(participants));
fprintf('Sessions: %s\n', mat2str(sessions));
fprintf('Save path: %s\n', saveDataPath);
fprintf('========================================\n\n');

% Track processing statistics
totalParticipants = length(participants);
successCount = 0;
failedParticipants = [];
processingTimes = zeros(totalParticipants, 1);

for p = 1:totalParticipants
    participantID = participants(p);
    participantStartTime = tic;

    fprintf('\n\n');
    fprintf('========================================\n');
    fprintf('PROCESSING PARTICIPANT %d of %d (ID: %d)\n', p, totalParticipants, participantID);
    fprintf('========================================\n');
    fprintf('Start time: %s\n', datestr(now));

    try
        %% 1. Load data
        fprintf('\n--- Step 1: Loading data ---\n');
        allData = spindlePilot_loadData(rawDataPath, participantID, sessions);

        %% 2. Re-label electrodes
        fprintf('\n--- Step 2: Re-labeling electrodes ---\n');
        allData = spindlePilot_relabelElectrodes(allData);

        %% 3. Align timestamps across all data types
        fprintf('\n--- Step 3: Aligning timestamps ---\n');
        allData = spindlePilot_alignTimestamps(allData);

        %% 4. Separate channels for different processing pipelines
        fprintf('\n--- Step 4: Separating channels ---\n');
        allData = spindlePilot_separateChannels(allData, excludedChannelPatterns);

        %% 5. Filter and downsample main EEG data
        fprintf('\n--- Step 5: Cleaning main EEG (filtering, downsampling, artifact detection) ---\n');
        [allData, cleaningReport] = spindlePilot_cleanMainEEG(allData);

        %% 6. Transfer artifact information for trial rejection
        fprintf('\n--- Step 6: Transferring artifact information ---\n');
        allData = spindlePilot_transferCleaningArtifacts(allData, cleaningReport);

        %% 7. Resample main EEG and excluded channels to exactly 500 Hz
        fprintf('\n--- Step 7: Resampling data to exactly 500 Hz ---\n');
        subjects = fieldnames(allData);
        for i = 1:length(subjects)
            subject = subjects{i};
            sess = fieldnames(allData.(subject));
            for j = 1:length(sess)
                session = sess{j};

                % Resample main EEG data
                if isfield(allData.(subject).(session), 'eeg_main') && ...
                   ~isempty(allData.(subject).(session).eeg_main)
                    currentFs = allData.(subject).(session).eeg_main.fsample;
                    fprintf('Resampling main EEG for %s, %s (current: %.4f Hz -> 500 Hz)...\n', ...
                        subject, session, currentFs);
                    cfg = [];
                    cfg.resamplefs = 500;
                    cfg.detrend = 'no';
                    allData.(subject).(session).eeg_main = ft_resampledata(cfg, allData.(subject).(session).eeg_main);
                end

                % Resample excluded channels
                if isfield(allData.(subject).(session), 'eeg_excluded') && ...
                   ~isempty(allData.(subject).(session).eeg_excluded)
                    currentFs = allData.(subject).(session).eeg_excluded.fsample;
                    fprintf('Resampling excluded channels for %s, %s (current: %.4f Hz -> 500 Hz)...\n', ...
                        subject, session, currentFs);
                    cfg = [];
                    cfg.resamplefs = 500;
                    cfg.detrend = 'no';
                    allData.(subject).(session).eeg_excluded = ft_resampledata(cfg, allData.(subject).(session).eeg_excluded);
                end
            end
        end

        %% 8. Automatic channel rejection (only on main EEG data)
        fprintf('\n--- Step 8: Automatic channel rejection ---\n');
        allData = spindlePilot_autoRejectChannelsMain(allData);

        %% 9. Interpolate rejected channels back into main EEG data
        fprintf('\n--- Step 9: Interpolating rejected channels ---\n');
        allData = spindlePilot_interpolateChannels(allData, 'easycapM1.mat');

        %% 10. Re-reference main EEG data
        fprintf('\n--- Step 10: Re-referencing main EEG data ---\n');
        allData = spindlePilot_rereferenceMainData(allData, refChannel);

        %% 11. Merge excluded channels back with processed main EEG data
        fprintf('\n--- Step 11: Merging channels ---\n');
        allData = spindlePilot_mergeChannels(allData);

        %% 12. Automatic trial rejection and epoching
        fprintf('\n--- Step 12: Automatic trial rejection and epoching ---\n');
        allData = spindlePilot_createEpochsAllData2(allData, 0);

        %% 13. Save processed data
        fprintf('\n--- Step 13: Saving processed data ---\n');
        [allData_saved, analysisData, edfData] = spindlePilot_finalizeAndSave(allData, saveDataPath);

        % Success
        successCount = successCount + 1;
        processingTimes(p) = toc(participantStartTime);

        fprintf('\n========================================\n');
        fprintf('PARTICIPANT %d (ID: %d) COMPLETED SUCCESSFULLY\n', p, participantID);
        fprintf('Processing time: %.1f minutes\n', processingTimes(p)/60);
        fprintf('========================================\n');

    catch ME
        % Error handling
        processingTimes(p) = toc(participantStartTime);
        failedParticipants = [failedParticipants, participantID];

        fprintf('\n========================================\n');
        fprintf('ERROR: PARTICIPANT %d (ID: %d) FAILED\n', p, participantID);
        fprintf('========================================\n');
        fprintf('Error message: %s\n', ME.message);
        fprintf('Error location: %s (line %d)\n', ME.stack(1).name, ME.stack(1).line);
        fprintf('Processing time before failure: %.1f minutes\n', processingTimes(p)/60);
        fprintf('========================================\n');

        % Save error details to file
        errorFile = fullfile(saveDataPath, sprintf('ERROR_sub%d_%s.txt', ...
            participantID, datestr(now, 'yyyy-mm-dd_HH-MM-SS')));
        fid = fopen(errorFile, 'w');
        fprintf(fid, 'Error processing participant %d\n', participantID);
        fprintf(fid, 'Time: %s\n', datestr(now));
        fprintf(fid, 'Error message: %s\n', ME.message);
        fprintf(fid, 'Stack trace:\n');
        for s = 1:length(ME.stack)
            fprintf(fid, '  %s (line %d)\n', ME.stack(s).name, ME.stack(s).line);
        end
        fclose(fid);
    end

    %% Clear memory for next participant
    fprintf('\n--- Clearing memory for next participant ---\n');
    clear allData allData_saved analysisData edfData cleaningReport
    clear subjects subject sess session i j cfg

    % Force garbage collection
    pause(2);

    % Show memory status
    [~, systemview] = memory;
    fprintf('Available memory: %.1f GB\n', systemview.PhysicalMemory.Available / 1e9);

    % Estimated time remaining
    if p < totalParticipants
        avgTime = mean(processingTimes(1:p));
        remainingParticipants = totalParticipants - p;
        estimatedTimeRemaining = avgTime * remainingParticipants / 60;
        fprintf('Estimated time remaining: %.1f minutes\n', estimatedTimeRemaining);
    end
end

%% ===== FINAL SUMMARY =====
fprintf('\n\n');
fprintf('========================================\n');
fprintf('PREPROCESSING PIPELINE COMPLETED\n');
fprintf('========================================\n');
fprintf('End time: %s\n', datestr(now));
fprintf('Total participants processed: %d\n', totalParticipants);
fprintf('Successful: %d\n', successCount);
fprintf('Failed: %d\n', length(failedParticipants));

if ~isempty(failedParticipants)
    fprintf('Failed participant IDs: %s\n', mat2str(failedParticipants));
end

fprintf('\nProcessing times:\n');
for p = 1:totalParticipants
    if processingTimes(p) > 0
        fprintf('  Participant %d: %.1f minutes\n', participants(p), processingTimes(p)/60);
    end
end

totalTime = sum(processingTimes) / 60;
avgTime = mean(processingTimes(processingTimes > 0)) / 60;
fprintf('\nTotal processing time: %.1f minutes (%.1f hours)\n', totalTime, totalTime/60);
fprintf('Average time per participant: %.1f minutes\n', avgTime);

fprintf('\n========================================\n');
fprintf('NEXT STEP: Manual Trial Rejection\n');
fprintf('========================================\n');
fprintf('To perform manual trial rejection, run:\n');
fprintf('  spindlePilot_ManualTrialRejection\n');
fprintf('This will load the saved data and allow you to\n');
fprintf('inspect and reject trials interactively.\n');
fprintf('========================================\n');

% Close diary
diary off;

fprintf('\nLog saved to: %s\n', logFile);

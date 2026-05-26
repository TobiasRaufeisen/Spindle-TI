function allData = spindlePilot_createEpochsAllData(allData, preWindowSec)
% spindlePilot_createEpochsAllData
%
% INPUTS:
%   allData      - Structure containing EEG data and markers
%   preWindowSec - Duration in seconds for pre-stimulation window (default: 1)
%                  Set to 0 for no pre-window
%
% Marker patterns handled:
%   [COND]_[BLOCK]_[TRIAL]                       -> regular   (e.g. 1HZ_001_001)
%   [COND]_refract_[BLOCK]_[TRIAL]               -> refractory
%   [COND]_[rampingUp|rampingDown]_[BLOCK]_[TRIAL] -> ramping
%
% Each pattern lives in its own output field, e.g.
%   1HZ            – only regular epochs
%   1HZ_refract    – only refractory epochs
%   1HZ_rampingUp  – ramp-up segments
%   1HZ_rampingDown– ramp-down segments
% Illegal MATLAB field names are sanitised with matlab.lang.makeValidName.
%
% Epochs overlapping manually identified artifacts are excluded from the
% main epoched data and stored separately in epochedData_withArtifacts.
% For OFF conditions, the first trial of each block is removed from the
% main data and stored separately in epochedData_firstOFF (to exclude
% transition effects). The continuous EEG and metadata are preserved
% alongside the epoched output.
%
% OUTPUT STRUCTURE:
%   Continuous data (preserved):
%   allData.(subject).(session).eeg                        - Raw EEG data
%   allData.(subject).(session).eeg_main                   - Filtered EEG data
%   allData.(subject).(session).eeg_excluded               - Excluded channels
%   allData.(subject).(session).eventMarker                - Event markers
%   allData.(subject).(session).TI                         - TI data
%   allData.(subject).(session).excludedChannelsList       - Channel exclusion info
%   allData.(subject).(session).unusedChannelsRemoved      - Removed channels info
%
%   Epoched data:
%   allData.(subject).(session).epochedData                - Clean epochs for analysis
%   allData.(subject).(session).epochedData_withArtifacts  - Epochs with artifacts
%   allData.(subject).(session).epochedData_firstOFF       - First OFF trials (if any)
%   allData.(subject).(session).artifactInfo               - Consolidated artifact info
%   allData.(subject).(session).processingInfo             - Processing metadata

% Set default pre-window if not provided
if nargin < 2 || isempty(preWindowSec)
    preWindowSec = 1;
end

subjects = fieldnames(allData);

for i = 1:numel(subjects)
    subject  = subjects{i};
    sessions = fieldnames(allData.(subject));

    for j = 1:numel(sessions)
        session = sessions{j};
        fprintf('Processing Subject %s, Session %s (pre-window: %.1fs)\n', subject, session, preWindowSec);

        %% --- Basic data ---------------------------------------------------
        % Use processed EEG data if available, otherwise use raw data
        if isfield(allData.(subject).(session), 'eeg_main') && ...
           ~isempty(allData.(subject).(session).eeg_main)
            eeg_data = allData.(subject).(session).eeg_main;
            fprintf('  Using processed EEG data (eeg_main)\n');
        else
            eeg_data = allData.(subject).(session).eeg;
            fprintf('  Using raw EEG data (eeg)\n');
        end
        
        eventMarker_data = allData.(subject).(session).eventMarker;

        raw_t        = eeg_data.time{1};
        fs           = 1/mean(diff(raw_t));
        raw_start    = raw_t(1);
        raw_end_samp = numel(raw_t);

        marker_samp  = round((eventMarker_data.time_stamps - raw_start) * fs)+1;
        markers      = eventMarker_data.time_series;
        preWindowSamp = round(preWindowSec * fs);  % Convert seconds to samples

        %% --- Check for artifact information from any source -------------
        % Artifacts can come from multiple sources:
        % 1. spindlePilot_cleanMainEEG (slope-based detection + interpolation)
        %    transferred via spindlePilot_transferCleaningArtifacts
        % 2. spindlePilot_rejectArtifactsSeparated (manual or automatic detection + zero replacement)
        % Both store artifacts in the same format for consistency
        hasArtifacts = false;
        artifactTimes = [];
        artifactMethod = 'unknown';

        if isfield(allData.(subject).(session), 'artifactTimes') && ...
           ~isempty(allData.(subject).(session).artifactTimes)
            hasArtifacts = true;
            artifactTimes = allData.(subject).(session).artifactTimes;
            if isfield(allData.(subject).(session), 'artifactMethod')
                artifactMethod = allData.(subject).(session).artifactMethod;
            end
            fprintf('  Found %d artifact periods (method: %s)\n', size(artifactTimes, 1), artifactMethod);
        elseif isfield(allData.(subject).(session), 'artifactInfo') && ...
               isfield(allData.(subject).(session).artifactInfo, 'artifactTimes') && ...
               ~isempty(allData.(subject).(session).artifactInfo.artifactTimes)
            hasArtifacts = true;
            artifactTimes = allData.(subject).(session).artifactInfo.artifactTimes;
            if isfield(allData.(subject).(session).artifactInfo, 'method')
                artifactMethod = allData.(subject).(session).artifactInfo.method;
            end
            fprintf('  Found %d artifact periods in artifactInfo (method: %s)\n', size(artifactTimes, 1), artifactMethod);
        else
            fprintf('  No artifacts found from any source\n');
        end

        %% --- Stimulation bounds ------------------------------------------
        stimStartIdx = find(strcmp(markers,'STIM_START'));
        stimStopIdx  = find(strcmp(markers,'STIM_STOP'));
        if isempty(stimStartIdx) || isempty(stimStopIdx)
            warning('Missing STIM_START / STIM_STOP (%s / %s)',subject,session);
            continue
        end

        %% --- NOSTIM epochs (ALL periods outside STIM_START/STIM_STOP pairs) ---
        trl_nostim = []; nostim_names = {};
        
        % Create pairs of STIM_START/STIM_STOP
        stimPairs = [];
        for ss = 1:length(stimStartIdx)
            % Find the next STIM_STOP after this STIM_START
            nextStopIdx = find(stimStopIdx > stimStartIdx(ss), 1, 'first');
            if ~isempty(nextStopIdx)
                stimPairs(end+1, :) = [marker_samp(stimStartIdx(ss)), marker_samp(stimStopIdx(nextStopIdx))];
            end
        end
        
        if ~isempty(stimPairs)
            % Period before first stimulation
            if stimPairs(1,1) > 1
                trl_nostim = [trl_nostim; 1, stimPairs(1,1)-1, 0];
                nostim_names{end+1,1} = 'NOSTIM_pre';
            end
            
            % Periods between stimulation blocks
            for ss = 1:size(stimPairs,1)-1
                gap_start = stimPairs(ss,2) + 1;     % After current STIM_STOP
                gap_end = stimPairs(ss+1,1) - 1;    % Before next STIM_START
                if gap_end > gap_start
                    trl_nostim = [trl_nostim; gap_start, gap_end, 0];
                    nostim_names{end+1,1} = sprintf('NOSTIM_gap%d', ss);
                end
            end
            
            % Period after last stimulation
            if stimPairs(end,2) < raw_end_samp
                trl_nostim = [trl_nostim; stimPairs(end,2)+1, raw_end_samp, 0];
                nostim_names{end+1,1} = 'NOSTIM_post';
            end
        else
            % No valid stimulation pairs found, entire recording is NOSTIM
            trl_nostim = [1, raw_end_samp, 0];
            nostim_names{1,1} = 'NOSTIM_all';
        end
        
        if ~isempty(trl_nostim)
            cfg=[]; cfg.trl=trl_nostim;
            data_nostim = ft_redefinetrial(cfg,eeg_data);
            data_nostim.conditionNames = nostim_names;
            fprintf('  Created %d NOSTIM periods\n', length(nostim_names));
        else
            data_nostim=[];
            fprintf('  No NOSTIM periods found\n');
        end

        %% --- Iterate through stimulation markers -------------------------
        stimIdx  = stimStartIdx(1):stimStopIdx(end);
        stimMark = markers(stimIdx);
        stimSamp = marker_samp(stimIdx);

        condTrials = struct();
        epochs_out_of_bounds = 0;  % Counter for safety reporting

        for k = 1:numel(stimMark)-1
            mk = stimMark{k};
            if strcmp(mk,'STIM_START'), continue, end
            
            % Skip STIM_STOP markers (these are just boundary markers, not conditions)
            if strcmp(mk,'STIM_STOP')
                continue
            end

            parts = strsplit(mk,'_');
            if numel(parts) < 3, warning('Malformed marker: %s',mk); continue, end

            baseCond = parts{1};                    % e.g. '5HZ'
            isRefract = false; isRamping=false; rampType='';

            switch parts{2}
                case 'refract'
                    isRefract = true;
                    if numel(parts) >= 4
                        block=parts{3}; trial=parts{4};
                    else, warning('Malformed marker: %s',mk); continue, end
                case {'rampingUp','rampingDown'}
                    isRamping = true; rampType=parts{2};
                    if numel(parts) >=4
                        block=parts{3}; trial=parts{4};
                    else, warning('Malformed marker: %s',mk); continue, end
                otherwise
                    block=parts{2}; trial=parts{3};
            end

            % build *logical* condition label --------------------------------
            if isRefract
                condLabel = sprintf('%s_refract',baseCond);
            elseif isRamping
                condLabel = sprintf('%s_%s',baseCond,rampType);
            else
                condLabel = baseCond;   % regular stimulation
            end
            condField = matlab.lang.makeValidName(condLabel);

            % initialise storage if first encounter -------------------------
            if ~isfield(condTrials,condField)
                condTrials.(condField) = struct( ...
                    'trl',            [], ...
                    'conditionNames', {{}}, ...
                    'blocks',         [], ...
                    'trials',         [], ...
                    'is_refract',     [], ...
                    'is_ramping',     [], ...
                    'ramping_type',   {{}}, ...
                    'has_artifacts',  [], ...
                    'origLabel',      condLabel );
            end
            ct = condTrials.(condField);

            % epoch limits with safety bounds checking -----------------------
            beg = max(1, stimSamp(k) - preWindowSamp);  % Use flexible pre-window
            fin = stimSamp(k+1) - 1;
            
            % SAFETY CHECK: Ensure epoch bounds are within available data
            if beg > raw_end_samp || fin > raw_end_samp || beg >= fin
                fprintf('  WARNING: Epoch for %s (block %s, trial %s) extends beyond available data. ', ...
                        condLabel, block, trial);
                fprintf('Epoch bounds: [%d, %d], Data length: %d. Marking as artifact.\n', ...
                        beg, fin, raw_end_samp);
                epochs_out_of_bounds = epochs_out_of_bounds + 1;
                
                % Mark this epoch as having artifacts (out of bounds = artifact)
                hasEpochArtifact = true;
                
                % Use valid bounds for storage (but mark as artifact)
                beg = min(beg, raw_end_samp);
                fin = min(fin, raw_end_samp);
                if beg >= fin
                    beg = max(1, raw_end_samp - 100);  % Create minimal valid epoch
                    fin = raw_end_samp;
                end
            else
                % Normal artifact checking for epochs within bounds
                hasEpochArtifact = false;
                if hasArtifacts
                    % Convert sample indices to time for comparison
                    epoch_start_time = raw_t(beg);
                    epoch_end_time = raw_t(fin);
                    
                    % Check if epoch overlaps with any artifact period
                    for a = 1:size(artifactTimes, 1)
                        art_start = artifactTimes(a, 1);
                        art_end = artifactTimes(a, 2);
                        
                        % Check for overlap: epoch overlaps artifact if
                        % epoch_start < artifact_end AND epoch_end > artifact_start
                        if epoch_start_time < art_end && epoch_end_time > art_start
                            hasEpochArtifact = true;
                            break;
                        end
                    end
                end
            end
            
            offs = -(stimSamp(k) - beg);

            % store ----------------------------------------------------------
            ct.trl = [ct.trl; beg,fin,offs];

            trialName = sprintf('%s_block%s_trial%s',condLabel,block,trial);
            ct.conditionNames{end+1,1} = trialName;
            ct.blocks(end+1,1)       = str2double(block);
            ct.trials(end+1,1)       = str2double(trial);
            ct.is_refract(end+1,1)   = isRefract;
            ct.is_ramping(end+1,1)   = isRamping;
            ct.ramping_type{end+1,1} = rampType;
            ct.has_artifacts(end+1,1) = hasEpochArtifact;

            condTrials.(condField) = ct;            % write-back
        end

        %% --- Build FieldTrip structures with artifact separation --------
        epoched = struct();
        epoched_withArtifacts = struct();
        cFields = fieldnames(condTrials);

        for c = 1:numel(cFields)
            fld = cFields{c};
            if ~isempty(condTrials.(fld).trl)
                % Check if we have artifact information for this condition
                if isfield(condTrials.(fld), 'has_artifacts') && ...
                   ~isempty(condTrials.(fld).has_artifacts)
                    
                    % Ensure has_artifacts is the right size
                    n_trials = size(condTrials.(fld).trl, 1);
                    if length(condTrials.(fld).has_artifacts) ~= n_trials
                        warning('Artifact flags size mismatch for %s. Expected %d, got %d', ...
                                fld, n_trials, length(condTrials.(fld).has_artifacts));
                        % Create default (no artifacts) if size mismatch
                        condTrials.(fld).has_artifacts = false(n_trials, 1);
                    end
                    
                    % Separate trials with and without artifacts
                    clean_trials_idx = find(~condTrials.(fld).has_artifacts);
                    artifact_trials_idx = find(condTrials.(fld).has_artifacts);
                    
                    fprintf('    %s: %d clean, %d with artifacts\n', fld, ...
                            length(clean_trials_idx), length(artifact_trials_idx));
                else
                    % No artifact information available, treat all as clean
                    n_trials = size(condTrials.(fld).trl, 1);
                    clean_trials_idx = 1:n_trials;
                    artifact_trials_idx = [];
                    fprintf('    %s: %d trials (no artifact info)\n', fld, n_trials);
                end
                
                % Create clean data structure
                if ~isempty(clean_trials_idx)
                    cfg=[]; cfg.trl = condTrials.(fld).trl(clean_trials_idx, :);
                    dat_clean = ft_redefinetrial(cfg,eeg_data);

                    dat_clean.conditionNames = condTrials.(fld).conditionNames(clean_trials_idx);
                    dat_clean.blocks         = condTrials.(fld).blocks(clean_trials_idx);
                    dat_clean.trials         = condTrials.(fld).trials(clean_trials_idx);
                    dat_clean.is_refract     = condTrials.(fld).is_refract(clean_trials_idx);
                    dat_clean.is_ramping     = condTrials.(fld).is_ramping(clean_trials_idx);
                    dat_clean.ramping_type   = condTrials.(fld).ramping_type(clean_trials_idx);
                    
                    if isfield(condTrials.(fld), 'has_artifacts')
                        dat_clean.has_artifacts = condTrials.(fld).has_artifacts(clean_trials_idx);
                    else
                        dat_clean.has_artifacts = false(length(clean_trials_idx), 1);
                    end
                    dat_clean.origLabel      = condTrials.(fld).origLabel;

                    epoched.(fld) = dat_clean;
                end
                
                % Create artifact data structure
                if ~isempty(artifact_trials_idx)
                    cfg=[]; cfg.trl = condTrials.(fld).trl(artifact_trials_idx, :);
                    dat_artifacts = ft_redefinetrial(cfg,eeg_data);

                    dat_artifacts.conditionNames = condTrials.(fld).conditionNames(artifact_trials_idx);
                    dat_artifacts.blocks         = condTrials.(fld).blocks(artifact_trials_idx);
                    dat_artifacts.trials         = condTrials.(fld).trials(artifact_trials_idx);
                    dat_artifacts.is_refract     = condTrials.(fld).is_refract(artifact_trials_idx);
                    dat_artifacts.is_ramping     = condTrials.(fld).is_ramping(artifact_trials_idx);
                    dat_artifacts.ramping_type   = condTrials.(fld).ramping_type(artifact_trials_idx);
                    dat_artifacts.has_artifacts  = condTrials.(fld).has_artifacts(artifact_trials_idx);
                    dat_artifacts.origLabel      = condTrials.(fld).origLabel;

                    epoched_withArtifacts.(fld) = dat_artifacts;
                end
            end
        end
        
        % Add NOSTIM data (always keep as clean - never reject for artifacts)
        if ~isempty(data_nostim)
            epoched.NOSTIM = data_nostim;
            fprintf('  NOSTIM: Always kept as clean data (no artifact rejection)\n');
        end

        %% --- Handle OFF trial removal (first trial of each OFF block) ---
        [epoched, epoched_firstOFF] = removeFirstOFFTrials(epoched);
        [epoched_withArtifacts, epoched_withArtifacts_firstOFF] = removeFirstOFFTrials(epoched_withArtifacts);
        
        allData.(subject).(session).epochedData = epoched;
        allData.(subject).(session).epochedData_withArtifacts = epoched_withArtifacts;
        
        % Store first OFF trials separately if any were found
        if ~isempty(fieldnames(epoched_firstOFF))
            allData.(subject).(session).epochedData_firstOFF = epoched_firstOFF;
        end
        if ~isempty(fieldnames(epoched_withArtifacts_firstOFF))
            allData.(subject).(session).epochedData_withArtifacts_firstOFF = epoched_withArtifacts_firstOFF;
        end
        
        % Update artifact information if present (consolidate existing fields)
        if hasArtifacts
            allData.(subject).(session).artifactInfo = struct();
            if isfield(allData.(subject).(session), 'artifactTimes')
                allData.(subject).(session).artifactInfo.artifactTimes = allData.(subject).(session).artifactTimes;
            elseif isfield(allData.(subject).(session), 'artifactInfo') && ...
                   isfield(allData.(subject).(session).artifactInfo, 'artifactTimes')
                % Keep existing artifactInfo
                continue;
            end
            
            % Consolidate other artifact fields if they exist
            artifactFields = {'artifactSamples', 'artifactDuration', 'artifactPercentage', ...
                             'artifactMethod', 'artifactParams', 'artifactMask'};
            for f = 1:length(artifactFields)
                fieldName = artifactFields{f};
                if isfield(allData.(subject).(session), fieldName)
                    allData.(subject).(session).artifactInfo.(fieldName) = allData.(subject).(session).(fieldName);
                    allData.(subject).(session) = rmfield(allData.(subject).(session), fieldName);
                end
            end
        end
        
        % Store processing information
        allData.(subject).(session).processingInfo = struct();
        allData.(subject).(session).processingInfo.epochingPreWindow = preWindowSec;
        allData.(subject).(session).processingInfo.samplingRate = fs;
        allData.(subject).(session).processingInfo.epochingDate = datestr(now);

        %% --- Console summary ---------------------------------------------
        fprintf('Epoching complete for %s / %s\n',subject,session);
        
        if epochs_out_of_bounds > 0
            fprintf('  SAFETY: %d epochs were out of bounds and marked as artifacts\n', epochs_out_of_bounds);
        end
        
        % Report clean epochs (after OFF trial removal)
        fn = fieldnames(epoched);
        total_clean = 0;
        for ii=1:numel(fn)
            d = epoched.(fn{ii});
            nT = numel(d.trial);
            total_clean = total_clean + nT;
            fprintf('  %s (clean): %d epochs\n',fn{ii},nT);
        end
        
        % Report artifact epochs
        fn_art = fieldnames(epoched_withArtifacts);
        total_artifacts = 0;
        for ii=1:numel(fn_art)
            d = epoched_withArtifacts.(fn_art{ii});
            nT = numel(d.trial);
            total_artifacts = total_artifacts + nT;
            fprintf('  %s (with artifacts): %d epochs\n',fn_art{ii},nT);
        end
        
        % Report first OFF trials if any
        total_firstOFF = 0;
        if exist('epoched_firstOFF', 'var') && ~isempty(fieldnames(epoched_firstOFF))
            fn_firstOFF = fieldnames(epoched_firstOFF);
            for ii=1:numel(fn_firstOFF)
                d = epoched_firstOFF.(fn_firstOFF{ii});
                nT = numel(d.trial);
                total_firstOFF = total_firstOFF + nT;
                fprintf('  %s (first OFF trials): %d epochs\n',fn_firstOFF{ii},nT);
            end
        end
        
        % Final summary
        fprintf('  FINAL SUMMARY:\n');
        fprintf('    Clean epochs: %d\n', total_clean);
        fprintf('    Epochs with artifacts: %d\n', total_artifacts);
        fprintf('    First OFF trials removed: %d\n', total_firstOFF);

        if hasArtifacts && total_artifacts > 0
            fprintf('    Artifact rejection rate: %.1f%%\n', total_artifacts/(total_clean + total_artifacts)*100);
        end
    end
end
end

function [epoched_cleaned, epoched_firstOFF] = removeFirstOFFTrials(epoched)
% Remove first trial of each OFF block and store separately
%
% This function identifies OFF conditions, finds the first trial of each
% block for those conditions, removes them from the main epoched data,
% and stores them separately.

epoched_cleaned = epoched;
epoched_firstOFF = struct();

if isempty(epoched)
    return;
end

fieldNames = fieldnames(epoched);
firstOFF_count = 0;

for i = 1:length(fieldNames)
    fieldName = fieldNames{i};
    data = epoched.(fieldName);
    
    % Check if this is a pure OFF condition (contains 'OFF' but NOT ramping)
    isOFFCondition = contains(upper(fieldName), 'OFF') && ...
                     ~contains(upper(fieldName), 'RAMPING');
    
    % Also check origLabel if it exists
    if isfield(data, 'origLabel') && ~isempty(data.origLabel)
        isOFFCondition = isOFFCondition || ...
                        (contains(upper(data.origLabel), 'OFF') && ...
                         ~contains(upper(data.origLabel), 'RAMPING'));
    end
    
    % Debug output for all conditions
    if contains(upper(fieldName), 'OFF')
        if isOFFCondition
            fprintf('    %s: Pure OFF condition - will remove first trials\n', fieldName);
        else
            fprintf('    %s: Ramping condition - keeping all trials\n', fieldName);
        end
    end
    
    if isOFFCondition && isfield(data, 'blocks') && ~isempty(data.blocks)
        fprintf('    Processing OFF condition: %s\n', fieldName);
        fprintf('      Total trials: %d, Blocks range: %d-%d, Trials range: %d-%d\n', ...
                length(data.trial), min(data.blocks), max(data.blocks), ...
                min(data.trials), max(data.trials));
        
        % Find unique blocks and their first trials
        uniqueBlocks = unique(data.blocks);
        firstTrialIndices = [];
        
        for blockNum = uniqueBlocks'
            % Find all trials in this block
            blockTrialIndices = find(data.blocks == blockNum);
            
            if ~isempty(blockTrialIndices)
                % Debug: Show trial numbers in this block
                trialsInBlock = data.trials(blockTrialIndices);
                fprintf('        Block %d has trials: [%s], indices: [%s]\n', ...
                        blockNum, num2str(trialsInBlock'), num2str(blockTrialIndices'));
                
                % Find the trial with the smallest trial number in this block
                [minTrialNum, minTrialIdx] = min(data.trials(blockTrialIndices));
                firstTrialIdx = blockTrialIndices(minTrialIdx);
                firstTrialIndices(end+1) = firstTrialIdx;
                
                fprintf('      Block %d: Removing trial %d (index %d) - was minimum trial number of [%s]\n', ...
                        blockNum, minTrialNum, firstTrialIdx, num2str(trialsInBlock'));
            end
        end
        
        if ~isempty(firstTrialIndices)
            % Create structure for first OFF trials
            firstOFF_fieldName = [fieldName '_firstTrials'];
            firstOFF_fieldName = matlab.lang.makeValidName(firstOFF_fieldName);
            
            % Extract first trials using manual extraction (more robust than ft_selectdata)
            epoched_firstOFF.(firstOFF_fieldName) = extractTrialsManually(data, firstTrialIndices);
            
            % Add metadata for first OFF trials
            epoched_firstOFF.(firstOFF_fieldName).conditionNames = data.conditionNames(firstTrialIndices);
            epoched_firstOFF.(firstOFF_fieldName).blocks = data.blocks(firstTrialIndices);
            epoched_firstOFF.(firstOFF_fieldName).trials = data.trials(firstTrialIndices);
            epoched_firstOFF.(firstOFF_fieldName).is_refract = data.is_refract(firstTrialIndices);
            epoched_firstOFF.(firstOFF_fieldName).is_ramping = data.is_ramping(firstTrialIndices);
            epoched_firstOFF.(firstOFF_fieldName).ramping_type = data.ramping_type(firstTrialIndices);
            if isfield(data, 'has_artifacts')
                epoched_firstOFF.(firstOFF_fieldName).has_artifacts = data.has_artifacts(firstTrialIndices);
            end
            epoched_firstOFF.(firstOFF_fieldName).origLabel = data.origLabel;
            epoched_firstOFF.(firstOFF_fieldName).removedReason = 'First trial of OFF block';
            
            % Remove first trials from main data using manual extraction
            remainingIndices = setdiff(1:length(data.trial), firstTrialIndices);
            
            if ~isempty(remainingIndices)
                epoched_cleaned.(fieldName) = extractTrialsManually(data, remainingIndices);
                
                % Update metadata for remaining trials
                epoched_cleaned.(fieldName).conditionNames = data.conditionNames(remainingIndices);
                epoched_cleaned.(fieldName).blocks = data.blocks(remainingIndices);
                epoched_cleaned.(fieldName).trials = data.trials(remainingIndices);
                epoched_cleaned.(fieldName).is_refract = data.is_refract(remainingIndices);
                epoched_cleaned.(fieldName).is_ramping = data.is_ramping(remainingIndices);
                epoched_cleaned.(fieldName).ramping_type = data.ramping_type(remainingIndices);
                if isfield(data, 'has_artifacts')
                    epoched_cleaned.(fieldName).has_artifacts = data.has_artifacts(remainingIndices);
                end
                epoched_cleaned.(fieldName).origLabel = data.origLabel;
                
                firstOFF_count = firstOFF_count + length(firstTrialIndices);
                fprintf('      Removed %d first OFF trials, %d trials remaining\n', ...
                        length(firstTrialIndices), length(remainingIndices));
            else
                % All trials were first trials, remove the entire condition
                epoched_cleaned = rmfield(epoched_cleaned, fieldName);
                fprintf('      All trials were first trials - removed entire condition\n');
            end
        end
    end
end

if firstOFF_count > 0
    fprintf('  TOTAL: Removed %d first trials from pure OFF conditions (ramping conditions unchanged)\n', firstOFF_count);
else
    fprintf('  No pure OFF conditions found or no first trials to remove (ramping conditions unchanged)\n');
end
end

function data_out = extractTrialsManually(data_in, trial_indices)
% Manually extract specific trials from FieldTrip data structure
% More robust than ft_selectdata for some problematic data structures

data_out = data_in;

% Extract the specified trials
data_out.trial = data_in.trial(trial_indices);
data_out.time = data_in.time(trial_indices);

% Update sampleinfo if it exists
if isfield(data_in, 'sampleinfo')
    data_out.sampleinfo = data_in.sampleinfo(trial_indices, :);
end

% Update trialinfo if it exists
if isfield(data_in, 'trialinfo')
    data_out.trialinfo = data_in.trialinfo(trial_indices, :);
end

% Keep other fields unchanged (label, fsample, grad, elec, etc.)
% These don't depend on trial selection
end
function allData = spindlePilot_createEpochsAllData2(allData, preWindowSec)
% spindlePilot_createEpochsAllData2
%
% 1) Create epochs for all stimulation conditions + NOSTIM
% 2) Epoch TI data using the same temporal boundaries as EEG
% 3) Separate epochs with artifacts (based on artifactTimes)
% 4) Remove first OFF trial of each OFF block (stored separately)
% 5) Auto-reject OFF/OFF_refract trials that occur immediately
%    after OFF_rampingDown, moving them to epochedData_withArtifacts
%
% INPUTS:
%   allData      - Structure containing EEG data, TI data, and markers
%   preWindowSec - Duration in seconds for pre-stimulation window (default: 0)
%                  Set to 0 for no pre-window
%
% Marker patterns handled:
%   [COND]_[BLOCK]_[TRIAL]                         -> regular   (e.g. 1HZ_001_001)
%   [COND]_refract_[BLOCK]_[TRIAL]                 -> refractory
%   [COND]_[rampingUp|rampingDown]_[BLOCK]_[TRIAL] -> ramping
%
% After epoching, each logical pattern lives in its own field:
%   1HZ, 1HZ_refract, 1HZ_rampingUp, 1HZ_rampingDown, OFF, OFF_refract, ...
%
% TI DATA EPOCHING:
%   If TI data is present in allData.(subject).(session).TI, it will be epoched
%   using the same temporal boundaries as the EEG data. The following fields are
%   added to each epoched condition:
%     .TI_trial      - Cell array {1 x nTrials} of TI data matrices (channels x samples)
%     .TI_time       - Cell array {1 x nTrials} of time vectors relative to stim onset
%     .TI_sampleinfo - [nTrials x 2] matrix of [start, end] sample indices in raw TI data
%     .TI_fsample    - Scalar, TI sampling rate (Hz)
%     .TI_label      - Cell array of TI channel names
%
%   TI data preserves its original sampling rate and is NOT processed or filtered.
%   Time alignment is achieved by matching temporal boundaries from event markers.

if nargin < 2 || isempty(preWindowSec)
    preWindowSec = 0;
end

subjects = fieldnames(allData);

for i = 1:numel(subjects)
    subject  = subjects{i};
    sessions = fieldnames(allData.(subject));

    for j = 1:numel(sessions)
        session = sessions{j};
        fprintf('Processing Subject %s, Session %s (pre-window: %.1fs)\n', subject, session, preWindowSec);

        %% --- Basic data ---------------------------------------------------
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

        marker_samp   = round((eventMarker_data.time_stamps - raw_start) * fs) + 1;
        markers       = eventMarker_data.time_series;
        preWindowSamp = round(preWindowSec * fs);

        %% --- TI data preparation ------------------------------------------
        hasTIData = false;
        TI_data = [];
        TI_t = [];
        TI_fs = [];
        TI_start = [];
        TI_end_samp = [];
        TI_channels = {};

        if isfield(allData.(subject).(session), 'TI') && ...
           ~isempty(allData.(subject).(session).TI)
            hasTIData = true;
            TI_raw = allData.(subject).(session).TI;

            % Extract TI parameters
            TI_t = TI_raw.time_stamps;
            TI_fs = str2double(TI_raw.info.nominal_srate);
            TI_start = TI_t(1);
            TI_end_samp = numel(TI_t);

            % Get TI data matrix and channel info
            TI_data = TI_raw.time_series;  % Should be channels × samples
            if size(TI_data, 2) == numel(TI_t) && size(TI_data, 1) ~= numel(TI_t)
                % Data is already channels × samples
                n_TI_channels = size(TI_data, 1);
            elseif size(TI_data, 1) == numel(TI_t) && size(TI_data, 2) ~= numel(TI_t)
                % Data is samples × channels, transpose it
                TI_data = TI_data';
                n_TI_channels = size(TI_data, 1);
            else
                % Ambiguous or single channel
                if size(TI_data, 1) == 1 || size(TI_data, 2) == 1
                    TI_data = TI_data(:)';  % Force to row vector (1 × samples)
                    n_TI_channels = 1;
                else
                    warning('Cannot determine TI data orientation for %s/%s', subject, session);
                    hasTIData = false;
                end
            end

            % Generate channel labels if not present
            if isfield(TI_raw.info, 'channel') && ~isempty(TI_raw.info.channel)
                TI_channels = {TI_raw.info.channel.label};
            else
                for ch = 1:n_TI_channels
                    TI_channels{ch} = sprintf('TI_%02d', ch);
                end
            end

            fprintf('  Found TI data: %d channels, %.2f Hz, %.2f - %.2f sec\n', ...
                    n_TI_channels, TI_fs, TI_t(1), TI_t(end));
        else
            fprintf('  No TI data found for this session\n');
        end

        %% --- Artifact info (if present) ----------------------------------
        hasArtifacts   = false;
        artifactTimes  = [];
        artifactMethod = 'unknown';

        if isfield(allData.(subject).(session), 'artifactTimes') && ...
           ~isempty(allData.(subject).(session).artifactTimes)
            hasArtifacts   = true;
            artifactTimes  = allData.(subject).(session).artifactTimes;
            if isfield(allData.(subject).(session), 'artifactMethod')
                artifactMethod = allData.(subject).(session).artifactMethod;
            end
            fprintf('  Found %d artifact periods (method: %s)\n', size(artifactTimes, 1), artifactMethod);

        elseif isfield(allData.(subject).(session), 'artifactInfo') && ...
               isfield(allData.(subject).(session).artifactInfo, 'artifactTimes') && ...
               ~isempty(allData.(subject).(session).artifactInfo.artifactTimes)
            hasArtifacts   = true;
            artifactTimes  = allData.(subject).(session).artifactInfo.artifactTimes;
            if isfield(allData.(subject).(session).artifactInfo, 'method')
                artifactMethod = allData.(subject).(session).artifactInfo.method;
            end
            fprintf('  Found %d artifact periods in artifactInfo (method: %s)\n', size(artifactTimes, 1), artifactMethod);
        else
            fprintf('  No artifacts found from any source\n');
        end

        %% --- STIM bounds --------------------------------------------------
        stimStartIdx = find(strcmp(markers,'STIM_START'));
        stimStopIdx  = find(strcmp(markers,'STIM_STOP'));
        if isempty(stimStartIdx) || isempty(stimStopIdx)
            warning('Missing STIM_START / STIM_STOP (%s / %s)',subject,session);
            continue
        end

        %% --- NOSTIM epochs (outside STIM_START/STIM_STOP pairs) ----------
        trl_nostim    = [];
        nostim_names  = {};
        stimPairs     = [];

        for ss = 1:length(stimStartIdx)
            nextStopIdx = find(stimStopIdx > stimStartIdx(ss), 1, 'first');
            if ~isempty(nextStopIdx)
                stimPairs(end+1, :) = [marker_samp(stimStartIdx(ss)), marker_samp(stimStopIdx(nextStopIdx))];
            end
        end

        if ~isempty(stimPairs)
            if stimPairs(1,1) > 1
                trl_nostim = [trl_nostim; 1, stimPairs(1,1)-1, 0];
                nostim_names{end+1,1} = 'NOSTIM_pre';
            end

            for ss = 1:size(stimPairs,1)-1
                gap_start = stimPairs(ss,2) + 1;
                gap_end   = stimPairs(ss+1,1) - 1;
                if gap_end > gap_start
                    trl_nostim = [trl_nostim; gap_start, gap_end, 0];
                    nostim_names{end+1,1} = sprintf('NOSTIM_gap%d', ss);
                end
            end

            if stimPairs(end,2) < raw_end_samp
                trl_nostim = [trl_nostim; stimPairs(end,2)+1, raw_end_samp, 0];
                nostim_names{end+1,1} = 'NOSTIM_post';
            end
        else
            trl_nostim = [1, raw_end_samp, 0];
            nostim_names{1,1} = 'NOSTIM_all';
        end

        if ~isempty(trl_nostim)
            cfg=[]; cfg.trl=trl_nostim;
            data_nostim = ft_redefinetrial(cfg,eeg_data);
            data_nostim.conditionNames = nostim_names;
            fprintf('  Created %d NOSTIM periods\n', length(nostim_names));
        else
            data_nostim = [];
            fprintf('  No NOSTIM periods found\n');
        end

        %% --- Build condition-wise trl from stimulation markers -----------
        stimIdx  = stimStartIdx(1):stimStopIdx(end);
        stimMark = markers(stimIdx);
        stimSamp = marker_samp(stimIdx);

        condTrials          = struct();
        epochs_out_of_bounds = 0;

        for k = 1:numel(stimMark)-1
            mk = stimMark{k};
            if strcmp(mk,'STIM_START') || strcmp(mk,'STIM_STOP')
                continue
            end

            parts = strsplit(mk,'_');
            if numel(parts) < 3
                warning('Malformed marker: %s',mk);
                continue
            end

            baseCond   = parts{1};
            isRefract  = false;
            isRamping  = false;
            rampType   = '';
            block      = '';
            trial      = '';

            switch parts{2}
                case 'refract'
                    isRefract = true;
                    if numel(parts) >= 4
                        block = parts{3}; trial = parts{4};
                    else
                        warning('Malformed marker: %s',mk); continue
                    end
                case {'rampingUp','rampingDown'}
                    isRamping = true; rampType = parts{2};
                    if numel(parts) >= 4
                        block = parts{3}; trial = parts{4};
                    else
                        warning('Malformed marker: %s',mk); continue
                    end
                otherwise
                    block = parts{2}; trial = parts{3};
            end

            if isRefract
                condLabel = sprintf('%s_refract',baseCond);
            elseif isRamping
                condLabel = sprintf('%s_%s',baseCond,rampType);
            else
                condLabel = baseCond;
            end
            condField = matlab.lang.makeValidName(condLabel);

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
                    'origLabel',      condLabel, ...
                    'TI_trl',         [], ...
                    'TI_epoch_times', {{}});
            end
            ct = condTrials.(condField);

            beg = max(1, stimSamp(k) - preWindowSamp);
            fin = stimSamp(k+1) - 1;

            if beg > raw_end_samp || fin > raw_end_samp || beg >= fin
                fprintf('  WARNING: Epoch for %s (block %s, trial %s) out of bounds. ', ...
                        condLabel, block, trial);
                fprintf('Bounds: [%d, %d], Data length: %d. Marking as artifact.\n', ...
                        beg, fin, raw_end_samp);
                epochs_out_of_bounds = epochs_out_of_bounds + 1;

                hasEpochArtifact = true;

                beg = min(beg, raw_end_samp);
                fin = min(fin, raw_end_samp);
                if beg >= fin
                    beg = max(1, raw_end_samp - 100);
                    fin = raw_end_samp;
                end
            else
                hasEpochArtifact = false;
                if hasArtifacts
                    epoch_start_time = raw_t(beg);
                    epoch_end_time   = raw_t(fin);
                    for a = 1:size(artifactTimes, 1)
                        art_start = artifactTimes(a,1);
                        art_end   = artifactTimes(a,2);
                        if epoch_start_time < art_end && epoch_end_time > art_start
                            hasEpochArtifact = true;
                            break
                        end
                    end
                end
            end

            offs = -(stimSamp(k) - beg);

            ct.trl = [ct.trl; beg,fin,offs];
            trialName = sprintf('%s_block%s_trial%s',condLabel,block,trial);
            ct.conditionNames{end+1,1} = trialName;
            ct.blocks(end+1,1)         = str2double(block);
            ct.trials(end+1,1)         = str2double(trial);
            ct.is_refract(end+1,1)     = isRefract;
            ct.is_ramping(end+1,1)     = isRamping;
            ct.ramping_type{end+1,1}   = rampType;
            ct.has_artifacts(end+1,1)  = hasEpochArtifact;

            %% --- Compute corresponding TI epoch boundaries ------------------
            if hasTIData
                % Get time boundaries from EEG epoch
                epoch_start_time = raw_t(beg);
                epoch_end_time   = raw_t(fin);

                % Find corresponding TI samples using time boundaries
                % Add small tolerance for floating point comparison
                time_tolerance = 1e-6;
                TI_beg_idx = find(TI_t >= (epoch_start_time - time_tolerance), 1, 'first');
                TI_end_idx = find(TI_t <= (epoch_end_time + time_tolerance), 1, 'last');

                % Validate TI epoch boundaries
                if isempty(TI_beg_idx) || isempty(TI_end_idx) || TI_beg_idx > TI_end_idx
                    % TI data not available for this epoch - store empty markers
                    ct.TI_trl = [ct.TI_trl; NaN, NaN, NaN];
                    ct.TI_epoch_times{end+1,1} = [];
                else
                    % Compute offset in TI samples (relative to stimulation onset)
                    % Find TI sample closest to stim onset
                    stim_onset_time = raw_t(stimSamp(k));
                    [~, TI_stim_idx] = min(abs(TI_t - stim_onset_time));
                    TI_offs = -(TI_stim_idx - TI_beg_idx);

                    ct.TI_trl = [ct.TI_trl; TI_beg_idx, TI_end_idx, TI_offs];
                    ct.TI_epoch_times{end+1,1} = [epoch_start_time, epoch_end_time];
                end
            end

            condTrials.(condField) = ct;
        end

        %% --- Build FieldTrip epoched structures (clean vs withArtifacts) --
        epoched               = struct();
        epoched_withArtifacts = struct();
        cFields               = fieldnames(condTrials);

        for c = 1:numel(cFields)
            fld = cFields{c};
            if isempty(condTrials.(fld).trl)
                continue
            end

            n_trials = size(condTrials.(fld).trl, 1);
            if isfield(condTrials.(fld),'has_artifacts') && ~isempty(condTrials.(fld).has_artifacts)
                if numel(condTrials.(fld).has_artifacts) ~= n_trials
                    warning('Artifact flags size mismatch for %s, fixing as no-artifacts', fld);
                    condTrials.(fld).has_artifacts = false(n_trials,1);
                end

                clean_idx    = find(~condTrials.(fld).has_artifacts);
                art_idx      = find( condTrials.(fld).has_artifacts);

                fprintf('    %s: %d clean, %d with artifacts\n', fld, numel(clean_idx), numel(art_idx));
            else
                clean_idx = 1:n_trials;
                art_idx   = [];
                fprintf('    %s: %d trials (no artifact info)\n', fld, n_trials);
                condTrials.(fld).has_artifacts = false(n_trials,1);
            end

            if ~isempty(clean_idx)
                cfg=[]; cfg.trl = condTrials.(fld).trl(clean_idx,:);
                dat_clean = ft_redefinetrial(cfg,eeg_data);

                dat_clean.conditionNames = condTrials.(fld).conditionNames(clean_idx);
                dat_clean.blocks         = condTrials.(fld).blocks(clean_idx);
                dat_clean.trials         = condTrials.(fld).trials(clean_idx);
                dat_clean.is_refract     = condTrials.(fld).is_refract(clean_idx);
                dat_clean.is_ramping     = condTrials.(fld).is_ramping(clean_idx);
                dat_clean.ramping_type   = condTrials.(fld).ramping_type(clean_idx);
                dat_clean.has_artifacts  = condTrials.(fld).has_artifacts(clean_idx);
                dat_clean.origLabel      = condTrials.(fld).origLabel;

                % Add TI data if available
                if hasTIData && isfield(condTrials.(fld), 'TI_trl') && ~isempty(condTrials.(fld).TI_trl)
                    dat_clean = addTIDataToEpochs(dat_clean, condTrials.(fld), clean_idx, TI_data, TI_t, TI_fs, TI_channels);
                end

                epoched.(fld) = dat_clean;
            end

            if ~isempty(art_idx)
                cfg=[]; cfg.trl = condTrials.(fld).trl(art_idx,:);
                dat_art = ft_redefinetrial(cfg,eeg_data);

                dat_art.conditionNames = condTrials.(fld).conditionNames(art_idx);
                dat_art.blocks         = condTrials.(fld).blocks(art_idx);
                dat_art.trials         = condTrials.(fld).trials(art_idx);
                dat_art.is_refract     = condTrials.(fld).is_refract(art_idx);
                dat_art.is_ramping     = condTrials.(fld).is_ramping(art_idx);
                dat_art.ramping_type   = condTrials.(fld).ramping_type(art_idx);
                dat_art.has_artifacts  = condTrials.(fld).has_artifacts(art_idx);
                dat_art.origLabel      = condTrials.(fld).origLabel;

                % Add TI data if available
                if hasTIData && isfield(condTrials.(fld), 'TI_trl') && ~isempty(condTrials.(fld).TI_trl)
                    dat_art = addTIDataToEpochs(dat_art, condTrials.(fld), art_idx, TI_data, TI_t, TI_fs, TI_channels);
                end

                epoched_withArtifacts.(fld) = dat_art;
            end
        end

        % Add NOSTIM (always treated as clean)
        if ~isempty(data_nostim)
            epoched.NOSTIM = data_nostim;
            fprintf('  NOSTIM: Always kept as clean data (no artifact rejection)\n');
        end

        %% --- Auto-reject OFF trials after OFF_rampingDown ----------------
        [epoched, epoched_withArtifacts, nOFFafterRamp] = ...
            autoRejectOFFAfterRamping_local(epoched, epoched_withArtifacts, markers, stimStartIdx, stimStopIdx);

        %% --- Store epoched data in allData -------------------------------
        allData.(subject).(session).epochedData               = epoched;
        allData.(subject).(session).epochedData_withArtifacts = epoched_withArtifacts;


        %% --- Consolidate artifact info back into artifactInfo ------------
        if hasArtifacts
            if ~isfield(allData.(subject).(session),'artifactInfo')
                allData.(subject).(session).artifactInfo = struct();
            end
            allData.(subject).(session).artifactInfo.artifactTimes = artifactTimes;

            artifactFields = {'artifactSamples', 'artifactDuration', 'artifactPercentage', ...
                              'artifactMethod', 'artifactParams', 'artifactMask'};
            for f = 1:numel(artifactFields)
                fieldName = artifactFields{f};
                if isfield(allData.(subject).(session), fieldName)
                    allData.(subject).(session).artifactInfo.(fieldName) = ...
                        allData.(subject).(session).(fieldName);
                    allData.(subject).(session) = rmfield(allData.(subject).(session), fieldName);
                end
            end
        end

        %% --- Processing info ---------------------------------------------
        allData.(subject).(session).processingInfo = struct();
        allData.(subject).(session).processingInfo.epochingPreWindow = preWindowSec;
        allData.(subject).(session).processingInfo.samplingRate      = fs;
        allData.(subject).(session).processingInfo.epochingDate      = datestr(now);

        %% --- Console summary ---------------------------------------------
        fprintf('Epoching complete for %s / %s\n',subject,session);

        if epochs_out_of_bounds > 0
            fprintf('  SAFETY: %d epochs were out of bounds and marked as artifacts\n', epochs_out_of_bounds);
        end

        fn  = fieldnames(epoched);
        tot_clean = 0;
        for ii=1:numel(fn)
            d  = epoched.(fn{ii});
            nT = numel(d.trial);
            tot_clean = tot_clean + nT;
            fprintf('  %s (clean): %d epochs\n', fn{ii}, nT);
        end

        fnA = fieldnames(epoched_withArtifacts);
        tot_art = 0;
        for ii = 1:numel(fnA)
            d = epoched_withArtifacts.(fnA{ii});
            if ~isstruct(d) || ~isfield(d,'trial') || isempty(d)
                continue
            end
            nT = numel(d.trial);
            tot_art = tot_art + nT;
            fprintf('  %s (with artifacts): %d epochs\n', fnA{ii}, nT);
        end

        fprintf('  FINAL SUMMARY:\n');
        fprintf('    Clean epochs: %d\n', tot_clean);
        fprintf('    Epochs with artifacts: %d\n', tot_art);
        fprintf('    OFF-after-ramping auto-rejected: %d\n', nOFFafterRamp);


        if hasArtifacts && (tot_clean+tot_art) > 0
            fprintf('    Artifact rejection rate: %.1f%%\n', ...
                tot_art / (tot_clean + tot_art) * 100);
        end
    end
end
end

%% ------------------------------------------------------------------------
function [epoched, epoched_withArtifacts, nRejected] = ...
    autoRejectOFFAfterRamping_local(epoched, epoched_withArtifacts, markers, stimStartIdx, stimStopIdx)

nRejected = 0;

if isempty(epoched) || isempty(fieldnames(epoched))
    return
end

if isempty(stimStartIdx) || isempty(stimStopIdx)
    fprintf('  No STIM_START/STIM_STOP markers found. Skipping OFF-after-ramping auto-rejection.\n');
    return
end

stimRange   = stimStartIdx(1):stimStopIdx(end);
stimMarkers = markers(stimRange);

problematicOFFTrials = identifyProblematicOFFTrials(stimMarkers);

if isempty(problematicOFFTrials)
    fprintf('  No problematic OFF trials found (OFF after OFF_rampingDown)\n');
    return
end

fprintf('  Found %d OFF trials that occur after ramping down:\n', numel(problematicOFFTrials));
for k = 1:numel(problematicOFFTrials)
    fprintf('    %s\n', problematicOFFTrials{k});
end

offConditions = {'OFF','OFF_refract'};

for c = 1:numel(offConditions)
    condName = offConditions{c};
    if ~isfield(epoched,condName) || isempty(epoched.(condName))
        continue
    end

    data = epoched.(condName);

    [trialsToReject, remainingTrials] = findTrialsToReject(data, problematicOFFTrials);
    if isempty(trialsToReject)
        continue
    end

    fprintf('  %s: Auto-rejecting %d OFF-after-ramping trials\n', condName, numel(trialsToReject));

    rejectedData = extractTrialsManually(data, trialsToReject);
    rejectedData.conditionNames = data.conditionNames(trialsToReject);
    rejectedData.blocks         = data.blocks(trialsToReject);
    rejectedData.trials         = data.trials(trialsToReject);
    rejectedData.is_refract     = data.is_refract(trialsToReject);
    rejectedData.is_ramping     = data.is_ramping(trialsToReject);
    rejectedData.ramping_type   = data.ramping_type(trialsToReject);
    if isfield(data,'has_artifacts')
        rejectedData.has_artifacts = true(numel(trialsToReject),1);
    end
    rejectedData.origLabel       = data.origLabel;
    rejectedData.rejectionReason = 'OFF trial after ramping down';

    % Append to existing artifact data or create new
    if isfield(epoched_withArtifacts,condName) && ~isempty(epoched_withArtifacts.(condName))
        epoched_withArtifacts.(condName) = ...
            mergeFieldTripData(epoched_withArtifacts.(condName), rejectedData);
    else
        epoched_withArtifacts.(condName) = rejectedData;
    end

    % Keep remaining trials in clean data or remove condition
    if ~isempty(remainingTrials)
        cleanData = extractTrialsManually(data, remainingTrials);
        cleanData.conditionNames = data.conditionNames(remainingTrials);
        cleanData.blocks         = data.blocks(remainingTrials);
        cleanData.trials         = data.trials(remainingTrials);
        cleanData.is_refract     = data.is_refract(remainingTrials);
        cleanData.is_ramping     = data.is_ramping(remainingTrials);
        cleanData.ramping_type   = data.ramping_type(remainingTrials);
        if isfield(data,'has_artifacts')
            cleanData.has_artifacts = data.has_artifacts(remainingTrials);
        end
        cleanData.origLabel = data.origLabel;

        epoched.(condName) = cleanData;
    else
        epoched = rmfield(epoched, condName);
    end

    nRejected = nRejected + numel(trialsToReject);
end
end


%% ------------------------------------------------------------------------
function problematicTrials = identifyProblematicOFFTrials(stimMarkers)

problematicTrials = {};

for k = 1:(numel(stimMarkers)-1)
    currentMarker = stimMarkers{k};
    nextMarker    = stimMarkers{k+1};

    if strcmp(currentMarker,'STIM_START') || strcmp(currentMarker,'STIM_STOP') || ...
       strcmp(nextMarker, 'STIM_START')  || strcmp(nextMarker,  'STIM_STOP')
        continue
    end

    if contains(currentMarker,'OFF_rampingDown')
        if (contains(nextMarker,'OFF_') || startsWith(nextMarker,'OFF')) && ...
           ~contains(nextMarker,'ramping')
            problematicTrials{end+1} = nextMarker; %#ok<AGROW>
        end
    end
end

problematicTrials = unique(problematicTrials);
end

%% ------------------------------------------------------------------------
function [trialsToReject, remainingTrials] = findTrialsToReject(data, problematicMarkers)

trialsToReject  = [];
remainingTrials = [];

if ~isfield(data,'conditionNames') || isempty(data.conditionNames)
    remainingTrials = 1:numel(data.trial);
    return
end

for t = 1:numel(data.conditionNames)
    trialName    = data.conditionNames{t};
    isProblematic = false;

    for p = 1:numel(problematicMarkers)
        if matchesMarker(trialName, problematicMarkers{p})
            isProblematic = true;
            break
        end
    end

    if isProblematic
        trialsToReject(end+1) = t; %#ok<AGROW>
    else
        remainingTrials(end+1) = t; %#ok<AGROW>
    end
end
end

%% ------------------------------------------------------------------------
function matches = matchesMarker(trialName, marker)

matches = false;

markerParts = strsplit(marker,'_');
if numel(markerParts) < 3, return, end

markerCond  = markerParts{1};
markerBlock = str2double(markerParts{2});
markerTrial = str2double(markerParts{3});

trialParts = strsplit(trialName,'_');
if numel(trialParts) < 3, return, end

if contains(trialParts{2},'block')
    trialCond  = trialParts{1};
    trialBlock = str2double(strrep(trialParts{2},'block',''));
    trialTrial = str2double(strrep(trialParts{3},'trial',''));

    matches = strcmp(trialCond,markerCond) && ...
              (trialBlock == markerBlock) && ...
              (trialTrial == markerTrial);
end
end

%% ------------------------------------------------------------------------
function data_out = extractTrialsManually(data_in, trial_indices)

data_out = data_in;
data_out.trial = data_in.trial(trial_indices);
data_out.time  = data_in.time(trial_indices);

if isfield(data_in,'sampleinfo')
    data_out.sampleinfo = data_in.sampleinfo(trial_indices,:);
end
if isfield(data_in,'trialinfo')
    data_out.trialinfo = data_in.trialinfo(trial_indices,:);
end

% Handle TI data fields if present
if isfield(data_in,'TI_trial')
    data_out.TI_trial = data_in.TI_trial(trial_indices);
end
if isfield(data_in,'TI_time')
    data_out.TI_time = data_in.TI_time(trial_indices);
end
if isfield(data_in,'TI_sampleinfo')
    data_out.TI_sampleinfo = data_in.TI_sampleinfo(trial_indices,:);
end
% TI_fsample and TI_label don't need indexing as they're scalar/constant
end

%% ------------------------------------------------------------------------
function merged = mergeFieldTripData(data1, data2)

merged = data1;

merged.trial = [data1.trial, data2.trial];
merged.time  = [data1.time,  data2.time];

if isfield(data1,'sampleinfo') && isfield(data2,'sampleinfo')
    merged.sampleinfo = [data1.sampleinfo; data2.sampleinfo];
end
if isfield(data1,'trialinfo') && isfield(data2,'trialinfo')
    merged.trialinfo = [data1.trialinfo; data2.trialinfo];
end

metaFields = {'conditionNames','blocks','trials','is_refract', ...
              'is_ramping','ramping_type','has_artifacts','rejectionReason'};

for f = 1:numel(metaFields)
    fld = metaFields{f};
    if isfield(data1,fld) && isfield(data2,fld)
        if iscell(data1.(fld))
            merged.(fld) = [data1.(fld); data2.(fld)];
        end
    end
end

% Handle TI data fields
if isfield(data1,'TI_trial') && isfield(data2,'TI_trial')
    merged.TI_trial = [data1.TI_trial, data2.TI_trial];
end
if isfield(data1,'TI_time') && isfield(data2,'TI_time')
    merged.TI_time = [data1.TI_time, data2.TI_time];
end
if isfield(data1,'TI_sampleinfo') && isfield(data2,'TI_sampleinfo')
    merged.TI_sampleinfo = [data1.TI_sampleinfo; data2.TI_sampleinfo];
end
% TI_fsample and TI_label should be the same in both datasets, keep from data1
end

%% ------------------------------------------------------------------------
function data_out = addTIDataToEpochs(data_out, condTrial, trial_indices, TI_data, TI_t, TI_fs, TI_channels)
% addTIDataToEpochs - Adds TI data epochs to existing EEG epoched data
%
% This function epochs TI data using the same temporal boundaries as EEG epochs
% and adds them as new fields to the existing FieldTrip data structure.
%
% Inputs:
%   data_out      - FieldTrip structure with EEG epochs
%   condTrial     - Condition trial structure containing TI_trl info
%   trial_indices - Indices of trials to include
%   TI_data       - Raw TI data matrix (channels × samples)
%   TI_t          - TI time vector
%   TI_fs         - TI sampling rate
%   TI_channels   - Cell array of TI channel labels
%
% Outputs:
%   data_out      - Updated structure with TI_trial, TI_time, TI_sampleinfo, TI_fsample

n_trials = numel(trial_indices);
TI_trial = cell(1, n_trials);
TI_time = cell(1, n_trials);
TI_sampleinfo = zeros(n_trials, 2);

for t = 1:n_trials
    trial_idx = trial_indices(t);

    % Get TI trial definition for this trial
    TI_trl_row = condTrial.TI_trl(trial_idx, :);

    % Check if TI data is available for this trial
    if any(isnan(TI_trl_row))
        % No TI data for this trial - store empty
        TI_trial{t} = [];
        TI_time{t} = [];
        TI_sampleinfo(t, :) = [NaN, NaN];
    else
        TI_beg = TI_trl_row(1);
        TI_end = TI_trl_row(2);
        TI_off = TI_trl_row(3);

        % Extract TI data for this epoch
        TI_trial{t} = TI_data(:, TI_beg:TI_end);

        % Create time vector relative to stimulation onset
        n_samples = TI_end - TI_beg + 1;
        TI_time{t} = (TI_off:(TI_off + n_samples - 1)) / TI_fs;

        % Store sample info (start and end indices in original TI data)
        TI_sampleinfo(t, :) = [TI_beg, TI_end];
    end
end

% Add TI fields to the output structure
data_out.TI_trial = TI_trial;
data_out.TI_time = TI_time;
data_out.TI_sampleinfo = TI_sampleinfo;
data_out.TI_fsample = TI_fs;
data_out.TI_label = TI_channels;

end

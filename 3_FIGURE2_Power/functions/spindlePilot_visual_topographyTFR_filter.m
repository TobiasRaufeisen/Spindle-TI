function [all_data_filtered, trial_indices] = spindlePilot_visual_topographyTFR_filter(...
    all_data, trial_indices, config)
%SPINDLEPILOT_VISUAL_TOPOGRAPHYTFR_FILTER Apply filters to loaded data.
%
%   This function applies filters in the order specified by config.filter_order.
%   It is the second step in the topography pipeline.
%
%   Available filters:
%     - 'sleep_stage': Filter trials by sleep stage
%     - 'artifact': Reject artifacts using MAD-based z-score
%     - 'log_transform': Transform power to dB scale
%     - 'power_filter': Filter trials by spindle power presence
%     - 'zscore_spindle_power': Filter trials by z-scored spindle power threshold
%
%   INPUTS:
%     all_data - data structure from spindlePilot_visual_topographyTFR_load
%     trial_indices - trial indices from spindlePilot_visual_topographyTFR_load
%     config - configuration struct
%
%   OUTPUTS:
%     all_data_filtered - filtered data structure
%     trial_indices - updated trial indices after filtering

    % Call the apply_filter_pipeline function from compute_simple
    % We use a local copy of the function to avoid code duplication
    [all_data_filtered, trial_indices] = apply_filter_pipeline_local(...
        all_data, trial_indices, config);
end


function [all_data_filtered, trial_indices] = apply_filter_pipeline_local(all_data, trial_indices, config)
    % Apply filters in the order specified by config.filter_order

    all_data_filtered = all_data;
    participants = config.participants;
    conditions = config.conditions;

    % Apply each filter in the specified order
    for i = 1:length(config.filter_order)
        filter_name = config.filter_order{i};

        fprintf('\nFilter %d/%d: %s\n', i, length(config.filter_order), filter_name);

        switch lower(filter_name)
            case 'sleep_stage'
                if isfield(config, 'sleep_stage_filter') && config.sleep_stage_filter.enabled
                    [all_data_filtered, trial_indices] = filter_sleep_stage(...
                        all_data_filtered, trial_indices, participants, conditions, config);
                else
                    fprintf('  Skipped (disabled)\n');
                end

            case 'artifact'
                if config.artifact.apply
                    [all_data_filtered, trial_indices] = filter_artifacts(...
                        all_data_filtered, trial_indices, participants, conditions, config);
                else
                    fprintf('  Skipped (disabled)\n');
                end

            case 'log_transform'
                if config.transform.use_log_transform
                    all_data_filtered = apply_log_transform(...
                        all_data_filtered, participants, conditions);
                else
                    fprintf('  Skipped (disabled)\n');
                end

            case 'power_filter'
                if config.power_filter.enabled
                    [all_data_filtered, trial_indices] = filter_power(...
                        all_data_filtered, trial_indices, participants, conditions, config);
                else
                    fprintf('  Skipped (disabled)\n');
                end

            case 'zscore_spindle_power'
                if config.zscore_spindle_power.enabled
                    [all_data_filtered, trial_indices] = filter_zscore_spindle_power(...
                        all_data_filtered, trial_indices, participants, conditions, config);
                else
                    fprintf('  Skipped (disabled)\n');
                end

            otherwise
                warning('Unknown filter: %s', filter_name);
        end
    end

    % Apply trial summarization after all filters
    fprintf('\nApplying trial summarization: %s\n', config.summary.method);
    all_data_filtered = summarize_trials(all_data_filtered, participants, conditions, config);
end


function [all_data_filtered, trial_indices] = filter_sleep_stage(...
    all_data, trial_indices, participants, conditions, config)
    % Filter trials to only include specified sleep stages

    fprintf('  Stages: %s\n', strjoin(config.sleep_stage_filter.stages, ', '));

    % Load valid trial numbers per participant/condition
    sleep_stage_trials = load_sleep_stage_intervals(config);

    if isempty(fieldnames(sleep_stage_trials))
        warning('No sleep stage trial data loaded - skipping filter');
        all_data_filtered = all_data;
        return;
    end

    all_data_filtered = struct();
    n_total = 0;
    n_kept = 0;

    for p = 1:length(participants)
        participant = participants{p};
        if ~isfield(all_data, participant), continue; end

        for c = 1:length(conditions)
            condition = conditions{c};
            if ~isfield(all_data.(participant), condition), continue; end

            trials = all_data.(participant).(condition).trials;
            n_trials = size(trials, 1);
            n_total = n_total + n_trials;

            % Get valid trial numbers for this participant/condition
            if ~isfield(sleep_stage_trials, participant) || ...
               ~isfield(sleep_stage_trials.(participant), condition)
                fprintf('    %s %s: No valid trials found - excluding all trials\n', participant, condition);
                trial_indices.(participant).(condition).kept = [];
                continue;
            end

            valid_trial_nums = sleep_stage_trials.(participant).(condition);
            loaded_trial_nums = trial_indices.(participant).(condition).trial_num;

            % Find which loaded trials are in the valid list
            keep_mask = ismember(loaded_trial_nums, valid_trial_nums);

            % Keep only trials that passed
            if any(keep_mask)
                all_data_filtered.(participant).(condition).trials = trials(keep_mask, :, :, :);
                all_data_filtered.(participant).(condition).channels = all_data.(participant).(condition).channels;
                all_data_filtered.(participant).(condition).freq = all_data.(participant).(condition).freq;
                all_data_filtered.(participant).(condition).time = all_data.(participant).(condition).time;
                trial_indices.(participant).(condition).kept = trial_indices.(participant).(condition).trial_num(keep_mask);
                n_kept = n_kept + sum(keep_mask);

                % Preserve passing_electrodes information if it exists
                if isfield(trial_indices.(participant).(condition), 'passing_electrodes')
                    old_passing_electrodes = trial_indices.(participant).(condition).passing_electrodes;
                    kept_trial_nums = trial_indices.(participant).(condition).kept;
                    new_passing_electrodes = struct();

                    for t = 1:length(kept_trial_nums)
                        trial_num = kept_trial_nums(t);
                        field_name = sprintf('trial_%d', trial_num);
                        if isfield(old_passing_electrodes, field_name)
                            new_passing_electrodes.(field_name) = old_passing_electrodes.(field_name);
                        end
                    end

                    trial_indices.(participant).(condition).passing_electrodes = new_passing_electrodes;
                end
            else
                trial_indices.(participant).(condition).kept = [];
            end
        end
    end

    fprintf('  Kept %d/%d trials (%.1f%%)\n', n_kept, n_total, 100*n_kept/n_total);
end


function [all_data_filtered, trial_indices] = filter_artifacts(...
    all_data, trial_indices, participants, conditions, config)
    % Reject artifacts using MAD-based robust z-score

    fprintf('  Method: MAD-based z-score (threshold=%.1f)\n', config.artifact.mad_threshold);
    fprintf('  Handling: %s\n', config.artifact.handling);

    all_data_filtered = struct();
    n_total = 0;
    n_rejected = 0;

    for p = 1:length(participants)
        participant = participants{p};
        if ~isfield(all_data, participant), continue; end

        for c = 1:length(conditions)
            condition = conditions{c};
            if ~isfield(all_data.(participant), condition), continue; end

            trials = all_data.(participant).(condition).trials;
            [n_trials, n_channels, ~, ~] = size(trials);
            n_total = n_total + n_trials;

            % Compute per-channel per-trial power
            trial_power = squeeze(mean(mean(trials, 3, 'omitnan'), 4, 'omitnan'));

            % Detect bad channel-trials using MAD
            bad_mask = false(n_trials, n_channels);
            for ch = 1:n_channels
                chan_power = trial_power(:, ch);
                med = median(chan_power, 'omitnan');
                mad = median(abs(chan_power - med), 'omitnan');
                if mad > 0
                    robust_z = abs(chan_power - med) / (1.4826 * mad);
                    bad_mask(:, ch) = robust_z > config.artifact.mad_threshold;
                end
            end

            % Apply handling strategy
            cleaned_trials = trials;
            keep_mask = true(n_trials, 1);

            switch config.artifact.handling
                case 'reject_trial'
                    % Reject entire trial if any channel is bad
                    keep_mask = ~any(bad_mask, 2);
                    cleaned_trials = trials(keep_mask, :, :, :);
                    n_rejected = n_rejected + sum(~keep_mask);

                case 'reject_channel'
                    % Mark bad channels as NaN
                    for t = 1:n_trials
                        for ch = 1:n_channels
                            if bad_mask(t, ch)
                                cleaned_trials(t, ch, :, :) = NaN;
                            end
                        end
                    end

                case 'interpolate_channel'
                    % Interpolate bad channels
                    for t = 1:n_trials
                        bad_chans = find(bad_mask(t, :));
                        if ~isempty(bad_chans)
                            good_chans = find(~bad_mask(t, :));
                            if ~isempty(good_chans)
                                good_data = cleaned_trials(t, good_chans, :, :);
                                for ch = bad_chans
                                    cleaned_trials(t, ch, :, :) = mean(good_data, 2, 'omitnan');
                                end
                            end
                        end
                    end
            end

            % Store cleaned data
            if any(keep_mask)
                all_data_filtered.(participant).(condition).trials = cleaned_trials;
                all_data_filtered.(participant).(condition).channels = all_data.(participant).(condition).channels;
                all_data_filtered.(participant).(condition).freq = all_data.(participant).(condition).freq;
                all_data_filtered.(participant).(condition).time = all_data.(participant).(condition).time;

                % Update trial indices
                if isfield(trial_indices.(participant).(condition), 'kept')
                    trial_indices.(participant).(condition).kept = trial_indices.(participant).(condition).kept(keep_mask);
                else
                    trial_indices.(participant).(condition).kept = trial_indices.(participant).(condition).trial_num(keep_mask);
                end

                % Preserve passing_electrodes information if it exists
                if isfield(trial_indices.(participant).(condition), 'passing_electrodes')
                    old_passing_electrodes = trial_indices.(participant).(condition).passing_electrodes;
                    kept_trial_nums = trial_indices.(participant).(condition).kept;
                    new_passing_electrodes = struct();

                    for t = 1:length(kept_trial_nums)
                        trial_num = kept_trial_nums(t);
                        field_name = sprintf('trial_%d', trial_num);
                        if isfield(old_passing_electrodes, field_name)
                            new_passing_electrodes.(field_name) = old_passing_electrodes.(field_name);
                        end
                    end

                    trial_indices.(participant).(condition).passing_electrodes = new_passing_electrodes;
                end
            else
                % Clear trials when none pass the artifact filter
                trial_indices.(participant).(condition).kept = [];
            end
        end
    end

    fprintf('  Rejected %d/%d trials (%.1f%%)\n', n_rejected, n_total, 100*n_rejected/n_total);
end


function all_data_filtered = apply_log_transform(all_data, participants, conditions)
    % Transform power to dB scale: 10*log10(power)

    fprintf('  Transforming to dB scale: 10*log10(power)\n');

    all_data_filtered = all_data;

    for p = 1:length(participants)
        participant = participants{p};
        if ~isfield(all_data, participant), continue; end

        for c = 1:length(conditions)
            condition = conditions{c};
            if ~isfield(all_data.(participant), condition), continue; end

            trials = all_data.(participant).(condition).trials;
            trials(trials <= 0) = eps;
            all_data_filtered.(participant).(condition).trials = 10 * log10(trials);
        end
    end
end


function [all_data_filtered, trial_indices] = filter_power(...
    all_data, trial_indices, participants, conditions, config)
    % Filter trials by spindle power presence
    % Supports two modes via config.electrode_filtering_mode:
    %   'trial_level': If min_channels pass, keep entire trial (all electrodes)
    %   'electrode_level': If any electrode passes, keep trial but only passing electrodes (others set to NaN)

    % Get minimum channels required (default to 1 for backward compatibility)
    if isfield(config.power_filter.params, 'min_channels')
        min_channels_required = config.power_filter.params.min_channels;
    else
        min_channels_required = 1;
    end

    % Get electrode filtering mode (default to 'trial_level' for backward compatibility)
    if isfield(config, 'electrode_filtering_mode')
        electrode_mode = config.electrode_filtering_mode;
    else
        electrode_mode = 'trial_level';
    end

    fprintf('  Applying power filter criterion\n');
    fprintf('  Electrode filtering mode: %s\n', electrode_mode);
    if strcmp(electrode_mode, 'trial_level')
        fprintf('  Minimum channels required: %d\n', min_channels_required);
    else
        fprintf('  Keeping only electrodes that pass criterion (no minimum)\n');
    end

    all_data_filtered = struct();
    n_total = 0;
    n_kept = 0;

    for p = 1:length(participants)
        participant = participants{p};
        if ~isfield(all_data, participant), continue; end

        for c = 1:length(conditions)
            condition = conditions{c};
            if ~isfield(all_data.(participant), condition), continue; end

            trials = all_data.(participant).(condition).trials;
            channels = all_data.(participant).(condition).channels;
            freq_axis = all_data.(participant).(condition).freq;
            time_axis = all_data.(participant).(condition).time;
            [n_trials, n_channels, ~, ~] = size(trials);
            n_total = n_total + n_trials;

            % Check each trial and track which electrodes pass
            keep_mask = false(n_trials, 1);
            electrode_pass_mask = false(n_trials, n_channels);  % Track which electrodes pass per trial

            for t = 1:n_trials
                % Check each channel
                for ch = 1:n_channels
                    chan_data = squeeze(trials(t, ch, :, :));
                    if all(isnan(chan_data(:)))
                        continue;
                    end

                    if check_power_criterion(chan_data, freq_axis, time_axis, config.power_filter.params)
                        electrode_pass_mask(t, ch) = true;
                    end
                end

                % Determine if trial should be kept based on mode
                channels_passing = sum(electrode_pass_mask(t, :));
                if strcmp(electrode_mode, 'trial_level')
                    % Keep trial if minimum number of channels pass
                    if channels_passing >= min_channels_required
                        keep_mask(t) = true;
                    end
                else  % 'electrode_level'
                    % Keep trial if at least one electrode passes
                    if channels_passing >= 1
                        keep_mask(t) = true;
                    end
                end
            end

            % Apply filtering based on mode
            if any(keep_mask)
                filtered_trials = trials(keep_mask, :, :, :);

                % For electrode_level mode, set non-passing electrodes to NaN
                if strcmp(electrode_mode, 'electrode_level')
                    kept_electrode_mask = electrode_pass_mask(keep_mask, :);
                    for t = 1:size(filtered_trials, 1)
                        for ch = 1:n_channels
                            if ~kept_electrode_mask(t, ch)
                                filtered_trials(t, ch, :, :) = NaN;
                            end
                        end
                    end
                end

                all_data_filtered.(participant).(condition).trials = filtered_trials;
                all_data_filtered.(participant).(condition).channels = channels;
                all_data_filtered.(participant).(condition).freq = freq_axis;
                all_data_filtered.(participant).(condition).time = time_axis;

                % Update trial indices
                if isfield(trial_indices.(participant).(condition), 'kept')
                    kept_trial_nums = trial_indices.(participant).(condition).kept(keep_mask);
                else
                    kept_trial_nums = trial_indices.(participant).(condition).trial_num(keep_mask);
                end
                trial_indices.(participant).(condition).kept = kept_trial_nums;

                % Store electrode-level information
                trial_indices.(participant).(condition).passing_electrodes = struct();
                kept_electrode_mask = electrode_pass_mask(keep_mask, :);
                for t = 1:length(kept_trial_nums)
                    trial_num = kept_trial_nums(t);
                    passing_ch_idx = find(kept_electrode_mask(t, :));
                    passing_ch_names = channels(passing_ch_idx);
                    trial_indices.(participant).(condition).passing_electrodes.(sprintf('trial_%d', trial_num)) = passing_ch_names;
                end

                n_kept = n_kept + sum(keep_mask);
            else
                % Clear trials when none pass the power filter
                trial_indices.(participant).(condition).kept = [];
            end
        end
    end

    fprintf('  Kept %d/%d trials (%.1f%%)\n', n_kept, n_total, 100*n_kept/n_total);
end


function all_data_summarized = summarize_trials(all_data, participants, conditions, config)
    % Summarize trials using trimmed mean, median, or mean
    % This stores the summarization method in the data structure for later use

    all_data_summarized = all_data;

    for p = 1:length(participants)
        participant = participants{p};
        if ~isfield(all_data, participant), continue; end

        for c = 1:length(conditions)
            condition = conditions{c};
            if ~isfield(all_data.(participant), condition), continue; end

            all_data_summarized.(participant).(condition).summary_method = config.summary.method;
            all_data_summarized.(participant).(condition).trim_percent = config.summary.trimmed_mean_percent;
        end
    end
end


function sleep_stage_intervals = load_sleep_stage_intervals(config)
    % Load sleep stage hypnogram data and check if trial windows are in requested stages
    % Returns a structure with trial numbers where the TRIAL TIME PERIOD is in the requested stage
    %
    % CORRECTED VERSION: Uses sampleinfo from ANALYSIS.mat files to accurately map
    % trial numbers to their actual time frames in the continuous recording.
    %
    % IMPORTANT: This does NOT filter for spindles! It checks if the trial time window
    % itself overlaps with the requested sleep stage periods in the hypnogram.
    %
    % CACHING: This function checks for a cached version of sleep stage classifications.
    % If the cache exists, it loads and filters it. If not, it computes from scratch and saves.

    repo_root = fileparts(fileparts(fileparts(mfilename('fullpath'))));  % portable repo root
    comprehensive_file = fullfile(repo_root, '1_eventDetection', 'eventDetectionResults', 'comprehensive_analysis.mat');
    analysis_dir = fullfile(repo_root, 'data', 'analysis');  % in-repo, gitignored (see README "Data Availability")

    if isfield(config, 'paths') && isfield(config.paths, 'comprehensive_analysis')
        comprehensive_file = config.paths.comprehensive_analysis;
    end
    if isfield(config, 'base_path')
        analysis_dir = config.base_path;
    end

    % Define cache file path (same directory as comprehensive_analysis)
    [cache_dir, ~, ~] = fileparts(comprehensive_file);
    cache_file = fullfile(cache_dir, 'sleep_stage_trial_cache.mat');

    % Check if cache exists
    if exist(cache_file, 'file')
        fprintf('  Found cached sleep stage classifications: %s\n', cache_file);
        fprintf('  Loading from cache...\n');

        try
            loaded = load(cache_file, 'sleep_stage_cache');
            sleep_stage_cache = loaded.sleep_stage_cache;

            % Filter cached data for requested stages and participants/conditions
            sleep_stage_intervals = filter_cached_sleep_stages(sleep_stage_cache, config);
            fprintf('  Successfully loaded from cache.\n');
            return;
        catch ME
            warning('spindlePilot:cacheLoadFailed', 'Failed to load cache file. Will recompute. Error: %s', ME.message);
        end
    else
        fprintf('  No cache file found. Will compute sleep stage classifications.\n');
    end

    % If we get here, either no cache exists or loading failed
    % Compute sleep stage classifications from scratch
    sleep_stage_intervals = struct();

    if ~exist(comprehensive_file, 'file')
        warning('Comprehensive analysis file not found: %s', comprehensive_file);
        return;
    end

    % Get the analysis window from config (e.g., [0.25, 1.75])
    if isfield(config, 'time_range') && ~isempty(config.time_range)
        analysis_window = config.time_range;
    else
        warning('config.time_range not found - using full trial');
        analysis_window = [];
    end

    try
        % Load sleep stage hypnogram
        loaded_stages = load(comprehensive_file, 'all_sleep_stages');
        if ~isfield(loaded_stages, 'all_sleep_stages')
            warning('all_sleep_stages not found in comprehensive analysis file');
            return;
        end

        all_sleep_stages = loaded_stages.all_sleep_stages;
        requested_stages = config.sleep_stage_filter.stages;

        fprintf('  Computing sleep stage classifications for all trials...\n');
        if ~isempty(analysis_window)
            fprintf('  Analysis window: %.2f - %.2f s (relative to trial onset)\n', analysis_window(1), analysis_window(2));
        end
        fprintf('  Using sampleinfo from ANALYSIS.mat to map trial numbers to time frames\n');

        % Structure to store complete sleep stage classification for ALL trials
        sleep_stage_cache = struct();
        sleep_stage_cache.analysis_window = analysis_window;
        sleep_stage_cache.participants = config.participants;
        sleep_stage_cache.conditions = config.conditions;
        sleep_stage_cache.session = config.session;
        sleep_stage_cache.computed_date = datestr(now);

        % Process each participant
        for p = 1:length(config.participants)
            participant = config.participants{p};

            % Load the ANALYSIS.mat file for this participant
            analysis_file = fullfile(analysis_dir, sprintf('%s_%s_ANALYSIS.mat', participant, config.session));

            if ~exist(analysis_file, 'file')
                warning('ANALYSIS file not found for %s: %s', participant, analysis_file);
                continue;
            end

            fprintf('  Processing %s...\n', participant);
            loaded_data = load(analysis_file, 'analysisData_saved');

            if ~isfield(loaded_data, 'analysisData_saved') || ...
               ~isfield(loaded_data.analysisData_saved, participant) || ...
               ~isfield(loaded_data.analysisData_saved.(participant), config.session)
                warning('Expected data structure not found in %s', analysis_file);
                continue;
            end

            participant_data = loaded_data.analysisData_saved.(participant).(config.session);

            % Get continuous EEG info for time conversion
            if ~isfield(participant_data, 'eeg')
                warning('EEG data not found for %s', participant);
                continue;
            end

            continuous_eeg = participant_data.eeg;
            fs = continuous_eeg.fsample;  % Sampling rate
            recording_start_sample = continuous_eeg.sampleinfo(1);  % First sample of recording

            % Get sleep stages for this participant
            subject_stages = all_sleep_stages(strcmp(all_sleep_stages.Subject, participant), :);

            if isempty(subject_stages)
                warning('No sleep stage data found for %s', participant);
                continue;
            end

            % Convert sleep stage timestamps to seconds (relative to first timestamp)
            if isdatetime(subject_stages.Timestamp)
                stage_times_sec = seconds(subject_stages.Timestamp - subject_stages.Timestamp(1));
            else
                stage_times_sec = subject_stages.Timestamp;
            end

            % Process each condition
            if ~isfield(participant_data, 'epochedData')
                warning('No epochedData found for %s', participant);
                continue;
            end

            epoched_data = participant_data.epochedData;

            for c = 1:length(config.conditions)
                condition = config.conditions{c};

                if ~isfield(epoched_data, condition)
                    continue;
                end

                cond_data = epoched_data.(condition);

                if ~isfield(cond_data, 'sampleinfo') || isempty(cond_data.trial)
                    continue;
                end

                n_trials = size(cond_data.sampleinfo, 1);

                % Initialize cache storage for this participant/condition
                if ~isfield(sleep_stage_cache, participant)
                    sleep_stage_cache.(participant) = struct();
                end
                sleep_stage_cache.(participant).(condition) = struct();
                sleep_stage_cache.(participant).(condition).trial_stages = cell(n_trials, 1);

                % Check each trial and store ALL sleep stage information
                valid_trials = [];
                for t = 1:n_trials
                    % Get the sample range for this trial in the continuous recording
                    trial_start_sample = cond_data.sampleinfo(t, 1);
                    trial_end_sample = cond_data.sampleinfo(t, 2);

                    % Convert to time (seconds from start of recording)
                    trial_start_time = (trial_start_sample - recording_start_sample) / fs;
                    trial_end_time = (trial_end_sample - recording_start_sample) / fs;

                    % Calculate the time range to check based on analysis window
                    if ~isempty(analysis_window)
                        % Check the analysis window relative to trial start
                        check_start_time = trial_start_time + analysis_window(1);
                        check_end_time = trial_start_time + analysis_window(2);
                    else
                        % Check the full trial
                        check_start_time = trial_start_time;
                        check_end_time = trial_end_time;
                    end

                    % Find ALL overlapping sleep stages for this trial
                    trial_sleep_stages = {};
                    for s = 1:height(subject_stages)
                        stage = subject_stages.Stage{s};
                        epoch_start = stage_times_sec(s);

                        % Determine epoch end (next timestamp or assume 30s epoch)
                        if s < height(subject_stages)
                            epoch_end = stage_times_sec(s+1);
                        else
                            epoch_end = epoch_start + 30; % Assume 30s epoch for last entry
                        end

                        % Check if this epoch overlaps with our check window
                        % Overlap condition: epoch_end > check_start AND epoch_start < check_end
                        overlaps = (epoch_end > check_start_time) && (epoch_start < check_end_time);

                        if overlaps && ~ismember(stage, trial_sleep_stages)
                            trial_sleep_stages{end+1} = stage; %#ok<AGROW>
                        end
                    end

                    % Store the sleep stages for this trial in the cache
                    sleep_stage_cache.(participant).(condition).trial_stages{t} = trial_sleep_stages;

                    % Check if this trial matches the requested stages
                    has_requested_stage = any(ismember(trial_sleep_stages, requested_stages));
                    if has_requested_stage
                        valid_trials = [valid_trials; t]; %#ok<AGROW>
                    end
                end

                % Store valid trial numbers for this participant/condition
                if ~isempty(valid_trials)
                    if ~isfield(sleep_stage_intervals, participant)
                        sleep_stage_intervals.(participant) = struct();
                    end
                    sleep_stage_intervals.(participant).(condition) = valid_trials;
                    fprintf('    %s %s: %d/%d trials in %s\n', participant, condition, ...
                        length(valid_trials), n_trials, strjoin(requested_stages, '/'));
                end
            end
        end

        % Save the cache for future use
        fprintf('  Saving sleep stage classifications to cache: %s\n', cache_file);
        try
            save(cache_file, 'sleep_stage_cache', '-v7.3');
            fprintf('  Cache saved successfully.\n');
        catch ME
            warning('spindlePilot:cacheSaveFailed', 'Failed to save cache file: %s', ME.message);
        end

    catch ME
        warning('Error loading sleep stage data: %s', getReport(ME, 'basic'));
        fprintf('%s\n', getReport(ME));
    end
end


function sleep_stage_intervals = filter_cached_sleep_stages(sleep_stage_cache, config)
    % Filter cached sleep stage data for requested stages and participants/conditions
    %
    % INPUTS:
    %   sleep_stage_cache - cached structure with sleep stage info for all trials
    %   config - configuration with requested stages, participants, conditions
    %
    % OUTPUTS:
    %   sleep_stage_intervals - structure with trial numbers matching requested stages

    sleep_stage_intervals = struct();
    requested_stages = config.sleep_stage_filter.stages;

    fprintf('  Filtering cached data for sleep stages: %s\n', strjoin(requested_stages, ', '));

    % Process each participant
    for p = 1:length(config.participants)
        participant = config.participants{p};

        if ~isfield(sleep_stage_cache, participant)
            continue;
        end

        % Process each condition
        for c = 1:length(config.conditions)
            condition = config.conditions{c};

            if ~isfield(sleep_stage_cache.(participant), condition)
                continue;
            end

            trial_stages = sleep_stage_cache.(participant).(condition).trial_stages;
            n_trials = length(trial_stages);

            % Find trials that match requested stages
            valid_trials = [];
            for t = 1:n_trials
                stages_for_trial = trial_stages{t};
                if any(ismember(stages_for_trial, requested_stages))
                    valid_trials = [valid_trials; t]; %#ok<AGROW>
                end
            end

            % Store valid trial numbers
            if ~isempty(valid_trials)
                if ~isfield(sleep_stage_intervals, participant)
                    sleep_stage_intervals.(participant) = struct();
                end
                sleep_stage_intervals.(participant).(condition) = valid_trials;
                fprintf('    %s %s: %d/%d trials in %s\n', participant, condition, ...
                    length(valid_trials), n_trials, strjoin(requested_stages, '/'));
            end
        end
    end
end


function passes = check_power_criterion(data_slice, freq_axis, time_axis, power_params)
    % Check power criterion for trial inclusion
    % Supports two methods:
    %   1. 'spike_vs_rest': Compare peak power to baseline (original method)
    %   2. 'band_ratio': Compare spindle band to reference band across time

    % Default method
    if ~isfield(power_params, 'method')
        power_params.method = 'spike_vs_rest';
    end

    switch lower(power_params.method)
        case 'spike_vs_rest'
            passes = check_spike_vs_rest(data_slice, freq_axis, time_axis, power_params);
        case 'band_ratio'
            passes = check_band_ratio(data_slice, freq_axis, time_axis, power_params);
        otherwise
            error('Unknown power filter method: %s', power_params.method);
    end
end


function passes = check_spike_vs_rest(data_slice, freq_axis, time_axis, power_params)
    % Original spike-vs-rest criterion for power inclusion

    if ~isfield(power_params, 'spike_len_sec'), power_params.spike_len_sec = 0.3; end
    if ~isfield(power_params, 'spike_vs_rest_ratio'), power_params.spike_vs_rest_ratio = 3.0; end
    if ~isfield(power_params, 'guard_sec'), power_params.guard_sec = 0; end

    % Frequency selection
    fidx = freq_axis >= power_params.freq_range(1) & freq_axis <= power_params.freq_range(2);
    if ~any(fidx)
        passes = false;
        return;
    end

    % Band-averaged time course
    tc = mean(data_slice(fidx, :), 1, 'omitnan');

    % Spike search window
    sidx = time_axis >= power_params.time_window(1) & time_axis <= power_params.time_window(2);
    if ~any(sidx)
        passes = false;
        return;
    end

    tc_search = tc(sidx);
    t_search = time_axis(sidx);

    % Sliding window
    dt = mean(diff(time_axis));
    winSamp = max(1, round(power_params.spike_len_sec / dt));

    if numel(tc_search) < winSamp
        passes = false;
        return;
    end

    w = movmean(tc_search, winSamp, 'omitnan');
    [spikePower, spikeCenterIdx] = max(w);
    spikeCenterTime = t_search(spikeCenterIdx);

    % Define exclusion window
    half = power_params.spike_len_sec / 2;
    exclStart = spikeCenterTime - half - power_params.guard_sec;
    exclEnd = spikeCenterTime + half + power_params.guard_sec;

    % Rest of trial mean
    restMask = ~(time_axis >= exclStart & time_axis <= exclEnd);
    restData = tc(restMask);

    if isempty(restData) || all(isnan(restData))
        passes = false;
        return;
    end

    restMean = mean(restData, 'omitnan');

    if ~isfinite(restMean) || restMean <= 0
        passes = false;
        return;
    end

    passes = spikePower >= power_params.spike_vs_rest_ratio * restMean;
end


function passes = check_band_ratio(data_slice, freq_axis, time_axis, power_params)
    % Band ratio criterion: Compare spindle band to reference band across time
    %
    % Parameters:
    %   spindle_band: [low, high] Hz for spindle band (e.g., [12, 16])
    %   reference_band: [low, high] Hz for reference band (e.g., [6, 9])
    %   min_ratio: Minimum ratio of spindle/reference power (e.g., 1.5)
    %   min_time_percent: Minimum percentage of time ratio must exceed threshold (e.g., 20)
    %   time_window: [start, end] time window to analyze (e.g., [0.25, 1.75])

    % Set defaults
    if ~isfield(power_params, 'spindle_band'), power_params.spindle_band = [12, 16]; end
    if ~isfield(power_params, 'reference_band'), power_params.reference_band = [6, 9]; end
    if ~isfield(power_params, 'min_ratio'), power_params.min_ratio = 1.5; end
    if ~isfield(power_params, 'min_time_percent'), power_params.min_time_percent = 20; end
    if ~isfield(power_params, 'time_window'), power_params.time_window = [0.25, 1.75]; end

    % Select time window
    time_idx = time_axis >= power_params.time_window(1) & time_axis <= power_params.time_window(2);
    if ~any(time_idx)
        passes = false;
        return;
    end

    % Select spindle band frequencies
    spindle_idx = freq_axis >= power_params.spindle_band(1) & freq_axis <= power_params.spindle_band(2);
    if ~any(spindle_idx)
        passes = false;
        return;
    end

    % Select reference band frequencies
    reference_idx = freq_axis >= power_params.reference_band(1) & freq_axis <= power_params.reference_band(2);
    if ~any(reference_idx)
        passes = false;
        return;
    end

    % Extract data for selected time window
    data_window = data_slice(:, time_idx);

    % Calculate average power across frequency bands at each time point
    spindle_power = mean(data_window(spindle_idx, :), 1, 'omitnan');
    reference_power = mean(data_window(reference_idx, :), 1, 'omitnan');

    % Check for valid data
    if all(isnan(spindle_power)) || all(isnan(reference_power))
        passes = false;
        return;
    end

    % Calculate ratio at each time point (avoid division by zero)
    valid_mask = reference_power > 0 & isfinite(spindle_power) & isfinite(reference_power);
    if ~any(valid_mask)
        passes = false;
        return;
    end

    ratio = zeros(size(spindle_power));
    ratio(valid_mask) = spindle_power(valid_mask) ./ reference_power(valid_mask);
    ratio(~valid_mask) = 0;

    % Calculate percentage of time points where ratio exceeds threshold
    exceeds_threshold = ratio >= power_params.min_ratio;
    percent_exceeding = 100 * sum(exceeds_threshold) / sum(valid_mask);

    % Pass if percentage exceeds the minimum required
    passes = percent_exceeding >= power_params.min_time_percent;
end


function [all_data_filtered, trial_indices] = filter_zscore_spindle_power(...
    all_data, trial_indices, participants, conditions, config)
    % Filter trials based on z-scored spindle power
    %
    % This filter:
    % 1. Averages spindle band power in a defined time window
    % 2. Does this per electrode, per trial, per subject
    % 3. Z-scores across trials within electrode within subject
    % 4. Supports two modes via config.electrode_filtering_mode:
    %    'trial_level': Keeps trials that exceed z-threshold in at least min_channels
    %    'electrode_level': Keeps trials with any passing electrode, but only keeps passing electrodes
    %
    % Parameters (in config.zscore_spindle_power):
    %   spindle_band: [low, high] Hz for spindle band (e.g., [12, 16])
    %   time_window: [start, end] time window to average (e.g., [-2, 4])
    %   z_threshold: Z-score threshold for keeping trials (e.g., 2)
    %   min_channels: Minimum number of channels that must exceed threshold (default: 1, trial_level mode only)

    params = config.zscore_spindle_power;

    % Set defaults
    if ~isfield(params, 'spindle_band'), params.spindle_band = [12, 16]; end
    if ~isfield(params, 'time_window'), params.time_window = [-2, 4]; end
    if ~isfield(params, 'z_threshold'), params.z_threshold = 2; end
    if ~isfield(params, 'min_channels'), params.min_channels = 1; end

    % Get electrode filtering mode (default to 'trial_level' for backward compatibility)
    if isfield(config, 'electrode_filtering_mode')
        electrode_mode = config.electrode_filtering_mode;
    else
        electrode_mode = 'trial_level';
    end

    fprintf('  Spindle band: %.1f-%.1f Hz\n', params.spindle_band(1), params.spindle_band(2));
    fprintf('  Time window: %.2f-%.2f s\n', params.time_window(1), params.time_window(2));
    fprintf('  Z-score threshold: %.1f\n', params.z_threshold);
    fprintf('  Electrode filtering mode: %s\n', electrode_mode);
    if strcmp(electrode_mode, 'trial_level')
        fprintf('  Minimum channels required: %d\n', params.min_channels);
    else
        fprintf('  Keeping only electrodes that exceed threshold (no minimum)\n');
    end

    all_data_filtered = struct();
    n_total = 0;
    n_kept = 0;

    % Process each participant separately
    for p = 1:length(participants)
        participant = participants{p};
        if ~isfield(all_data, participant), continue; end

        % Process each condition separately
        for c = 1:length(conditions)
            condition = conditions{c};
            if ~isfield(all_data.(participant), condition), continue; end

            trials = all_data.(participant).(condition).trials;
            channels = all_data.(participant).(condition).channels;
            freq_axis = all_data.(participant).(condition).freq;
            time_axis = all_data.(participant).(condition).time;

            [n_trials, n_channels, ~, ~] = size(trials);
            n_total = n_total + n_trials;

            % Select frequency indices for spindle band
            freq_idx = freq_axis >= params.spindle_band(1) & freq_axis <= params.spindle_band(2);
            if ~any(freq_idx)
                warning('No frequencies found in spindle band [%.1f-%.1f Hz] for %s %s', ...
                    params.spindle_band(1), params.spindle_band(2), participant, condition);
                continue;
            end

            % Select time indices for averaging window
            time_idx = time_axis >= params.time_window(1) & time_axis <= params.time_window(2);
            if ~any(time_idx)
                warning('No time points found in window [%.2f-%.2f s] for %s %s', ...
                    params.time_window(1), params.time_window(2), participant, condition);
                continue;
            end

            % Warn if requested window extends beyond loaded data
            actual_time_min = min(time_axis(time_idx));
            actual_time_max = max(time_axis(time_idx));
            time_resolution = mean(diff(time_axis));
            tolerance = time_resolution * 1.5;  % Allow for sampling resolution + some margin

            % Check if requested window is significantly outside loaded range
            extends_before = params.time_window(1) < (min(time_axis) - tolerance);
            extends_after = params.time_window(2) > (max(time_axis) + tolerance);

            if extends_before || extends_after
                warning('Requested time window [%.2f, %.2f] s extends beyond loaded data [%.2f, %.2f] s for %s %s.\nUsing available range [%.2f, %.2f] s. Consider setting config.load_time_range to include desired window.', ...
                    params.time_window(1), params.time_window(2), ...
                    min(time_axis), max(time_axis), ...
                    participant, condition, ...
                    actual_time_min, actual_time_max);
            end

            % Compute average spindle power per trial per channel
            % Shape: [n_trials x n_channels]
            trial_power = zeros(n_trials, n_channels);
            for t = 1:n_trials
                for ch = 1:n_channels
                    % Extract data for this trial, channel, in spindle band and time window
                    data_slice = squeeze(trials(t, ch, freq_idx, time_idx));
                    % Average across frequency and time
                    trial_power(t, ch) = mean(data_slice(:), 'omitnan');
                end
            end

            % Z-score per channel across trials
            % Shape: [n_trials x n_channels]
            z_scores = zeros(n_trials, n_channels);
            for ch = 1:n_channels
                channel_power = trial_power(:, ch);
                % Only compute z-score if we have valid data
                if ~all(isnan(channel_power))
                    mu = mean(channel_power, 'omitnan');
                    sigma = std(channel_power, 'omitnan');
                    if sigma > 0
                        z_scores(:, ch) = (channel_power - mu) / sigma;
                    else
                        z_scores(:, ch) = 0;  % If no variance, set z-scores to 0
                    end
                else
                    z_scores(:, ch) = NaN;
                end
            end

            % For each trial, determine which electrodes pass and if trial should be kept
            keep_mask = false(n_trials, 1);
            electrode_pass_mask = false(n_trials, n_channels);  % Track which electrodes pass per trial

            for t = 1:n_trials
                % Identify electrodes that exceed threshold
                electrode_pass_mask(t, :) = z_scores(t, :) > params.z_threshold;
                channels_exceeding = sum(electrode_pass_mask(t, :), 'omitnan');

                % Determine if trial should be kept based on mode
                if strcmp(electrode_mode, 'trial_level')
                    % Keep trial if minimum number of channels exceed threshold
                    if channels_exceeding >= params.min_channels
                        keep_mask(t) = true;
                    end
                else  % 'electrode_level'
                    % Keep trial if at least one electrode exceeds threshold
                    if channels_exceeding >= 1
                        keep_mask(t) = true;
                    end
                end
            end

            % Apply filtering based on mode
            if any(keep_mask)
                filtered_trials = trials(keep_mask, :, :, :);

                % For electrode_level mode, set non-passing electrodes to NaN
                if strcmp(electrode_mode, 'electrode_level')
                    kept_electrode_mask = electrode_pass_mask(keep_mask, :);
                    for t = 1:size(filtered_trials, 1)
                        for ch = 1:n_channels
                            if ~kept_electrode_mask(t, ch)
                                filtered_trials(t, ch, :, :) = NaN;
                            end
                        end
                    end
                end

                all_data_filtered.(participant).(condition).trials = filtered_trials;
                all_data_filtered.(participant).(condition).channels = channels;
                all_data_filtered.(participant).(condition).freq = freq_axis;
                all_data_filtered.(participant).(condition).time = time_axis;

                % Update trial indices
                if isfield(trial_indices.(participant).(condition), 'kept')
                    kept_trial_nums = trial_indices.(participant).(condition).kept(keep_mask);
                else
                    kept_trial_nums = trial_indices.(participant).(condition).trial_num(keep_mask);
                end
                trial_indices.(participant).(condition).kept = kept_trial_nums;

                % Store electrode-level information
                trial_indices.(participant).(condition).passing_electrodes = struct();
                kept_electrode_mask = electrode_pass_mask(keep_mask, :);
                for t = 1:length(kept_trial_nums)
                    trial_num = kept_trial_nums(t);
                    passing_ch_idx = kept_electrode_mask(t, :);
                    passing_ch_names = channels(passing_ch_idx);
                    trial_indices.(participant).(condition).passing_electrodes.(sprintf('trial_%d', trial_num)) = passing_ch_names;
                end

                n_kept = n_kept + sum(keep_mask);

                fprintf('    %s %s: kept %d/%d trials (%.1f%%)\n', ...
                    participant, condition, sum(keep_mask), n_trials, 100*sum(keep_mask)/n_trials);
            else
                % Clear trials when none pass the zscore filter
                trial_indices.(participant).(condition).kept = [];
                fprintf('    %s %s: kept 0/%d trials (0.0%%)\n', participant, condition, n_trials);
            end
        end
    end

    fprintf('  Total kept %d/%d trials (%.1f%%)\n', n_kept, n_total, 100*n_kept/max(n_total,1));
end

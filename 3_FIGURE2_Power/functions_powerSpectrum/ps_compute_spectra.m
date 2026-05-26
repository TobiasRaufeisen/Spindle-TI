function [spectra_data, freq, subjects_used, channels_computed] = ps_compute_spectra( ...
        cfg, participants, analysis_data_path)
%PS_COMPUTE_SPECTRA Compute per-subject, per-channel Welch power spectra.
%
%   [spectra_data, freq, subjects_used, channels_computed] = ps_compute_spectra(cfg, participants, analysis_data_path)
%
%   Loads epoched EEG data for each participant, filters trials by sleep
%   stage, and computes Welch PSD per channel. Results are optionally cached.
%
%   Inputs:
%     cfg                - struct with fields: session, conditions_to_compare,
%                          channels_to_compute, sleep_stages_filter, time_range,
%                          comprehensive_path, USE_CACHE, CACHE_DIR
%     participants       - cell array of participant IDs
%     analysis_data_path - path to folder containing *_ANALYSIS.mat files
%
%   Outputs:
%     spectra_data       - struct with per-condition, per-subject spectra (dB)
%     freq               - frequency vector (Hz)
%     subjects_used      - cell array of participants that contributed data
%     channels_computed  - cell array of channel labels

    %% Check cache
    cache_file = fullfile(cfg.CACHE_DIR, 'cache_powerSpectrum.mat');
    if cfg.USE_CACHE && exist(cache_file, 'file')
        fprintf('Cache file found: %s\n', cache_file);
        cache = load(cache_file);
        if isequal(cache.cache_params.participants, participants) && ...
           isequal(cache.cache_params.session, cfg.session) && ...
           isequal(cache.cache_params.conditions_to_compare, cfg.conditions_to_compare) && ...
           isequal(cache.cache_params.channels_to_compute, cfg.channels_to_compute) && ...
           isequal(cache.cache_params.sleep_stages_filter, cfg.sleep_stages_filter) && ...
           isequal(cache.cache_params.time_range, cfg.time_range)
            spectra_data       = cache.spectra_data;
            freq               = cache.freq;
            subjects_used      = cache.subjects_used;
            channels_computed  = cache.channels_computed;
            fprintf('Cache valid — skipping computation (%d channels, %d subjects).\n', ...
                    length(channels_computed), length(subjects_used));
            return;
        else
            fprintf('Cache parameters changed — recomputing.\n');
        end
    end

    %% Load sleep stage data
    all_sleep_stages_full = [];
    if exist(cfg.comprehensive_path, 'file')
        fprintf('Loading sleep stage data from: %s\n', cfg.comprehensive_path);
        tmp = load(cfg.comprehensive_path, 'all_sleep_stages');
        all_sleep_stages_full = tmp.all_sleep_stages;
        fprintf('Loaded all_sleep_stages table (%d records)\n', height(all_sleep_stages_full));
    else
        warning('Comprehensive analysis file not found. Sleep stage filtering will be skipped.');
    end

    %% Initialise storage
    conditions = cfg.conditions_to_compare;
    spectra_data = struct();
    for c = 1:length(conditions)
        spectra_data.(conditions{c}).per_subject_channel_db = {};
        spectra_data.(conditions{c}).subject_labels = {};
    end
    freq = [];
    subjects_used = {};
    channels_computed = {};

    % Welch parameters (set on first subject)
    fs_set = false;
    window_length = []; overlap = []; nfft = [];

    %% Loop over subjects
    n_participants = length(participants);
    for s = 1:n_participants
        participant = participants{s};
        fprintf('\n========== Subject %d/%d: %s ==========\n', s, n_participants, participant);

        % Load epoched data
        analysis_file = fullfile(analysis_data_path, ...
            sprintf('%s_%s_ANALYSIS.mat', participant, cfg.session));
        if ~exist(analysis_file, 'file')
            warning('Analysis file not found for %s. Skipping.', participant);
            continue;
        end

        tmp = load(analysis_file, 'analysisData_saved');
        analysisData_saved = tmp.analysisData_saved;
        if ~isfield(analysisData_saved, participant) || ...
           ~isfield(analysisData_saved.(participant), cfg.session)
            warning('Data not found for %s %s. Skipping.', participant, cfg.session);
            continue;
        end

        participant_data = analysisData_saved.(participant).(cfg.session);
        clear analysisData_saved tmp;

        if ~isfield(participant_data, 'epochedData')
            warning('No epoched data for %s. Skipping.', participant);
            continue;
        end

        % Sleep stages for this subject
        subj_sleep_stages = [];
        if ~isempty(all_sleep_stages_full)
            mask = strcmp(all_sleep_stages_full.Subject, participant);
            subj_sleep_stages = all_sleep_stages_full(mask, :);
            fprintf('Found %d sleep stage records for %s\n', height(subj_sleep_stages), participant);
        end

        % Resolve sampling rate and channels from first available condition
        if ~fs_set
            for c = 1:length(conditions)
                if isfield(participant_data.epochedData, conditions{c})
                    cond_tmp = participant_data.epochedData.(conditions{c});
                    fs = cond_tmp.fsample;

                    if isempty(channels_computed)
                        if ischar(cfg.channels_to_compute) && strcmpi(cfg.channels_to_compute, 'all')
                            channels_computed = cond_tmp.label(:)';
                        else
                            channels_computed = cfg.channels_to_compute;
                        end
                        fprintf('Channels to compute (%d): %s\n', ...
                                length(channels_computed), strjoin(channels_computed, ', '));
                    end
                    break;
                end
            end

            if ~isempty(cfg.time_range)
                segment_duration = cfg.time_range(2) - cfg.time_range(1);
                fprintf('Time range: [%.2f, %.2f] s (%.2f s per trial)\n', ...
                        cfg.time_range(1), cfg.time_range(2), segment_duration);
            else
                segment_duration = size(cond_tmp.trial{1}, 2) / fs;
            end
            window_length = round(min(1, segment_duration) * fs);
            overlap       = round(window_length / 2);
            nfft          = 2^nextpow2(window_length * 2);
            fs_set = true;
            fprintf('Sampling rate: %d Hz\n', fs);
            fprintf('Welch: window=%.2fs, overlap=%.2fs, nfft=%d\n', ...
                    window_length/fs, overlap/fs, nfft);
        end

        n_channels = length(channels_computed);
        subject_has_data = false;

        % Process each condition
        for c = 1:length(conditions)
            cond_name = conditions{c};
            if ~isfield(participant_data.epochedData, cond_name)
                warning('%s: Condition %s not found. Skipping.', participant, cond_name);
                continue;
            end

            cond_data = participant_data.epochedData.(cond_name);

            % Channel indices
            ch_indices = zeros(1, n_channels);
            for ch = 1:n_channels
                idx = find(strcmp(cond_data.label, channels_computed{ch}));
                if isempty(idx)
                    warning('%s %s: Channel %s not found.', participant, cond_name, channels_computed{ch});
                else
                    ch_indices(ch) = idx;
                end
            end

            % Filter trials by sleep stage
            valid_trials = get_valid_trials(cond_data, subj_sleep_stages, ...
                cfg.sleep_stages_filter, fs, participant, cond_name);

            if isempty(valid_trials)
                warning('%s %s: No valid trials. Skipping.', participant, cond_name);
                continue;
            end

            % Compute Welch PSD per trial and channel
            n_freqs_est = nfft/2 + 1;
            all_pxx = NaN(length(valid_trials), n_channels, n_freqs_est);

            for t = 1:length(valid_trials)
                trial_idx = valid_trials(t);
                for ch = 1:n_channels
                    if ch_indices(ch) == 0, continue; end
                    eeg = cond_data.trial{trial_idx}(ch_indices(ch), :);
                    if ~isempty(cfg.time_range)
                        t_vec = cond_data.time{trial_idx};
                        eeg = eeg(t_vec >= cfg.time_range(1) & t_vec <= cfg.time_range(2));
                    end
                    [pxx, freq] = pwelch(eeg, window_length, overlap, nfft, fs);
                    all_pxx(t, ch, :) = pxx(:)';
                end
            end

            % Average across trials -> dB per channel
            mean_pxx = squeeze(mean(all_pxx, 1, 'omitnan'));
            if n_channels == 1
                mean_pxx = mean_pxx(:)';
            end
            subj_mean_db = 10 * log10(mean_pxx);

            spectra_data.(cond_name).per_subject_channel_db{end+1} = subj_mean_db;
            spectra_data.(cond_name).subject_labels{end+1} = participant;
            subject_has_data = true;

            fprintf('  %s %s: %d trials, %d channels\n', ...
                    participant, cond_name, length(valid_trials), n_channels);
        end

        if subject_has_data
            subjects_used{end+1} = participant; %#ok<AGROW>
        end
    end

    %% Save cache
    if cfg.USE_CACHE
        if ~exist(cfg.CACHE_DIR, 'dir'), mkdir(cfg.CACHE_DIR); end
        cache_params = struct( ...
            'participants', {participants}, 'session', cfg.session, ...
            'conditions_to_compare', {cfg.conditions_to_compare}, ...
            'channels_to_compute', {cfg.channels_to_compute}, ...
            'sleep_stages_filter', cfg.sleep_stages_filter, ...
            'time_range', cfg.time_range);
        save(cache_file, 'spectra_data', 'freq', 'subjects_used', ...
             'channels_computed', 'cache_params');
        fprintf('Spectra cached to: %s\n', cache_file);
    end
end


%% ---- Local helper ----

function valid_trials = get_valid_trials(cond_data, subj_sleep_stages, ...
        sleep_stages_filter, fs, participant, cond_name)
%GET_VALID_TRIALS Return trial indices matching the requested sleep stages.

    n_trials = length(cond_data.trial);

    if isempty(subj_sleep_stages)
        valid_trials = 1:n_trials;
        fprintf('  %s %s: using all %d trials (no sleep stage filter)\n', ...
                participant, cond_name, n_trials);
        return;
    end

    stage_map = containers.Map( ...
        {'N1','N2','N3','REM','Wake','W'}, ...
        {1, 2, 3, 5, 0, 0});

    trial_stages = zeros(n_trials, 1);
    for t = 1:n_trials
        trial_start_sec = (cond_data.sampleinfo(t,1) - 1) / fs;
        time_diffs = abs(seconds(subj_sleep_stages.Timestamp - ...
                         subj_sleep_stages.Timestamp(1)) - trial_start_sec);
        [~, closest] = min(time_diffs);
        stage_str = subj_sleep_stages.Stage{closest};
        if stage_map.isKey(stage_str)
            trial_stages(t) = stage_map(stage_str);
        else
            trial_stages(t) = -1;
        end
    end

    valid_trials = find(ismember(trial_stages, sleep_stages_filter));
    fprintf('  %s %s: %d/%d trials in target sleep stage(s)\n', ...
            participant, cond_name, length(valid_trials), n_trials);
end

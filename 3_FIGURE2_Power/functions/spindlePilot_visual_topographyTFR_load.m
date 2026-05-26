function [all_data, trial_indices] = spindlePilot_visual_topographyTFR_load(...
    participants, session, conditions, time_range, freq_range, tfr_path)
%SPINDLEPILOT_VISUAL_TOPOGRAPHYTFR_LOAD Load all trial data from disk.
%
%   This function loads all trial data without applying any filters.
%   It is the first step in the topography pipeline.
%
%   INPUTS:
%     participants - cell array of participant IDs
%     session - session name (e.g., 'ses1')
%     conditions - cell array of condition names
%     time_range - [min_time, max_time] in seconds
%     freq_range - [min_freq, max_freq] in Hz
%     tfr_path - path to TFR data files
%
%   OUTPUTS:
%     all_data - struct containing:
%       .(participant).(condition).trials = [trials x channels x freq x time]
%       .(participant).(condition).channels = cell array of channel names
%       .(participant).(condition).freq = frequency vector
%       .(participant).(condition).time = time vector
%     trial_indices - struct containing:
%       .(participant).(condition).trial_num = trial numbers
%       .(participant).(condition).sampleinfo = [start_sample, end_sample]

    all_data = struct();
    trial_indices = struct();

    % Channels to exclude (non-EEG reference channels)
    exclude_channels = {'ROCA1', 'ROCA2', 'LOCA1', 'LOCA2', 'XX', 'XXX', ...
        'EOG', 'HEOG', 'VEOG', 'ECG', 'ECG1', 'ECG2', 'EMG', 'EMG1', 'EMG2', 'EMG1EMG2'};

    for p = 1:length(participants)
        participant = participants{p};

        for c = 1:length(conditions)
            condition = conditions{c};

            % Find all trial files for this participant/condition
            trial_files = dir(fullfile(tfr_path, sprintf('TFR_SP_trial_%s_%s_%s_*.mat', ...
                participant, session, condition)));

            if isempty(trial_files)
                continue;
            end

            % Preallocate
            trial_numbers = zeros(length(trial_files), 1);
            sampleinfo = zeros(length(trial_files), 2);
            trial_data_temp = [];
            channels = {};
            freq_axis = [];
            time_axis = [];

            for t = 1:length(trial_files)
                % Load TFR file
                tfr_data = load(fullfile(tfr_path, trial_files(t).name));
                tfr = extract_tfr_struct(tfr_data);

                % Filter out non-EEG channels
                keep_channels = setdiff(tfr.label, exclude_channels, 'stable');
                keep_idx = find(ismember(tfr.label, keep_channels));

                if isempty(keep_idx)
                    continue;
                end

                % Apply channel filter
                tfr.label = tfr.label(keep_idx);
                if ndims(tfr.powspctrm) == 4
                    tfr.powspctrm = tfr.powspctrm(:, keep_idx, :, :);
                else
                    tfr.powspctrm = tfr.powspctrm(keep_idx, :, :);
                end

                % Get frequency and time indices
                freq_idx = tfr.freq >= freq_range(1) & tfr.freq <= freq_range(2);
                time_idx = tfr.time >= time_range(1) & tfr.time <= time_range(2);

                if ~any(freq_idx) || ~any(time_idx)
                    continue;
                end

                % Extract data: [channels x freq x time]
                if ndims(tfr.powspctrm) == 4
                    data_slice = squeeze(tfr.powspctrm(1, :, freq_idx, time_idx));
                else
                    data_slice = tfr.powspctrm(:, freq_idx, time_idx);
                end

                % Initialize on first valid trial
                if isempty(channels)
                    channels = tfr.label;
                    freq_axis = tfr.freq(freq_idx);
                    time_axis = tfr.time(time_idx);
                    n_chan = length(channels);
                    n_freq = length(freq_axis);
                    n_time = length(time_axis);
                    trial_data_temp = zeros(length(trial_files), n_chan, n_freq, n_time);
                end

                % Extract trial number from filename
                tokens = regexp(trial_files(t).name, '_(\d+)\.mat$', 'tokens');
                if ~isempty(tokens)
                    trial_numbers(t) = str2double(tokens{1}{1});
                end

                % Extract sampleinfo if available
                if isfield(tfr, 'sampleinfo') && ~isempty(tfr.sampleinfo)
                    sampleinfo(t, :) = tfr.sampleinfo(1, :);
                else
                    sampleinfo(t, :) = [0, 0];
                end

                trial_data_temp(t, :, :, :) = data_slice;
            end

            % Remove empty trials
            if ~isempty(trial_data_temp)
                valid_trials = any(any(any(trial_data_temp, 2), 3), 4);
                valid_trials = valid_trials(:);

                if any(valid_trials)
                    all_data.(participant).(condition).trials = trial_data_temp(valid_trials, :, :, :);
                    all_data.(participant).(condition).channels = channels;
                    all_data.(participant).(condition).freq = freq_axis;
                    all_data.(participant).(condition).time = time_axis;

                    trial_indices.(participant).(condition).trial_num = trial_numbers(valid_trials);
                    trial_indices.(participant).(condition).sampleinfo = sampleinfo(valid_trials, :);

                    fprintf('  %s %s: %d trials, %d channels\n', ...
                        participant, condition, sum(valid_trials), length(channels));
                end
            end
        end
    end
end


function tfr = extract_tfr_struct(tfr_data)
    % Extract TFR structure from loaded data
    if isfield(tfr_data, 'tfr_single')
        tfr = tfr_data.tfr_single;
    elseif isfield(tfr_data, 'tf_result')
        tfr = tfr_data.tf_result;
    else
        fn = fieldnames(tfr_data);
        tfr = tfr_data.(fn{1});
    end
end

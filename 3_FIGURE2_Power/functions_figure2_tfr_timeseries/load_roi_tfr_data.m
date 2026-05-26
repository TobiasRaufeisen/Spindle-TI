function [all_data, freq_axis, time_axis] = load_roi_tfr_data( ...
    tfr_path, participants, session, conditions, roi_electrodes, ...
    trial_indices, time_range, freq_range, electrode_filtering_mode)
% Load ROI-averaged TFR data using trial indices from topography analysis.
%
% INPUTS
%   tfr_path        - directory containing per-trial TFR .mat files
%   participants    - cell array of participant IDs
%   session         - session label (e.g. 'ses1')
%   conditions      - cell array of condition labels
%   roi_electrodes  - cell array of electrode labels to average
%   trial_indices   - struct from with kept/rejected trial info
%   time_range      - [t_start, t_end] seconds
%   freq_range      - [f_low, f_high] Hz
%   electrode_filtering_mode - 'trial_level' | 'electrode_level' | 'none'
%
% OUTPUTS
%   all_data   - struct.(participant).(condition).{trials, freq, time}
%   freq_axis  - common frequency vector
%   time_axis  - common time vector

if nargin < 9, electrode_filtering_mode = 'trial_level'; end

EXCLUDE_CHANNELS = {'ROCA1','ROCA2','LOCA1','LOCA2','XX','XXX', ...
    'EOG','HEOG','VEOG','ECG','ECG1','ECG2','EMG','EMG1','EMG2','EMG1EMG2'};

all_data  = struct();
freq_axis = [];
time_axis = [];

total_original = 0;
total_rejected = 0;
total_kept     = 0;

for p = 1:length(participants)
    participant = participants{p};

    for c = 1:length(conditions)
        condition = conditions{c};

        % Retrieve trial info
        if ~isfield(trial_indices, participant) || ...
           ~isfield(trial_indices.(participant), condition) || ...
           ~isfield(trial_indices.(participant).(condition), 'kept')
            fprintf('  Warning: No trial indices for %s %s\n', participant, condition);
            continue;
        end

        trial_info    = trial_indices.(participant).(condition);
        kept_trials   = trial_info.kept;
        all_trials    = trial_info.trial_num;
        trials_to_use = kept_trials;

        if isempty(trials_to_use)
            fprintf('  Warning: No trials for %s %s\n', participant, condition);
            continue;
        end

        n_orig = length(all_trials);
        n_kept = length(kept_trials);
        total_original = total_original + n_orig;
        total_rejected = total_rejected + (n_orig - n_kept);
        total_kept     = total_kept + n_kept;

        fprintf('  %s %s: %d/%d kept (%.0f%% rejected)\n', ...
            participant, condition, n_kept, n_orig, (1 - n_kept/n_orig)*100);

        % Find trial files
        trial_files = dir(fullfile(tfr_path, sprintf('TFR_SP_trial_%s_%s_%s_*.mat', ...
            participant, session, condition)));
        if isempty(trial_files)
            fprintf('  Warning: No TFR files for %s %s\n', participant, condition);
            continue;
        end

        % Load matching trials
        channels       = {};
        freq_local     = [];
        time_local     = [];
        trial_data_buf = [];

        for t = 1:length(trial_files)
            tokens = regexp(trial_files(t).name, '_(\d+)\.mat$', 'tokens');
            if isempty(tokens), continue; end

            trial_num = str2double(tokens{1}{1});
            if ~ismember(trial_num, trials_to_use), continue; end

            tfr = extract_tfr_struct(load(fullfile(tfr_path, trial_files(t).name)));

            % Remove non-EEG channels
            keep_ch = setdiff(tfr.label, EXCLUDE_CHANNELS, 'stable');
            ch_idx  = find(ismember(tfr.label, keep_ch));
            if isempty(ch_idx), continue; end

            tfr.label = tfr.label(ch_idx);
            if ndims(tfr.powspctrm) == 4
                tfr.powspctrm = tfr.powspctrm(:, ch_idx, :, :);
            else
                tfr.powspctrm = tfr.powspctrm(ch_idx, :, :);
            end

            % Select freq/time range
            fi = tfr.freq >= freq_range(1) & tfr.freq <= freq_range(2);
            ti = tfr.time >= time_range(1) & tfr.time <= time_range(2);
            if ~any(fi) || ~any(ti), continue; end

            if ndims(tfr.powspctrm) == 4
                slice = squeeze(tfr.powspctrm(1, :, fi, ti));
            else
                slice = tfr.powspctrm(:, fi, ti);
            end

            % Initialise on first valid trial
            if isempty(channels)
                channels   = tfr.label;
                freq_local = tfr.freq(fi);
                time_local = tfr.time(ti);
                n_ch       = length(channels);
                n_freq     = length(freq_local);
                n_time     = length(time_local);
                trial_data_buf = zeros(length(trials_to_use), n_ch, n_freq, n_time);
            end

            idx = find(trials_to_use == trial_num);
            if ~isempty(idx)
                trial_data_buf(idx, :, :, :) = slice;
            end
        end

        if isempty(trial_data_buf) || isempty(channels), continue; end

        % Extract ROI electrodes
        roi_idx = [];
        for e = 1:length(roi_electrodes)
            ix = find(strcmpi(channels, roi_electrodes{e}), 1);
            if ~isempty(ix)
                roi_idx(end+1) = ix; %#ok<AGROW>
            else
                fprintf('  Warning: ROI electrode %s not found for %s %s\n', ...
                    roi_electrodes{e}, participant, condition);
            end
        end
        if isempty(roi_idx), continue; end

        roi_data = trial_data_buf(:, roi_idx, :, :);

        % Electrode-level NaN masking
        if strcmp(electrode_filtering_mode, 'electrode_level') && isfield(trial_info, 'passing_electrodes')
            roi_data = apply_electrode_nan_mask(roi_data, trials_to_use, ...
                trial_info.passing_electrodes, channels, roi_idx);
        end

        % Average across ROI electrodes -> [trials x freq x time]
        if length(roi_idx) > 1
            roi_data = squeeze(mean(roi_data, 2, 'omitnan'));
        else
            roi_data = squeeze(roi_data);
        end

        % Guarantee 3-D shape
        expected_numel = length(trials_to_use) * n_freq * n_time;
        if numel(roi_data) == expected_numel
            roi_data = reshape(roi_data, [length(trials_to_use), n_freq, n_time]);
        else
            warning('Dimension mismatch for %s %s -- skipping.', participant, condition);
            continue;
        end

        all_data.(participant).(condition).trials = roi_data;
        all_data.(participant).(condition).freq   = freq_local;
        all_data.(participant).(condition).time   = time_local;

        if isempty(freq_axis)
            freq_axis = freq_local;
            time_axis = time_local;
        end
    end
end

fprintf('\n  Trial summary: %d original, %d rejected (%.0f%%), %d kept\n', ...
    total_original, total_rejected, total_rejected / max(total_original, 1) * 100, total_kept);
end


function roi_data = apply_electrode_nan_mask(roi_data, trials_to_use, passing_electrodes, channels, roi_idx)
% Set ROI electrode data to NaN where that electrode did not pass filtering.
    for t = 1:length(trials_to_use)
        field_name = sprintf('trial_%d', trials_to_use(t));
        if isfield(passing_electrodes, field_name)
            passing_names = passing_electrodes.(field_name);
            for r = 1:length(roi_idx)
                if ~ismember(channels{roi_idx(r)}, passing_names)
                    roi_data(t, r, :, :) = NaN;
                end
            end
        else
            roi_data(t, :, :, :) = NaN;
        end
    end
end
function compute_results = spindlePilot_visual_topographyTFR_compute_from_filtered(...
    all_data_filtered, trial_indices_filtered, config)
%SPINDLEPILOT_VISUAL_TOPOGRAPHYTFR_COMPUTE_FROM_FILTERED Compute topography from filtered data.
%
%   This function computes topography from already-filtered data.
%   It is the third step in the topography pipeline.
%
%   INPUTS:
%     all_data_filtered - filtered data from spindlePilot_visual_topographyTFR_filter
%     trial_indices_filtered - trial indices from spindlePilot_visual_topographyTFR_filter
%     config - configuration struct
%
%   OUTPUTS:
%     compute_results - struct containing:
%       .topo_data_computed - topography data for plotting
%       .trial_indices - which trials were kept after filtering
%       .layout - FieldTrip layout for plotting
%       .matched_channels - channels used in topography
%       .config - configuration used
%       .conditions, .participants, .freq_axis, .time_axis
%       .all_data_topo - trial-level data for statistical analysis

    % Extract axes from filtered data
    [freq_axis, time_axis] = get_axes_from_data(all_data_filtered, config.participants, config.conditions);

    if isempty(freq_axis) || isempty(time_axis)
        error('No valid data remaining after filtering.');
    end

    % Prepare FieldTrip layout
    [layout, matched_channels] = prepare_layout(all_data_filtered, ...
        config.participants, config.conditions, config.topo_params);

    % Compute topography for each time-frequency window
    topo_data_computed = compute_topography_windows(all_data_filtered, ...
        config.participants, config.conditions, matched_channels, ...
        config.topo_params, freq_axis, time_axis);

    % Compute subject-level data for LME analysis
    subject_data = compute_subject_level_data(all_data_filtered, ...
        config.participants, config.conditions, matched_channels, ...
        config.topo_params, freq_axis, time_axis);

    % Package results
    compute_results = struct();
    compute_results.topo_data_computed = topo_data_computed;
    compute_results.trial_indices = trial_indices_filtered;
    compute_results.layout = layout;
    compute_results.matched_channels = matched_channels;
    compute_results.config = config;
    compute_results.conditions = config.conditions;
    compute_results.participants = config.participants;
    compute_results.freq_axis = freq_axis;
    compute_results.time_axis = time_axis;
    compute_results.topo_params = config.topo_params;
    compute_results.all_data_topo = all_data_filtered;  % Add trial-level data for statistics
    compute_results.subject_data = subject_data;  % Add subject-level data for LME analysis

    fprintf('\nComputation complete.\n');
    fprintf('Ready for plotting and statistics.\n');
end


function [layout, matched_channels] = prepare_layout(all_data, participants, conditions, topo_params)
    % Prepare FieldTrip layout for topography plotting

    % Get all channels from data
    all_channels = {};
    for p = 1:length(participants)
        participant = participants{p};
        if ~isfield(all_data, participant), continue; end
        for c = 1:length(conditions)
            condition = conditions{c};
            if isfield(all_data.(participant), condition) && isfield(all_data.(participant).(condition), 'channels')
                all_channels = all_data.(participant).(condition).channels;
                break;
            end
        end
        if ~isempty(all_channels), break; end
    end

    if isempty(all_channels)
        error('No channels found in data');
    end

    % Load layout
    try
        cfg = [];
        cfg.layout = topo_params.layout;
        layout = ft_prepare_layout(cfg);
    catch
        cfg = [];
        cfg.channel = all_channels;
        layout = ft_prepare_layout(cfg);
    end

    % Match channels (case-insensitive to handle e.g. FP1 vs Fp1)
    [~, layout_idx, ~] = intersect(lower(layout.label), lower(all_channels), 'stable');
    if isempty(layout_idx)
        error('No matching channels between layout and data');
    end

    % Use layout names (correct casing for FieldTrip topoplot)
    matched_channels = layout.label(layout_idx);
    fprintf('Matched %d channels for topography\n', length(matched_channels));
end


function topo_data = compute_topography_windows(all_data, participants, conditions, ...
    channels, topo_params, freq_axis, time_axis)
    % Compute average topography for each time-frequency window

    n_windows = size(topo_params.time_freq_windows, 1);
    topo_data = struct();

    for w = 1:n_windows
        freq_win = [topo_params.time_freq_windows{w, 1}, topo_params.time_freq_windows{w, 2}];
        time_win = [topo_params.time_freq_windows{w, 3}, topo_params.time_freq_windows{w, 4}];
        win_label = topo_params.time_freq_windows{w, 5};

        fprintf('  Window %d/%d: %s (%.1f-%.1f Hz, %.1f-%.1f s)\n', ...
            w, n_windows, win_label, freq_win(1), freq_win(2), time_win(1), time_win(2));

        % Find indices
        freq_idx = freq_axis >= freq_win(1) & freq_axis <= freq_win(2);
        time_idx = time_axis >= time_win(1) & time_axis <= time_win(2);

        % Compute for each condition
        window_data = struct();
        for c = 1:length(conditions)
            condition = conditions{c};
            [avg_power, n_participants, n_trials] = compute_condition_average(...
                all_data, participants, condition, channels, freq_idx, time_idx);

            window_data.(condition).data = avg_power;
            window_data.(condition).n_participants = n_participants;
            window_data.(condition).n_trials = n_trials;
        end

        topo_data.(win_label).data = window_data;
        topo_data.(win_label).freq_win = freq_win;
        topo_data.(win_label).time_win = time_win;
        topo_data.(win_label).win_label = win_label;
    end
end


function [avg_power, n_participants, n_trials] = compute_condition_average(...
    all_data, participants, condition, channels, freq_idx, time_idx)
    % Compute average power per channel across participants for one condition

    n_chan = length(channels);
    power_sum = zeros(n_chan, 1);
    count = zeros(n_chan, 1);
    n_participants = 0;
    n_trials = 0;

    for p = 1:length(participants)
        participant = participants{p};
        if ~isfield(all_data, participant) || ~isfield(all_data.(participant), condition)
            continue;
        end

        trials = all_data.(participant).(condition).trials;
        data_channels = all_data.(participant).(condition).channels;
        summary_method = all_data.(participant).(condition).summary_method;
        trim_percent = all_data.(participant).(condition).trim_percent;

        n_trials = n_trials + size(trials, 1);

        % Compute per-channel average for this participant
        participant_avg = nan(n_chan, 1);
        for ch = 1:n_chan
            ch_idx = find(strcmpi(data_channels, channels{ch}), 1);
            if ~isempty(ch_idx)
                % Extract channel data: [trials x freq x time]
                ch_data = squeeze(trials(:, ch_idx, freq_idx, time_idx));

                % Average across freq x time for each trial
                if ndims(ch_data) == 3
                    trial_powers = squeeze(mean(mean(ch_data, 3, 'omitnan'), 2, 'omitnan'));
                else
                    trial_powers = mean(ch_data, 2, 'omitnan');
                end

                trial_powers = trial_powers(~isnan(trial_powers));

                if isempty(trial_powers)
                    continue;
                end

                % Summarize across trials
                switch summary_method
                    case 'trimmed_mean'
                        participant_avg(ch) = trimmean(trial_powers, 2 * trim_percent);
                    case 'median'
                        participant_avg(ch) = median(trial_powers, 'omitnan');
                    otherwise
                        participant_avg(ch) = mean(trial_powers, 'omitnan');
                end
            end
        end

        % Add to sum
        if ~all(isnan(participant_avg))
            valid = ~isnan(participant_avg);
            power_sum(valid) = power_sum(valid) + participant_avg(valid);
            count(valid) = count(valid) + 1;
            n_participants = n_participants + 1;
        end
    end

    % Compute average across participants
    avg_power = nan(n_chan, 1);
    valid = count > 0;
    avg_power(valid) = power_sum(valid) ./ count(valid);
end


function [freq_axis, time_axis] = get_axes_from_data(all_data, participants, conditions)
    freq_axis = [];
    time_axis = [];
    for p = 1:length(participants)
        participant = participants{p};
        if ~isfield(all_data, participant), continue; end
        for c = 1:length(conditions)
            condition = conditions{c};
            if isfield(all_data.(participant), condition)
                freq_axis = all_data.(participant).(condition).freq;
                time_axis = all_data.(participant).(condition).time;
                return;
            end
        end
    end
end


function subject_data = compute_subject_level_data(all_data, participants, conditions, ...
    channels, topo_params, freq_axis, time_axis)
    % Compute subject-level averages for LME analysis
    % Returns structure: subject_data.P01.x5HZ.StimClean = [n_channels x 1] vector

    n_windows = size(topo_params.time_freq_windows, 1);
    n_chan = length(channels);
    subject_data = struct();

    fprintf('Computing subject-level data for LME analysis...\n');

    for p = 1:length(participants)
        participant = participants{p};

        if ~isfield(all_data, participant)
            continue;
        end

        for c = 1:length(conditions)
            condition = conditions{c};

            if ~isfield(all_data.(participant), condition)
                continue;
            end

            trials = all_data.(participant).(condition).trials;
            data_channels = all_data.(participant).(condition).channels;
            summary_method = all_data.(participant).(condition).summary_method;
            trim_percent = all_data.(participant).(condition).trim_percent;

            % Compute for each time-frequency window
            for w = 1:n_windows
                freq_win = [topo_params.time_freq_windows{w, 1}, topo_params.time_freq_windows{w, 2}];
                time_win = [topo_params.time_freq_windows{w, 3}, topo_params.time_freq_windows{w, 4}];
                win_label = topo_params.time_freq_windows{w, 5};

                % Find indices
                freq_idx = freq_axis >= freq_win(1) & freq_axis <= freq_win(2);
                time_idx = time_axis >= time_win(1) & time_axis <= time_win(2);

                % Compute per-channel average for this participant
                participant_avg = nan(n_chan, 1);
                for ch = 1:n_chan
                    ch_idx = find(strcmpi(data_channels, channels{ch}), 1);
                    if ~isempty(ch_idx)
                        % Extract channel data: [trials x freq x time]
                        ch_data = squeeze(trials(:, ch_idx, freq_idx, time_idx));

                        % Average across freq x time for each trial
                        if ndims(ch_data) == 3
                            trial_powers = squeeze(mean(mean(ch_data, 3, 'omitnan'), 2, 'omitnan'));
                        else
                            trial_powers = mean(ch_data, 2, 'omitnan');
                        end

                        trial_powers = trial_powers(~isnan(trial_powers));

                        if isempty(trial_powers)
                            continue;
                        end

                        % Summarize across trials
                        switch summary_method
                            case 'trimmed_mean'
                                participant_avg(ch) = trimmean(trial_powers, 2 * trim_percent);
                            case 'median'
                                participant_avg(ch) = median(trial_powers, 'omitnan');
                            otherwise
                                participant_avg(ch) = mean(trial_powers, 'omitnan');
                        end
                    end
                end

                % Store subject-level data
                subject_data.(participant).(condition).(win_label) = participant_avg;
            end
        end
    end

    fprintf('Subject-level data computed for %d participants.\n', length(fieldnames(subject_data)));
end

function slowwaves = addSlowwavePhaseInformation(slowwaves, eeg_data, params)
% Add RelativeTime, PhaseVector, and FilteredWaveform to slowwaves table
% These fields are required for phase-amplitude coupling analysis
%
% Inputs:
%   slowwaves - table with slowwave events (must have NegPeak, Channel, EventSample)
%   eeg_data  - FieldTrip continuous EEG data structure
%   params    - struct with fields:
%               .window_duration - time window around trough (default: 2.0 s)
%               .so_freq_range   - SO filter range (default: [0.5 2])
%               .filter_order    - filter order (default: 3)
%
% Outputs:
%   slowwaves - table with added columns: RelativeTime, PhaseVector, FilteredWaveform

    if nargin < 3 || isempty(params)
        params = struct();
    end
    if ~isfield(params, 'window_duration'), params.window_duration = 2.0; end
    if ~isfield(params, 'so_freq_range'), params.so_freq_range = [0.5 2]; end
    if ~isfield(params, 'filter_order'), params.filter_order = 3; end

    fprintf('Adding phase information to %d slowwaves...\n', height(slowwaves));

    fsample = eeg_data.fsample;
    half_window = params.window_duration / 2;
    window_samples = round(params.window_duration * fsample);

    % Initialize cell arrays for new columns
    RelativeTime = cell(height(slowwaves), 1);
    PhaseVector = cell(height(slowwaves), 1);
    FilteredWaveform = cell(height(slowwaves), 1);

    % Design bandpass filter for slow oscillation
    [b, a] = butter(params.filter_order, params.so_freq_range / (fsample/2), 'bandpass');

    % Get unique channels for filtering
    if ismember('Channel', slowwaves.Properties.VariableNames)
        channels = slowwaves.Channel;
    elseif ismember('PrimaryChannel', slowwaves.Properties.VariableNames)
        channels = slowwaves.PrimaryChannel;
    else
        error('Slowwaves table must have Channel or PrimaryChannel field');
    end

    % Strip reference electrode suffix (A1, A2) from channel names for matching
    channels_stripped = cell(size(channels));
    for i = 1:length(channels)
        ch = channels{i};
        if iscell(ch), ch = ch{1}; end
        % Remove A1, A2, M1, M2 suffixes (common reference schemes)
        ch = regexprep(ch, 'A[12]$', '');
        ch = regexprep(ch, 'M[12]$', '');
        channels_stripped{i} = ch;
    end

    unique_channels = unique(channels_stripped);
    fprintf('  Processing %d unique channels\n', length(unique_channels));

    % Pre-filter all channels
    filtered_data = cell(length(unique_channels), 1);
    for ch_idx = 1:length(unique_channels)
        chan_name = unique_channels{ch_idx};

        % Find channel in EEG data (handle cell array)
        if iscell(chan_name)
            chan_name = chan_name{1};
        end

        label_idx = find(strcmpi(eeg_data.label, chan_name));
        if isempty(label_idx)
            fprintf('  WARNING: Channel %s not found in EEG data\n', chan_name);
            continue;
        end

        % Concatenate all trials for this channel
        chan_data = [];
        for trial_idx = 1:length(eeg_data.trial)
            chan_data = [chan_data, eeg_data.trial{trial_idx}(label_idx, :)];
        end

        % Remove NaN values before filtering (replace with mean to preserve length)
        nan_mask = isnan(chan_data);
        if any(nan_mask)
            chan_data(nan_mask) = mean(chan_data(~nan_mask));
        end

        % Filter the data (use filter instead of filtfilt to avoid edge artifacts with very long data)
        % For phase analysis, we use a zero-phase filter by filtering forward and backward
        try
            filtered_chan = filtfilt(b, a, double(chan_data));
        catch
            % If filtfilt fails, use regular filter (will have phase shift but better than NaN)
            filtered_chan = filter(b, a, double(chan_data));
            fprintf('    WARNING: Using regular filter (not zero-phase) for channel %s\n', chan_name);
        end

        filtered_data{ch_idx} = filtered_chan;

        fprintf('  Filtered channel %s (%d/%d)\n', chan_name, ch_idx, length(unique_channels));
    end

    % Extract continuous time vector
    continuous_time = [];
    for trial_idx = 1:length(eeg_data.time)
        continuous_time = [continuous_time, eeg_data.time{trial_idx}];
    end

    % Process each slowwave
    n_success = 0;
    n_failed = 0;

    for sw_idx = 1:height(slowwaves)
        if mod(sw_idx, 100) == 0
            fprintf('  Processed %d/%d slowwaves\n', sw_idx, height(slowwaves));
        end

        % Get slowwave timing
        if ismember('NegPeak', slowwaves.Properties.VariableNames)
            trough_time = slowwaves.NegPeak(sw_idx);
        elseif ismember('Peak', slowwaves.Properties.VariableNames)
            trough_time = slowwaves.Peak(sw_idx);
        else
            n_failed = n_failed + 1;
            continue;
        end

        % Get channel (stripped version for matching)
        chan = channels_stripped{sw_idx};

        % Find channel index in unique channels
        chan_idx = find(strcmpi(unique_channels, chan));
        if isempty(chan_idx) || isempty(filtered_data{chan_idx})
            n_failed = n_failed + 1;
            continue;
        end

        % Define time window around trough
        window_start_time = trough_time - half_window;
        window_end_time = trough_time + half_window;

        % Find corresponding sample indices in continuous data
        in_window = continuous_time >= window_start_time & continuous_time <= window_end_time;
        window_indices = find(in_window);

        if isempty(window_indices) || length(window_indices) < 10
            n_failed = n_failed + 1;
            continue;
        end

        start_idx = window_indices(1);
        end_idx = window_indices(end);

        % Extract window
        window_indices = start_idx:end_idx;
        if length(window_indices) < 10 % Sanity check
            n_failed = n_failed + 1;
            continue;
        end

        % Get filtered waveform for this window
        filtered_window = filtered_data{chan_idx}(window_indices);

        % Calculate phase using Hilbert transform
        analytic_signal = hilbert(filtered_window);
        phase = angle(analytic_signal);

        % Create relative time vector (centered at trough)
        relative_time = continuous_time(window_indices) - trough_time;

        % Store results
        RelativeTime{sw_idx} = relative_time(:);
        PhaseVector{sw_idx} = phase(:);
        FilteredWaveform{sw_idx} = filtered_window(:);

        n_success = n_success + 1;
    end

    % Add new columns to table
    slowwaves.RelativeTime = RelativeTime;
    slowwaves.PhaseVector = PhaseVector;
    slowwaves.FilteredWaveform = FilteredWaveform;

    fprintf('  Successfully added phase info to %d slowwaves (%d failed)\n', n_success, n_failed);
end

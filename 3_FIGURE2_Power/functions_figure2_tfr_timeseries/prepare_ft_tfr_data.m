function [ft_data1, ft_data2] = prepare_ft_tfr_data(all_data, participants, ...
    cond1, cond2, freq_axis, analysis_freq_idx, common_time, apply_db_transform)
% Prepare participant-level TFR averages in FieldTrip format for statistics.
%
% Each participant contributes one observation (mean across their trials).
%
% INPUTS
%   all_data            - struct.(participant).(condition).{trials, freq, time}
%   participants        - cell array of participant IDs
%   cond1, cond2        - condition labels to compare
%   freq_axis           - full frequency vector
%   analysis_freq_idx   - logical index into freq_axis for analysis range
%   common_time         - common time vector
%   apply_db_transform  - if true, 10*log10 before statistics
%
% OUTPUTS
%   ft_data1, ft_data2  - cell arrays of FieldTrip structs (one per participant)

if nargin < 8, apply_db_transform = false; end

ft_data1 = {};
ft_data2 = {};
analysis_freq   = freq_axis(analysis_freq_idx);
n_analysis_freq = length(analysis_freq);

for p = 1:length(participants)
    participant = participants{p};

    if ~isfield(all_data, participant) || ...
       ~isfield(all_data.(participant), cond1) || ...
       ~isfield(all_data.(participant), cond2)
        continue;
    end

    trials1 = all_data.(participant).(cond1).trials;
    trials2 = all_data.(participant).(cond2).trials;
    if isempty(trials1) || isempty(trials2), continue; end

    % Participant-level average
    data1 = squeeze(mean(trials1, 1));
    data2 = squeeze(mean(trials2, 1));

    if apply_db_transform
        data1 = 10 * log10(data1);
        data2 = 10 * log10(data2);
    end

    freq1 = all_data.(participant).(cond1).freq;
    freq2 = all_data.(participant).(cond2).freq;
    time1 = all_data.(participant).(cond1).time;
    time2 = all_data.(participant).(cond2).time;

    if length(freq1) < 2 || length(time1) < 2 || length(freq2) < 2 || length(time2) < 2
        continue;
    end

    % Ensure [freq x time] orientation
    if size(data1,1) ~= length(freq1) && size(data1,2) == length(freq1), data1 = data1'; end
    if size(data2,1) ~= length(freq2) && size(data2,2) == length(freq2), data2 = data2'; end

    % Interpolate to common grid then restrict to analysis frequencies
    i1 = interpolate_to_common_grid(data1, freq1, time1, freq_axis, common_time);
    i2 = interpolate_to_common_grid(data2, freq2, time2, freq_axis, common_time);
    i1 = i1(analysis_freq_idx, :);
    i2 = i2(analysis_freq_idx, :);

    if size(i1,1) ~= n_analysis_freq || size(i1,2) ~= length(common_time)
        continue;
    end

    % Package as FieldTrip struct
    ft1 = struct('label', {{'ROI'}}, 'freq', analysis_freq, 'time', common_time, ...
        'powspctrm', reshape(i1, [1, n_analysis_freq, length(common_time)]), ...
        'dimord', 'chan_freq_time');
    ft2 = struct('label', {{'ROI'}}, 'freq', analysis_freq, 'time', common_time, ...
        'powspctrm', reshape(i2, [1, n_analysis_freq, length(common_time)]), ...
        'dimord', 'chan_freq_time');

    ft_data1{end+1} = ft1; %#ok<AGROW>
    ft_data2{end+1} = ft2; %#ok<AGROW>
end
end

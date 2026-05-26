function tval_map = compute_full_range_tvalues(all_data, participants, ...
    cond1, cond2, freq_axis, common_time, apply_db_transform)
% Compute paired t-values across the full frequency range for visualisation.
%
% One observation per participant (mean across trials). Computes pointwise
% t = mean(diff) / (std(diff) / sqrt(N)).
%
% INPUTS
%   all_data           - struct.(participant).(condition).{trials, freq, time}
%   participants       - cell array of participant IDs
%   cond1, cond2       - condition labels
%   freq_axis          - frequency vector
%   common_time        - time vector
%   apply_db_transform - if true, 10*log10 before computing differences
%
% OUTPUT
%   tval_map - [freq x time] paired t-values

if nargin < 7, apply_db_transform = false; end

n_freq = length(freq_axis);
n_time = length(common_time);
subj_diffs = {};

for p = 1:length(participants)
    participant = participants{p};
    if ~isfield(all_data, participant) || ...
       ~isfield(all_data.(participant), cond1) || ...
       ~isfield(all_data.(participant), cond2)
        continue;
    end

    trials1 = all_data.(participant).(cond1).trials;
    trials2 = all_data.(participant).(cond2).trials;
    freq1   = all_data.(participant).(cond1).freq;
    freq2   = all_data.(participant).(cond2).freq;
    time1   = all_data.(participant).(cond1).time;
    time2   = all_data.(participant).(cond2).time;

    if isempty(trials1) || isempty(trials2), continue; end
    if length(freq1) < 2 || length(time1) < 2 || length(freq2) < 2 || length(time2) < 2
        continue;
    end

    data1 = squeeze(mean(trials1, 1));
    data2 = squeeze(mean(trials2, 1));

    if apply_db_transform
        data1 = 10 * log10(data1);
        data2 = 10 * log10(data2);
    end

    if size(data1,1) ~= length(freq1) && size(data1,2) == length(freq1), data1 = data1'; end
    if size(data2,1) ~= length(freq2) && size(data2,2) == length(freq2), data2 = data2'; end

    i1 = interpolate_to_common_grid(data1, freq1, time1, freq_axis, common_time);
    i2 = interpolate_to_common_grid(data2, freq2, time2, freq_axis, common_time);

    subj_diffs{end+1} = i1 - i2; %#ok<AGROW>
end

n_subj = length(subj_diffs);
diff_array = zeros(n_freq, n_time, n_subj);
for s = 1:n_subj
    diff_array(:,:,s) = subj_diffs{s};
end

mean_d   = mean(diff_array, 3);
std_d    = std(diff_array, 0, 3);
tval_map = mean_d ./ (std_d / sqrt(n_subj));
end

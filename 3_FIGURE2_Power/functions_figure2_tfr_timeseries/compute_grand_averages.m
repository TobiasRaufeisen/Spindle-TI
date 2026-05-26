function grand_avg = compute_grand_averages(all_data, participants, conditions, freq_axis, time_axis, weighting)
% Compute grand-average TFR per condition.
%
% INPUTS
%   all_data     - struct.(participant).(condition).{trials, freq, time}
%   participants - cell array of participant IDs
%   conditions   - cell array of condition labels
%   freq_axis    - target frequency vector
%   time_axis    - target time vector
%   weighting    - 'equal' (default): mean of participant means
%                  'trial_pooled': pool all trials then average
%
% OUTPUT
%   grand_avg    - struct.(condition) = [freq x time] mean power

if nargin < 6 || isempty(weighting), weighting = 'equal'; end

n_freq = length(freq_axis);
n_time = length(time_axis);
grand_avg = struct();

for c = 1:length(conditions)
    condition = conditions{c};

    if strcmp(weighting, 'equal')
        % Each participant contributes one mean -> average across participants
        subj_means = [];
        for p = 1:length(participants)
            trials_interp = get_interpolated_trials(all_data, participants{p}, ...
                condition, freq_axis, time_axis);
            if isempty(trials_interp), continue; end
            subj_means = cat(3, subj_means, mean(trials_interp, 1));
        end
        if ~isempty(subj_means)
            grand_avg.(condition) = squeeze(mean(subj_means, 3));
        else
            grand_avg.(condition) = nan(n_freq, n_time);
        end

    else  % 'trial_pooled'
        % Pool all trials across participants then average
        pooled = [];
        for p = 1:length(participants)
            trials_interp = get_interpolated_trials(all_data, participants{p}, ...
                condition, freq_axis, time_axis);
            if isempty(trials_interp), continue; end
            pooled = cat(1, pooled, trials_interp);
        end
        if ~isempty(pooled)
            grand_avg.(condition) = squeeze(mean(pooled, 1));
        else
            grand_avg.(condition) = nan(n_freq, n_time);
        end
    end
end

fprintf('  Weighting mode: %s\n', weighting);
end


function trials_interp = get_interpolated_trials(all_data, participant, condition, freq_axis, time_axis)
% Return trials interpolated to the common grid, or [] if unavailable.
    trials_interp = [];
    if ~isfield(all_data, participant) || ~isfield(all_data.(participant), condition)
        return;
    end

    trials     = all_data.(participant).(condition).trials;
    local_freq = all_data.(participant).(condition).freq;
    local_time = all_data.(participant).(condition).time;

    if length(local_freq) < 2 || length(local_time) < 2
        return;
    end

    if isequal(local_freq, freq_axis) && isequal(local_time, time_axis)
        trials_interp = trials;
    else
        n_tr = size(trials, 1);
        trials_interp = zeros(n_tr, length(freq_axis), length(time_axis));
        for t = 1:n_tr
            trials_interp(t,:,:) = interpolate_to_common_grid( ...
                squeeze(trials(t,:,:)), local_freq, local_time, freq_axis, time_axis);
        end
    end
end

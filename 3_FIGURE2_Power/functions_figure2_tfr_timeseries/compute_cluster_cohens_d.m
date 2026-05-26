function [d, n_pairs, mean_diff, sd_diff] = compute_cluster_cohens_d( ...
    all_data, participants, cond1, cond2, mask, stat_freq, stat_time)
%COMPUTE_CLUSTER_COHENS_D Paired Cohen's d restricted to a cluster mask.
%   For each subject, computes the mean of the trial-averaged TFR across
%   the time-frequency points selected by the cluster mask, separately for
%   each condition. Returns the paired Cohen's d of (cond1 - cond2).
%
%   IMPORTANT: This effect size is descriptive only. It is biased upward
%   by the selection process that defined the cluster (non-independence
%   error / "double dipping"). Do NOT interpret it as a generalizable
%   population effect size — use the a priori band-averaged d for that.
%
%   INPUTS:
%     all_data     - struct.(participant).(condition).{trials, freq, time}
%     participants - cell array of participant IDs
%     cond1, cond2 - condition labels (difference is cond1 - cond2)
%     mask         - [freq x time] logical mask in stat coordinates
%     stat_freq    - frequency vector matching mask rows
%     stat_time    - time vector matching mask columns
%
%   OUTPUTS:
%     d         - paired Cohen's d (mean(diff) / std(diff))
%     n_pairs   - number of valid subject pairs
%     mean_diff - mean of the paired differences
%     sd_diff   - standard deviation of the paired differences

    n_subj = length(participants);
    means1 = nan(n_subj, 1);
    means2 = nan(n_subj, 1);

    for si = 1:n_subj
        subj = participants{si};
        if ~isfield(all_data, subj), continue; end
        if ~isfield(all_data.(subj), cond1), continue; end
        if ~isfield(all_data.(subj), cond2), continue; end

        means1(si) = subject_cluster_mean(all_data.(subj).(cond1), mask, stat_freq, stat_time);
        means2(si) = subject_cluster_mean(all_data.(subj).(cond2), mask, stat_freq, stat_time);
    end

    valid = ~isnan(means1) & ~isnan(means2);
    diff_vals = means1(valid) - means2(valid);
    n_pairs = sum(valid);

    if n_pairs < 2 || std(diff_vals) == 0
        d = NaN;
        mean_diff = NaN;
        sd_diff = NaN;
    else
        mean_diff = mean(diff_vals);
        sd_diff = std(diff_vals);
        d = mean_diff / sd_diff;
    end
end


function m = subject_cluster_mean(cond_data, mask, stat_freq, stat_time)
% Compute the mean of a subject's trial-averaged TFR over the cluster mask.

    % Average across trials -> [freq x time]
    subj_tfr = squeeze(mean(cond_data.trials, 1, 'omitnan'));

    % Nearest-neighbor mapping from stat coords to subject coords
    % (per-subject axes may differ slightly in numerical value)
    n_f = length(stat_freq);
    n_t = length(stat_time);
    fi = zeros(1, n_f);
    ti = zeros(1, n_t);
    for i = 1:n_f
        [~, fi(i)] = min(abs(cond_data.freq - stat_freq(i)));
    end
    for i = 1:n_t
        [~, ti(i)] = min(abs(cond_data.time - stat_time(i)));
    end

    sub_tfr = subj_tfr(fi, ti);

    if ~any(mask(:))
        m = NaN;
        return;
    end

    m = mean(sub_tfr(mask), 'omitnan');
end

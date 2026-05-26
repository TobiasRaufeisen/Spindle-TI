function run_tfr_descriptive_statistics(all_data, grand_avg, stats_results, ...
    participants, conditions, condition_pairs, freq_axis, time_axis, params)
%RUN_TFR_DESCRIPTIVE_STATISTICS Print descriptive statistics for TFR timeseries.
%   Prints global descriptives per condition (analysis-band averaged per subject)
%   and per-comparison cluster descriptives with effect sizes.
%
%   INPUTS:
%     all_data        - struct.(participant).(condition).{trials, freq, time}
%     grand_avg       - struct.(condition) = [freq x time] grand average
%     stats_results   - struct.(comp_name) = FieldTrip stat struct
%     participants    - cell array of participant IDs
%     conditions      - cell array of condition labels
%     condition_pairs - Nx3 cell: {cond1, cond2, label; ...}
%     freq_axis       - frequency vector
%     time_axis       - time vector
%     params          - parameter struct with freq_range_analysis, stats_alpha

    analysis_fi = freq_axis >= params.freq_range_analysis(1) & ...
                  freq_axis <= params.freq_range_analysis(2);

    fprintf('\n========================================\n');
    fprintf('DESCRIPTIVE STATISTICS: TFR Time Series\n');
    fprintf('========================================\n');
    fprintf('ROI electrodes: %s\n', strjoin(params.roi_electrodes, ', '));
    fprintf('Analysis band:  %.0f-%.0f Hz\n', params.freq_range_analysis);
    fprintf('Display range:  %.0f-%.0f Hz, %.2f-%.2f s\n', ...
        params.freq_range_plot(1), params.freq_range_plot(2), ...
        params.time_range(1), params.time_range(2));

    % --- Per-condition descriptives (analysis-band averaged) ---
    [subj_means, n_valid] = compute_subject_band_means( ...
        all_data, participants, conditions, freq_axis, time_axis, analysis_fi);

    fprintf('\n  Global descriptives (analysis-band mean per subject):\n');
    fprintf('  %-10s  %8s  %10s  %10s  %10s  %10s  %10s  %10s\n', ...
        'Condition', 'N', 'Mean', 'SD', 'SEM', 'Median', 'Min', 'Max');
    fprintf('  %s\n', repmat('-', 1, 80));
    for ci = 1:length(conditions)
        vals = subj_means(:, ci);
        vals = vals(~isnan(vals));
        n = length(vals);
        fprintf('  %-10s  %8d  %10.4f  %10.4f  %10.4f  %10.4f  %10.4f  %10.4f\n', ...
            conditions{ci}, n, mean(vals), std(vals), std(vals)/sqrt(n), ...
            median(vals), min(vals), max(vals));
    end

    % --- Trial count summary ---
    fprintf('\n  Trial counts per condition:\n');
    fprintf('  %-10s  %8s  %10s  %10s  %10s\n', ...
        'Condition', 'N_subj', 'Mean_tri', 'Min_tri', 'Max_tri');
    fprintf('  %s\n', repmat('-', 1, 50));
    for ci = 1:length(conditions)
        cond = conditions{ci};
        trial_counts = [];
        for p = 1:length(participants)
            subj = participants{p};
            if isfield(all_data, subj) && isfield(all_data.(subj), cond)
                trial_counts(end+1) = size(all_data.(subj).(cond).trials, 1); %#ok<AGROW>
            end
        end
        if ~isempty(trial_counts)
            fprintf('  %-10s  %8d  %10.1f  %10d  %10d\n', ...
                cond, length(trial_counts), mean(trial_counts), ...
                min(trial_counts), max(trial_counts));
        end
    end

    % --- Per-comparison cluster descriptives ---
    for p = 1:size(condition_pairs, 1)
        cond1 = condition_pairs{p, 1};
        cond2 = condition_pairs{p, 2};
        label = condition_pairs{p, 3};
        comp_name = sprintf('%s_vs_%s', cond1, cond2);

        fprintf('\n  --- Comparison: %s ---\n', label);

        if ~isfield(stats_results, comp_name)
            fprintf('  No statistics available.\n');
            continue;
        end

        stat = stats_results.(comp_name);

        % Condition means in analysis band
        ci1 = find(strcmp(conditions, cond1));
        ci2 = find(strcmp(conditions, cond2));
        vals1 = subj_means(:, ci1);
        vals2 = subj_means(:, ci2);
        valid = ~isnan(vals1) & ~isnan(vals2);
        diff_vals = vals1(valid) - vals2(valid);

        fprintf('  Band-averaged descriptives (N = %d):\n', sum(valid));
        fprintf('  %-10s  %10s  %10s  %10s\n', '', 'Mean', 'SD', 'SEM');
        fprintf('  %s\n', repmat('-', 1, 45));
        for vi = 1:3
            switch vi
                case 1, lbl = cond1; v = vals1(valid);
                case 2, lbl = cond2; v = vals2(valid);
                case 3, lbl = 'Diff'; v = diff_vals;
            end
            fprintf('  %-10s  %10.4f  %10.4f  %10.4f\n', ...
                lbl, mean(v), std(v), std(v)/sqrt(length(v)));
        end
        if std(diff_vals) > 0
            fprintf('  Cohen''s d (full window, a priori band; UNBIASED): %.3f\n', ...
                mean(diff_vals) / std(diff_vals));
        end

        % Report clusters (with descriptive within-cluster effect sizes)
        print_cluster_info(stat, params.stats_alpha, 'positive', ...
            'posclusters', 'posclusterslabelmat', 'posdistribution', ...
            all_data, participants, cond1, cond2);
        print_cluster_info(stat, params.stats_alpha, 'negative', ...
            'negclusters', 'negclusterslabelmat', 'negdistribution', ...
            all_data, participants, cond1, cond2);
    end

    fprintf('\n========================================\n');
end


%% ========================================================================
%  LOCAL HELPERS
%  ========================================================================

function [subj_means, n_valid] = compute_subject_band_means( ...
    all_data, participants, conditions, freq_axis, time_axis, analysis_fi)
% Compute per-subject mean power in the analysis frequency band.
% Returns [n_subj x n_cond] matrix.

    n_subj = length(participants);
    n_cond = length(conditions);
    subj_means = nan(n_subj, n_cond);
    n_valid = zeros(1, n_cond);

    for si = 1:n_subj
        subj = participants{si};
        for ci = 1:n_cond
            cond = conditions{ci};
            if ~isfield(all_data, subj) || ~isfield(all_data.(subj), cond)
                continue;
            end
            trials = all_data.(subj).(cond).trials;  % [trials x freq x time]
            local_freq = all_data.(subj).(cond).freq;
            local_fi = local_freq >= freq_axis(find(analysis_fi, 1)) & ...
                       local_freq <= freq_axis(find(analysis_fi, 1, 'last'));
            % Mean across trials, then analysis-band freqs, then time
            subj_mean_tfr = squeeze(mean(trials, 1, 'omitnan'));  % [freq x time]
            subj_means(si, ci) = mean(subj_mean_tfr(local_fi, :), 'all', 'omitnan');
            n_valid(ci) = n_valid(ci) + 1;
        end
    end
end


function print_cluster_info(stat, alpha, direction, cluster_field, label_field, dist_field, ...
    all_data, participants, cond1, cond2)
% Print information about clusters of the given direction.

    if ~isfield(stat, cluster_field) || isempty(stat.(cluster_field))
        fprintf('  No %s clusters found.\n', direction);
        return;
    end

    clusters = stat.(cluster_field);
    n_sig = sum([clusters.prob] < alpha);

    if n_sig == 0
        fprintf('  No significant %s clusters (smallest p = %.4f).\n', ...
            direction, min([clusters.prob]));
    end

    % Null distribution summary
    if isfield(stat, dist_field) && ~isempty(stat.(dist_field))
        null_dist = stat.(dist_field);
        null_dist = null_dist(isfinite(null_dist));
        if ~isempty(null_dist)
            fprintf('  %s null distribution: median=%.2f, 95th pctl=%.2f, max=%.2f\n', ...
                direction, median(null_dist), prctile(null_dist, 95), max(null_dist));
        end
    end

    for ci = 1:length(clusters)
        is_sig = clusters(ci).prob < alpha;
        sig_tag = '';
        if is_sig, sig_tag = ' ***SIGNIFICANT***'; end

        % Count time-frequency pixels in cluster
        if isfield(stat, label_field)
            n_pixels = sum(stat.(label_field)(:) == ci);
        else
            n_pixels = NaN;
        end

        fprintf('  %s cluster %d: p = %.4f, stat = %.2f, %d TF-pixels%s\n', ...
            direction, ci, clusters(ci).prob, clusters(ci).clusterstat, ...
            n_pixels, sig_tag);

        % For significant clusters, report time-frequency extent and effect size
        if is_sig && isfield(stat, label_field)
            mask = stat.(label_field) == ci;
            % mask is [1 x freq x time] or [freq x time]
            mask = squeeze(mask);
            freq_involved = stat.freq(any(mask, 2));
            time_involved = stat.time(any(mask, 1));
            fprintf('    Frequency extent: %.1f - %.1f Hz\n', ...
                min(freq_involved), max(freq_involved));
            fprintf('    Time extent:      %.3f - %.3f s\n', ...
                min(time_involved), max(time_involved));

            % Cluster-restricted Cohen's d (DESCRIPTIVE — selection-biased upward,
            % do not interpret as a generalizable effect size)
            [d_clust, n_pairs] = compute_cluster_cohens_d(all_data, participants, ...
                cond1, cond2, mask, stat.freq, stat.time);
            if ~isnan(d_clust)
                fprintf('    Cohen''s d within cluster (DESCRIPTIVE, biased): %.3f (N=%d)\n', ...
                    d_clust, n_pairs);
            end
        end
    end
end

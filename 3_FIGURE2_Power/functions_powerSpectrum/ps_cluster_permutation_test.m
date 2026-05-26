function cluster_results = ps_cluster_permutation_test(condition_stats, spectra_data, ...
        freq, freq_range, cluster_cfg)
%PS_CLUSTER_PERMUTATION_TEST Frequency-resolved cluster-based permutation test.
%
%   cluster_results = ps_cluster_permutation_test(condition_stats, spectra_data,
%       freq, freq_range, cluster_cfg)
%
%   Implements Maris & Oostenveld (2007): paired sign-flip permutation test
%   over frequency bins. Uses exact enumeration when n_subjects <= 12,
%   otherwise Monte Carlo sampling.
%
%   cluster_cfg fields: n_permutations, forming_alpha, cluster_alpha,
%                        comparisons (cell Nx2), comp_labels (cell Nx1)

    fprintf('\n=== Cluster-Based Permutation Test: Frequency-Resolved ===\n');
    fprintf('Settings: forming alpha = %.3f (two-tailed), cluster alpha = %.3f\n', ...
        cluster_cfg.forming_alpha, cluster_cfg.cluster_alpha);

    freq_mask = freq >= freq_range(1) & freq <= freq_range(2);
    freq_analysis = freq(freq_mask);
    n_freqs = length(freq_analysis);
    fprintf('Frequency bins: %d (%.2f - %.2f Hz)\n', n_freqs, min(freq_analysis), max(freq_analysis));

    comparisons = cluster_cfg.comparisons;
    cluster_results = struct();

    for comp = 1:size(comparisons, 1)
        cond_A = comparisons{comp, 1};
        cond_B = comparisons{comp, 2};
        comp_label = sprintf('%s_vs_%s', cond_A, cond_B);
        fprintf('\n--- %s vs %s ---\n', cond_A, cond_B);

        if ~isfield(condition_stats, cond_A) || ~isfield(condition_stats, cond_B)
            warning('Missing data for %s vs %s. Skipping.', cond_A, cond_B);
            continue;
        end

        % Match subjects
        labels_A = spectra_data.(cond_A).subject_labels;
        labels_B = spectra_data.(cond_B).subject_labels;
        [common_subj, idx_A, idx_B] = intersect(labels_A, labels_B, 'stable');
        n_subj = length(common_subj);

        if n_subj < 2
            warning('Fewer than 2 matched subjects. Skipping.');
            continue;
        end

        data_A = condition_stats.(cond_A).per_subject_db(idx_A, freq_mask);
        data_B = condition_stats.(cond_B).per_subject_db(idx_B, freq_mask);
        fprintf('Matched subjects: %d\n', n_subj);

        if n_subj < 6
            fprintf('  NOTE: minimum achievable p = %.4f (1/2^%d)\n', 1/2^n_subj, n_subj);
        end

        % Observed t-statistics
        diff_matrix = data_A - data_B;
        diff_mean = mean(diff_matrix, 1);
        diff_se   = std(diff_matrix, 0, 1) / sqrt(n_subj);
        obs_t = diff_mean ./ diff_se;
        obs_t(diff_se == 0) = 0;

        t_crit = tinv(1 - cluster_cfg.forming_alpha / 2, n_subj - 1);
        fprintf('Cluster-forming threshold: |t| > %.3f (df = %d)\n', t_crit, n_subj - 1);

        % Observed clusters
        [obs_pos_cl, obs_pos_stats] = ps_find_freq_clusters(obs_t, t_crit, 'positive');
        [obs_neg_cl, obs_neg_stats] = ps_find_freq_clusters(obs_t, -t_crit, 'negative');
        n_pos = length(obs_pos_stats);
        n_neg = length(obs_neg_stats);
        fprintf('Observed clusters: %d positive, %d negative\n', n_pos, n_neg);

        % No clusters -> store empty result
        if n_pos == 0 && n_neg == 0
            fprintf('No supra-threshold clusters. Skipping permutation.\n');
            cluster_results.(comp_label) = empty_result(cond_A, cond_B, obs_t, ...
                t_crit, freq_analysis, n_subj, common_subj);
            continue;
        end

        % Build sign-flip matrix
        if n_subj <= 12
            n_perm = 2^n_subj;
            sign_matrix = ones(n_perm, n_subj);
            for p = 0:(n_perm - 1)
                for si = 1:n_subj
                    if bitget(p, si), sign_matrix(p+1, si) = -1; end
                end
            end
            fprintf('Exact permutation: %d (2^%d)\n', n_perm, n_subj);
        else
            n_perm = cluster_cfg.n_permutations;
            rng(42, 'twister');
            sign_matrix = 2 * (randi(2, n_perm, n_subj) - 1) - 1;
            fprintf('Monte Carlo: %d permutations\n', n_perm);
        end

        % Permutation loop
        null_max_pos = zeros(n_perm, 1);
        null_max_neg = zeros(n_perm, 1);

        fprintf('Running permutations');
        progress_step = max(1, round(n_perm / 10));
        for perm = 1:n_perm
            if mod(perm, progress_step) == 0, fprintf('.'); end

            perm_diff = diff_matrix .* sign_matrix(perm, :)';
            perm_mean = mean(perm_diff, 1);
            perm_se   = std(perm_diff, 0, 1) / sqrt(n_subj);
            perm_t    = perm_mean ./ perm_se;
            perm_t(perm_se == 0) = 0;

            [~, pp_stats] = ps_find_freq_clusters(perm_t, t_crit, 'positive');
            [~, pn_stats] = ps_find_freq_clusters(perm_t, -t_crit, 'negative');
            if ~isempty(pp_stats), null_max_pos(perm) = max(pp_stats); end
            if ~isempty(pn_stats), null_max_neg(perm) = min(pn_stats); end
        end
        fprintf(' done.\n');

        % Cluster p-values (Phipson & Smyth, 2010)
        pos_p = arrayfun(@(s) (sum(null_max_pos >= s) + 1) / (n_perm + 1), obs_pos_stats);
        neg_p = arrayfun(@(s) (sum(null_max_neg <= s) + 1) / (n_perm + 1), obs_neg_stats);

        % Report
        report_clusters('Positive', cond_A, cond_B, obs_pos_cl, obs_pos_stats, pos_p, ...
            freq_analysis, prctile(null_max_pos, 95));
        report_clusters('Negative', cond_A, cond_B, obs_neg_cl, obs_neg_stats, neg_p, ...
            freq_analysis, prctile(null_max_neg, 5));

        cluster_results.(comp_label) = struct( ...
            'cond_A', cond_A, 'cond_B', cond_B, ...
            'obs_t', obs_t, 't_crit', t_crit, 'freq', freq_analysis, ...
            'n_subjects', n_subj, 'common_subjects', {common_subj}, ...
            'pos_clusters', {obs_pos_cl}, 'pos_cluster_stats', obs_pos_stats, ...
            'pos_cluster_p', pos_p, ...
            'neg_clusters', {obs_neg_cl}, 'neg_cluster_stats', obs_neg_stats, ...
            'neg_cluster_p', neg_p, ...
            'n_permutations', n_perm, ...
            'null_max_pos', null_max_pos, 'null_max_neg', null_max_neg, ...
            'null_pos_95pct', prctile(null_max_pos, 95), ...
            'null_neg_05pct', prctile(null_max_neg, 5));
    end

    fprintf('\n=== Cluster-Based Permutation Test Complete ===\n');
end


%% ---- Local helpers ----

function res = empty_result(cond_A, cond_B, obs_t, t_crit, freq_analysis, n_subj, common_subj)
    res = struct( ...
        'cond_A', cond_A, 'cond_B', cond_B, ...
        'obs_t', obs_t, 't_crit', t_crit, 'freq', freq_analysis, ...
        'n_subjects', n_subj, 'common_subjects', {common_subj}, ...
        'pos_clusters', {{}}, 'pos_cluster_stats', [], 'pos_cluster_p', [], ...
        'neg_clusters', {{}}, 'neg_cluster_stats', [], 'neg_cluster_p', [], ...
        'n_permutations', 0, 'null_max_pos', [], 'null_max_neg', [], ...
        'null_pos_95pct', NaN, 'null_neg_05pct', NaN);
end


function report_clusters(direction, cond_A, cond_B, clusters, stats, p_vals, freq_vec, pctile_val)
    if strcmp(direction, 'Positive')
        fprintf('\nPositive clusters (%s > %s):\n', cond_A, cond_B);
        if ~isnan(pctile_val) && ~isempty(stats)
            fprintf('  Null 95th percentile: %.2f\n', pctile_val);
        end
    else
        fprintf('Negative clusters (%s < %s):\n', cond_A, cond_B);
        if ~isnan(pctile_val) && ~isempty(stats)
            fprintf('  Null 5th percentile: %.2f\n', pctile_val);
        end
    end

    if isempty(stats)
        fprintf('  None\n');
        return;
    end

    for cl = 1:length(stats)
        cl_freqs = freq_vec(clusters{cl});
        stat_val = abs(stats(cl));
        fprintf('  Cluster %d: %.2f - %.2f Hz (%d bins), sum(t) = %.2f, p = %.4f %s\n', ...
            cl, min(cl_freqs), max(cl_freqs), length(clusters{cl}), ...
            stat_val, p_vals(cl), ps_sig_stars(p_vals(cl)));
    end
end

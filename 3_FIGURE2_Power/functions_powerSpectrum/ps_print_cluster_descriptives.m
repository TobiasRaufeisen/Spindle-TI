function ps_print_cluster_descriptives(cluster_results, condition_stats, spectra_data, ...
        freq, freq_range, cluster_alpha)
%PS_PRINT_CLUSTER_DESCRIPTIVES Print descriptive statistics for significant clusters.
%
%   Reports per-condition mean power (dB) within each significant cluster's
%   frequency range, plus Cohen's d for paired comparisons.

    fprintf('\n=== DESCRIPTIVE STATISTICS: Significant Frequency Clusters ===\n');
    fprintf('Values are electrode-averaged per subject, then M +/- SD across subjects.\n\n');

    freq_mask = freq >= freq_range(1) & freq <= freq_range(2);
    freq_analysis = freq(freq_mask);
    comp_fields = fieldnames(cluster_results);

    for comp = 1:length(comp_fields)
        res = cluster_results.(comp_fields{comp});
        cond_A = res.cond_A;
        cond_B = res.cond_B;

        % Collect significant clusters
        sig_clusters = collect_sig_clusters(res, cluster_alpha);

        if isempty(sig_clusters)
            fprintf('--- %s vs %s: No significant clusters ---\n\n', cond_A, cond_B);
            continue;
        end

        fprintf('--- %s vs %s ---\n', cond_A, cond_B);

        % Match subjects
        labels_A = spectra_data.(cond_A).subject_labels;
        labels_B = spectra_data.(cond_B).subject_labels;
        [~, idx_A, idx_B] = intersect(labels_A, labels_B, 'stable');
        n_subj = length(idx_A);

        data_A = condition_stats.(cond_A).per_subject_db(idx_A, freq_mask);
        data_B = condition_stats.(cond_B).per_subject_db(idx_B, freq_mask);

        for sci = 1:length(sig_clusters)
            cl = sig_clusters{sci};
            cl_freqs = freq_analysis(cl.indices);

            pw_A    = mean(data_A(:, cl.indices), 2);
            pw_B    = mean(data_B(:, cl.indices), 2);
            pw_diff = pw_A - pw_B;

            fprintf('\n  Cluster: %.2f - %.2f Hz (%d bins, %s, p = %.4f)\n', ...
                min(cl_freqs), max(cl_freqs), length(cl.indices), cl.direction, cl.p);
            fprintf('  N = %d matched subjects\n', n_subj);
            fprintf('  %-8s  %10s  %10s  %10s  %10s  %10s\n', ...
                '', 'Mean(dB)', 'SD(dB)', 'SEM(dB)', 'Min(dB)', 'Max(dB)');
            fprintf('  %s\n', repmat('-', 1, 65));
            print_row(cond_A, pw_A, n_subj);
            print_row(cond_B, pw_B, n_subj);
            print_row('Diff',  pw_diff, n_subj);
            fprintf('  Cohen''s d (paired): %.3f\n', mean(pw_diff) / std(pw_diff));
        end
        fprintf('\n');
    end
end


%% ---- Local helpers ----

function sig = collect_sig_clusters(res, alpha)
    sig = {};
    for cl = 1:length(res.pos_cluster_p)
        if res.pos_cluster_p(cl) < alpha
            sig{end+1} = struct('indices', res.pos_clusters{cl}, ...
                'direction', 'positive', 'p', res.pos_cluster_p(cl)); %#ok<AGROW>
        end
    end
    for cl = 1:length(res.neg_cluster_p)
        if res.neg_cluster_p(cl) < alpha
            sig{end+1} = struct('indices', res.neg_clusters{cl}, ...
                'direction', 'negative', 'p', res.neg_cluster_p(cl)); %#ok<AGROW>
        end
    end
end


function print_row(label, vals, n)
    fprintf('  %-8s  %10.3f  %10.3f  %10.3f  %10.3f  %10.3f\n', ...
        label, mean(vals), std(vals), std(vals)/sqrt(n), min(vals), max(vals));
end

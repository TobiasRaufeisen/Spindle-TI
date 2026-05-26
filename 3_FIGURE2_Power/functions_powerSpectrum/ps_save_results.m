function ps_save_results(fig, OUTPUT_DIR, condition_stats, spectra_data, ...
        conditions_to_compare, channels_computed, channels_to_plot_resolved, ...
        participants, subjects_used, session, freq, freq_range, ...
        spindle_band, artifact_band, sleep_stages_filter, pub, ...
        lme_results, cluster_results, electrode_handling, cluster_cfg)
%PS_SAVE_RESULTS Save figure (PNG/SVG/FIG), data (.mat), and statistics report (.txt).

    %% Prepare output directory
    if ~exist(OUTPUT_DIR, 'dir'), mkdir(OUTPUT_DIR); end

    %% Resize figure for saving
    SAVE_WIDTH_CM  = 35;
    SAVE_HEIGHT_CM = 10;
    set(fig, 'Units', 'centimeters', ...
        'Position', [5 5 SAVE_WIDTH_CM SAVE_HEIGHT_CM], ...
        'PaperUnits', 'centimeters', ...
        'PaperSize', [SAVE_WIDTH_CM SAVE_HEIGHT_CM], ...
        'PaperPosition', [0 0 SAVE_WIDTH_CM SAVE_HEIGHT_CM]);

    %% Build filename
    n_ch = length(channels_to_plot_resolved);
    if length(subjects_used) == 1
        subj_str = subjects_used{1};
    else
        subj_str = sprintf('n%d_subjects', length(subjects_used));
    end
    if n_ch == 1
        ch_str = channels_to_plot_resolved{1};
    else
        ch_str = sprintf('%dch', n_ch);
    end
    base = sprintf('figure2_powerSpectrum_comparison_wide_%s_%s_%s', ...
                   subj_str, session, ch_str);

    %% Save figure formats
    print(fig, fullfile(OUTPUT_DIR, [base '.png']), '-dpng', '-r300');
    print(fig, fullfile(OUTPUT_DIR, [base '.svg']), '-dsvg', '-vector');
    savefig(fig, fullfile(OUTPUT_DIR, [base '.fig']));

    %% Save data
    save(fullfile(OUTPUT_DIR, [base '.mat']), ...
        'condition_stats', 'spectra_data', 'conditions_to_compare', ...
        'channels_computed', 'channels_to_plot_resolved', ...
        'participants', 'subjects_used', 'session', 'freq', 'freq_range', ...
        'spindle_band', 'artifact_band', 'sleep_stages_filter', 'pub', ...
        'lme_results', 'cluster_results');

    %% Write statistics text report
    stats_file = fullfile(OUTPUT_DIR, [base '_stats.txt']);
    fid = fopen(stats_file, 'w');

    write_header(fid, subjects_used, session, conditions_to_compare, ...
        channels_to_plot_resolved, electrode_handling);
    write_lme_results(fid, lme_results);
    write_cluster_results(fid, cluster_results, spectra_data, condition_stats, ...
        freq, freq_range, cluster_cfg);

    fclose(fid);

    %% Report
    fprintf('\nOutputs saved to: %s\n', OUTPUT_DIR);
    fprintf('  - %s.png (300 DPI)\n', base);
    fprintf('  - %s.svg\n', base);
    fprintf('  - %s.fig\n', base);
    fprintf('  - %s.mat\n', base);
    fprintf('  - %s_stats.txt\n', base);
end


%% ======== Local helpers ========

function write_header(fid, subjects_used, session, conditions, channels, elec_handling)
    fprintf(fid, 'Power Spectrum LME Statistics\n');
    fprintf(fid, '=============================\n');
    fprintf(fid, 'Date: %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
    fprintf(fid, 'Subjects (%d): %s\n', length(subjects_used), strjoin(subjects_used, ', '));
    fprintf(fid, 'Session: %s\n', session);
    fprintf(fid, 'Conditions: %s\n', strjoin(conditions, ', '));
    fprintf(fid, 'Channels (plot): %s\n', strjoin(channels, ', '));
    fprintf(fid, 'Sleep stages: N2\n');
    fprintf(fid, 'Electrode handling: %s\n', elec_handling);
end


function write_lme_results(fid, lme_results)
    bands = fieldnames(lme_results);
    for b = 1:length(bands)
        bname = bands{b};
        res = lme_results.(bname);

        fprintf(fid, '\n\n=== %s Band (%.1f-%.1f Hz) ===\n', ...
            bname, res.band_range(1), res.band_range(2));
        fprintf(fid, 'Formula: %s\n', res.formula);

        fprintf(fid, '\nModel summary:\n');
        fprintf(fid, '%s', evalc('disp(res.model)'));

        % Descriptives
        fprintf(fid, '\nDescriptive statistics (dB, electrode-averaged per subject):\n');
        desc = res.descriptives;
        cats = categories(desc.Condition);
        for ci = 1:length(cats)
            vals = desc.mean_Power(desc.Condition == cats{ci});
            fprintf(fid, '  %-5s: M = %7.2f, SD = %5.2f  (n = %d)\n', ...
                cats{ci}, mean(vals), std(vals), length(vals));
        end

        % ANOVA
        fprintf(fid, '\nOmnibus F-test (ANOVA on LME):\n');
        fprintf(fid, '%s', evalc('disp(res.anova)'));

        % Post-hoc
        ph = res.posthoc;
        fprintf(fid, '\nPost-hoc pairwise comparisons (Holm-corrected):\n');
        fprintf(fid, '  %-20s  %8s  %8s  %6s  %10s  %10s\n', ...
            'Comparison', 'Est(dB)', 't', 'df', 'p_raw', 'p_holm');
        fprintf(fid, '  %s\n', repmat('-', 1, 68));
        for i = 1:length(ph.pair_labels)
            fprintf(fid, '  %-20s  %8.3f  %8.3f  %6.0f  %10.4f  %10.4f\n', ...
                ph.pair_labels{i}, ph.estimates(i), ph.t_values(i), ...
                ph.df(i), ph.p_raw(i), ph.p_holm(i));
        end
    end
end


function write_cluster_results(fid, cluster_results, spectra_data, condition_stats, ...
        freq, freq_range, cluster_cfg)
    fprintf(fid, '\n\n========================================\n');
    fprintf(fid, 'CLUSTER-BASED PERMUTATION TEST RESULTS\n');
    fprintf(fid, '========================================\n');
    fprintf(fid, 'Method: Maris & Oostenveld (2007) cluster-based permutation test\n');
    fprintf(fid, 'Test dimension: Frequency bins\n');
    fprintf(fid, 'Permutation scheme: Sign-flip (paired within-subject)\n');
    fprintf(fid, 'Cluster-forming alpha: %.3f (two-tailed)\n', cluster_cfg.forming_alpha);
    fprintf(fid, 'Cluster significance alpha: %.3f\n', cluster_cfg.cluster_alpha);
    fprintf(fid, 'Frequency range: %.1f - %.1f Hz\n', freq_range(1), freq_range(2));

    freq_mask = freq >= freq_range(1) & freq <= freq_range(2);
    freq_analysis = freq(freq_mask);
    comp_fields = fieldnames(cluster_results);

    for comp = 1:length(comp_fields)
        res = cluster_results.(comp_fields{comp});

        if res.n_permutations == 0
            perm_str = 'N/A (no supra-threshold clusters)';
        elseif res.n_subjects <= 12
            perm_str = sprintf('%d (exact, 2^%d)', res.n_permutations, res.n_subjects);
        else
            perm_str = sprintf('%d (Monte Carlo)', res.n_permutations);
        end

        fprintf(fid, '\n--- %s vs %s ---\n', res.cond_A, res.cond_B);
        fprintf(fid, 'Matched subjects: %d\n', res.n_subjects);
        fprintf(fid, 'Permutations: %s\n', perm_str);
        fprintf(fid, 'Cluster-forming threshold: |t| > %.3f (df = %d)\n', ...
            res.t_crit, res.n_subjects - 1);

        write_cluster_direction(fid, 'Positive', res.cond_A, res.cond_B, ...
            res.pos_clusters, res.pos_cluster_stats, res.pos_cluster_p, ...
            res.freq, res.null_pos_95pct);
        write_cluster_direction(fid, 'Negative', res.cond_A, res.cond_B, ...
            res.neg_clusters, res.neg_cluster_stats, res.neg_cluster_p, ...
            res.freq, res.null_neg_05pct);

        % Descriptives for significant clusters
        write_sig_cluster_descriptives(fid, res, spectra_data, condition_stats, ...
            freq_mask, freq_analysis, cluster_cfg.cluster_alpha);
    end
end


function write_cluster_direction(fid, direction, cond_A, cond_B, clusters, stats, p_vals, freq_vec, pctile_val)
    if strcmp(direction, 'Positive')
        fprintf(fid, '\nPositive clusters (%s > %s):\n', cond_A, cond_B);
        pctile_label = '95th';
    else
        fprintf(fid, 'Negative clusters (%s < %s):\n', cond_A, cond_B);
        pctile_label = '5th';
    end

    if ~isnan(pctile_val) && ~isempty(stats)
        fprintf(fid, '  Null distribution %s percentile: %.2f\n', pctile_label, pctile_val);
    end

    if isempty(stats)
        fprintf(fid, '  None\n');
        return;
    end

    for cl = 1:length(stats)
        cl_freqs = freq_vec(clusters{cl});
        fprintf(fid, '  Cluster %d: %.2f - %.2f Hz (%d bins), sum(t) = %.2f, p = %.4f %s\n', ...
            cl, min(cl_freqs), max(cl_freqs), length(clusters{cl}), ...
            abs(stats(cl)), p_vals(cl), ps_sig_stars(p_vals(cl)));
    end
end


function write_sig_cluster_descriptives(fid, res, spectra_data, condition_stats, ...
        freq_mask, freq_analysis, alpha)
    sig_cl = {};
    for cl = 1:length(res.pos_cluster_p)
        if res.pos_cluster_p(cl) < alpha
            sig_cl{end+1} = struct('indices', res.pos_clusters{cl}, ...
                'direction', 'positive', 'p', res.pos_cluster_p(cl)); %#ok<AGROW>
        end
    end
    for cl = 1:length(res.neg_cluster_p)
        if res.neg_cluster_p(cl) < alpha
            sig_cl{end+1} = struct('indices', res.neg_clusters{cl}, ...
                'direction', 'negative', 'p', res.neg_cluster_p(cl)); %#ok<AGROW>
        end
    end

    if isempty(sig_cl), return; end

    fprintf(fid, '\nDescriptive Statistics for Significant Clusters:\n');
    labels_A = spectra_data.(res.cond_A).subject_labels;
    labels_B = spectra_data.(res.cond_B).subject_labels;
    [~, idx_A, idx_B] = intersect(labels_A, labels_B, 'stable');
    n_subj = length(idx_A);
    data_A = condition_stats.(res.cond_A).per_subject_db(idx_A, freq_mask);
    data_B = condition_stats.(res.cond_B).per_subject_db(idx_B, freq_mask);

    for sci = 1:length(sig_cl)
        cl = sig_cl{sci};
        cl_freqs = freq_analysis(cl.indices);
        pw_A = mean(data_A(:, cl.indices), 2);
        pw_B = mean(data_B(:, cl.indices), 2);
        pw_d = pw_A - pw_B;

        fprintf(fid, '\n  Cluster: %.2f-%.2f Hz (%s, p=%.4f, N=%d)\n', ...
            min(cl_freqs), max(cl_freqs), cl.direction, cl.p, n_subj);
        fprintf(fid, '  %-8s  %10s  %10s  %10s  %10s  %10s\n', ...
            '', 'Mean(dB)', 'SD(dB)', 'SEM(dB)', 'Min(dB)', 'Max(dB)');
        fprintf(fid, '  %s\n', repmat('-', 1, 65));
        write_desc_row(fid, res.cond_A, pw_A, n_subj);
        write_desc_row(fid, res.cond_B, pw_B, n_subj);
        write_desc_row(fid, 'Diff', pw_d, n_subj);
        fprintf(fid, '  Cohen''s d (paired): %.3f\n', mean(pw_d)/std(pw_d));
    end
end


function write_desc_row(fid, label, vals, n)
    fprintf(fid, '  %-8s  %10.3f  %10.3f  %10.3f  %10.3f  %10.3f\n', ...
        label, mean(vals), std(vals), std(vals)/sqrt(n), min(vals), max(vals));
end

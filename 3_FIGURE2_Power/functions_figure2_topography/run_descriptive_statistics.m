function run_descriptive_statistics(compute_results, stats_results, config)
%RUN_DESCRIPTIVE_STATISTICS Print descriptive statistics for topography data.
%   Prints global descriptives per condition (electrode-averaged per subject)
%   and per-electrode descriptives within significant clusters.
%
%   INPUTS:
%     compute_results - output of spindlePilot_visual_topographyTFR_compute_from_filtered
%     stats_results   - output of spindlePilot_visual_topographyTFR_stats
%     config          - pipeline config struct

    subject_data     = compute_results.subject_data;
    matched_channels = compute_results.matched_channels;
    conditions       = compute_results.conditions;
    participants     = fieldnames(subject_data);
    n_subj           = length(participants);
    n_chan            = length(matched_channels);

    fprintf('\n========================================\n');
    fprintf('DESCRIPTIVE STATISTICS: Power Topography\n');
    fprintf('========================================\n');

    for wi = 1:size(config.topo_params.time_freq_windows, 1)
        wl = config.topo_params.time_freq_windows{wi, 5};
        fprintf('\n--- Window: %s (%.0f-%.0f Hz, %.2f-%.2f s) ---\n', wl, ...
            config.topo_params.time_freq_windows{wi, 1}, ...
            config.topo_params.time_freq_windows{wi, 2}, ...
            config.topo_params.time_freq_windows{wi, 3}, ...
            config.topo_params.time_freq_windows{wi, 4});

        [power_by_subj, power_by_subj_elec] = build_power_matrices( ...
            subject_data, participants, conditions, wl, n_chan);

        print_global_descriptives(power_by_subj, conditions, n_subj);

        if isfield(stats_results, wl) && isfield(stats_results.(wl), 'cluster_results')
            cluster_results = stats_results.(wl).cluster_results;
        else
            cluster_results = struct();
        end

        print_global_pairwise_stats(power_by_subj, conditions, cluster_results);

        if ~isempty(fieldnames(cluster_results))
            print_cluster_descriptives(cluster_results, ...
                power_by_subj_elec, conditions, matched_channels);
        end
    end
end


%% ========================================================================
%  LOCAL HELPERS
%  ========================================================================

function [power_by_subj, power_by_subj_elec] = build_power_matrices( ...
    subject_data, participants, conditions, window_label, n_chan)
    % Build subject x condition and subject x electrode x condition matrices

    n_subj = length(participants);
    n_cond = length(conditions);
    power_by_subj      = nan(n_subj, n_cond);
    power_by_subj_elec = nan(n_subj, n_chan, n_cond);

    for si = 1:n_subj
        subj = participants{si};
        for ci = 1:n_cond
            cond = conditions{ci};
            if isfield(subject_data.(subj), cond) && ...
               isfield(subject_data.(subj).(cond), window_label)
                vals = subject_data.(subj).(cond).(window_label);
                power_by_subj(si, ci) = mean(vals, 'omitnan');
                for ch = 1:min(n_chan, length(vals))
                    power_by_subj_elec(si, ch, ci) = vals(ch);
                end
            end
        end
    end
end


function print_global_descriptives(power_by_subj, conditions, n_subj)
    fprintf('\n  Global descriptives (electrode-averaged per subject, N = %d):\n', n_subj);
    fprintf('  %-10s  %10s  %10s  %10s  %10s  %10s  %10s\n', ...
        'Condition', 'Mean(dB)', 'SD(dB)', 'SEM(dB)', 'Median', 'Min', 'Max');
    fprintf('  %s\n', repmat('-', 1, 75));
    for ci = 1:length(conditions)
        vals = power_by_subj(:, ci);
        vals = vals(~isnan(vals));
        fprintf('  %-10s  %10.3f  %10.3f  %10.3f  %10.3f  %10.3f  %10.3f\n', ...
            conditions{ci}, mean(vals), std(vals), std(vals)/sqrt(length(vals)), ...
            median(vals), min(vals), max(vals));
    end
end


function print_global_pairwise_stats(power_by_subj, conditions, cluster_results)
    % Print paired effect sizes for all condition pairs at the global
    % (electrode-averaged) level. Reported regardless of cluster significance,
    % so non-significant contrasts also get an interpretable effect size.
    %
    % Cohen's d is the paired (d_z) form: mean(diff) / SD(diff), matching the
    % within-cluster d reported elsewhere in this script.

    % Determine pair ordering: prefer the order used by the cluster tests so
    % that the sign convention matches the rest of the report. Fall back to
    % all unique pairs from `conditions` if no cluster results are available.
    if ~isempty(fieldnames(cluster_results))
        comp_names = fieldnames(cluster_results);
        n_pairs = length(comp_names);
        pairs = cell(n_pairs, 2);
        for pi = 1:n_pairs
            parts = strsplit(comp_names{pi}, '_vs_');
            pairs{pi, 1} = parts{1};
            pairs{pi, 2} = parts{2};
        end
    else
        idx = nchoosek(1:length(conditions), 2);
        n_pairs = size(idx, 1);
        pairs = cell(n_pairs, 2);
        for pi = 1:n_pairs
            pairs{pi, 1} = conditions{idx(pi, 1)};
            pairs{pi, 2} = conditions{idx(pi, 2)};
        end
    end

    fprintf(['\n  Global pairwise effect sizes ' ...
        '(electrode-averaged per subject, paired):\n']);
    fprintf('  %-18s  %4s  %10s  %10s  %8s  %10s  %10s\n', ...
        'Comparison', 'N', 'MeanDiff', 'SD(Diff)', 't', 'p (two-t)', 'Cohen d_z');
    fprintf('  %s\n', repmat('-', 1, 82));

    for pi = 1:n_pairs
        c1 = pairs{pi, 1};
        c2 = pairs{pi, 2};
        ci1 = find(strcmp(conditions, c1));
        ci2 = find(strcmp(conditions, c2));
        if isempty(ci1) || isempty(ci2), continue; end

        v1 = power_by_subj(:, ci1);
        v2 = power_by_subj(:, ci2);
        valid = ~isnan(v1) & ~isnan(v2);
        d_vec = v1(valid) - v2(valid);
        n_d   = length(d_vec);

        if n_d < 2
            continue;
        end

        m_d  = mean(d_vec);
        sd_d = std(d_vec);
        if sd_d == 0
            t_val = NaN; p_val = NaN; cohen_dz = NaN;
        else
            sem_d    = sd_d / sqrt(n_d);
            t_val    = m_d / sem_d;
            p_val    = 2 * (1 - tcdf(abs(t_val), n_d - 1));
            cohen_dz = m_d / sd_d;
        end

        comp_label = sprintf('%s vs %s', c1, c2);
        fprintf('  %-18s  %4d  %10.3f  %10.3f  %8.3f  %10.4f  %10.3f\n', ...
            comp_label, n_d, m_d, sd_d, t_val, p_val, cohen_dz);
    end
end


function print_cluster_descriptives(cluster_results, power_by_subj_elec, ...
    conditions, matched_channels)
    % Print descriptives for electrodes within significant clusters

    comp_names = fieldnames(cluster_results);
    for ci = 1:length(comp_names)
        result = cluster_results.(comp_names{ci});
        if isempty(result.significant_clusters), continue; end

        parts = strsplit(comp_names{ci}, '_vs_');
        cond1 = parts{1};  cond2 = parts{2};
        cond1_idx = find(strcmp(conditions, cond1));
        cond2_idx = find(strcmp(conditions, cond2));

        for sci = 1:length(result.significant_clusters)
            cl_idx   = result.significant_clusters(sci);
            elec_idx = result.observed_clusters{cl_idx};
            elec_names = matched_channels(elec_idx);

            fprintf('\n  Significant cluster: %s vs %s (p = %.4f, %d electrodes)\n', ...
                cond1, cond2, result.cluster_p_values(cl_idx), length(elec_idx));
            fprintf('  Electrodes: %s\n', strjoin(elec_names, ', '));

            cl_power_1 = mean(power_by_subj_elec(:, elec_idx, cond1_idx), 2, 'omitnan');
            cl_power_2 = mean(power_by_subj_elec(:, elec_idx, cond2_idx), 2, 'omitnan');
            cl_diff    = cl_power_1 - cl_power_2;
            valid      = ~isnan(cl_diff);

            % Cluster-averaged descriptives
            fprintf('  %-10s  %10s  %10s  %10s  %10s  %10s\n', ...
                '', 'Mean(dB)', 'SD(dB)', 'SEM(dB)', 'Min(dB)', 'Max(dB)');
            fprintf('  %s\n', repmat('-', 1, 60));

            labels = {cond1, cond2, 'Diff'};
            vectors = {cl_power_1, cl_power_2, cl_diff};
            for vi = 1:3
                v = vectors{vi}(valid);
                fprintf('  %-10s  %10.3f  %10.3f  %10.3f  %10.3f  %10.3f\n', ...
                    labels{vi}, mean(v), std(v), std(v)/sqrt(length(v)), min(v), max(v));
            end
            fprintf('  Cohen''s d (paired): %.3f\n', ...
                mean(cl_diff(valid)) / std(cl_diff(valid)));

            % Per-electrode descriptives
            fprintf('\n  Per-electrode power (group mean across subjects):\n');
            fprintf('  %-8s  %10s  %10s  %10s  %10s\n', ...
                'Elec', [cond1 '(dB)'], [cond2 '(dB)'], 'Diff(dB)', 't-stat');
            fprintf('  %s\n', repmat('-', 1, 55));
            for ei = 1:length(elec_idx)
                e_idx = elec_idx(ei);
                e_pw1 = power_by_subj_elec(:, e_idx, cond1_idx);
                e_pw2 = power_by_subj_elec(:, e_idx, cond2_idx);
                fprintf('  %-8s  %10.3f  %10.3f  %10.3f  %10.3f\n', ...
                    elec_names{ei}, mean(e_pw1, 'omitnan'), mean(e_pw2, 'omitnan'), ...
                    mean(e_pw1, 'omitnan') - mean(e_pw2, 'omitnan'), ...
                    result.obs_t_stats(e_idx));
            end
        end
    end
end

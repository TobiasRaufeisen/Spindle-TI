function export_statistics_to_text(stats_results, channels, conditions, config, output_file)
%EXPORT_STATISTICS_TO_TEXT Write cluster-corrected statistics to text file.
%   Exports a detailed report of all cluster-corrected permutation statistics
%   for publication reference.
%
%   INPUTS:
%     stats_results - cluster-corrected statistics results
%     channels      - matched channel labels
%     conditions    - cell array of condition names
%     config        - pipeline config struct
%     output_file   - full path to output .txt file

    fprintf('Exporting statistics to %s\n', output_file);

    fid = fopen(output_file, 'w');
    if fid == -1
        error('Could not open file for writing: %s', output_file);
    end

    cleanup = onCleanup(@() fclose(fid));

    % Header
    fprintf(fid, '========================================\n');
    fprintf(fid, 'FIGURE 2: SPINDLE POWER TOPOGRAPHY\n');
    fprintf(fid, 'CLUSTER-CORRECTED PERMUTATION STATISTICS\n');
    fprintf(fid, '========================================\n\n');
    fprintf(fid, 'Generated: %s\n\n', datestr(now));

    % Analysis parameters
    fprintf(fid, 'ANALYSIS PARAMETERS\n');
    fprintf(fid, '-------------------\n');
    fprintf(fid, 'Conditions: %s\n', strjoin(conditions, ', '));
    fprintf(fid, 'Event type: %s\n', config.event_type);
    fprintf(fid, 'Sleep stage: N2\n\n');

    if isfield(config, 'topo_params') && isfield(config.topo_params, 'time_freq_windows')
        win = config.topo_params.time_freq_windows(1, :);
        fprintf(fid, 'Time-frequency window:\n');
        fprintf(fid, '  Frequency: %.1f - %.1f Hz\n', win{1}, win{2});
        fprintf(fid, '  Time: %.2f - %.2f s\n', win{3}, win{4});
        fprintf(fid, '  Label: %s\n\n', win{5});
    end

    fprintf(fid, 'Statistical parameters:\n');
    fprintf(fid, '  Significance level (alpha): %.3f\n', config.stats.alpha);
    fprintf(fid, '  Cluster-forming threshold: %.3f\n', config.stats.cluster_alpha);
    fprintf(fid, '  Number of permutations: %d\n', config.stats.n_permutations);
    fprintf(fid, '  Minimum cluster size: %d electrodes\n\n', config.stats.min_cluster_size);

    % Get window labels (skip metadata fields)
    window_labels = fieldnames(stats_results);
    window_labels = window_labels(~ismember(window_labels, ...
        {'conditions', 'pair_indices', 'channels', 'pair_labels'}));

    % Results for each window
    for w = 1:length(window_labels)
        win_label = window_labels{w};
        if ~isfield(stats_results.(win_label), 'cluster_results'), continue; end

        cluster_results = stats_results.(win_label).cluster_results;
        comp_names = fieldnames(cluster_results);

        fprintf(fid, '\n========================================\n');
        fprintf(fid, 'WINDOW: %s\n', win_label);
        fprintf(fid, '========================================\n');

        for c = 1:length(comp_names)
            comp_name = comp_names{c};
            result = cluster_results.(comp_name);

            fprintf(fid, '\n----------------------------------------\n');
            fprintf(fid, 'COMPARISON: %s\n', strrep(comp_name, '_vs_', ' vs '));
            fprintf(fid, '----------------------------------------\n\n');
            fprintf(fid, 'Number of subjects: %d\n\n', result.n_subjects);

            if isempty(result.significant_clusters)
                fprintf(fid, 'No significant clusters found.\n\n');
                write_nonsig_clusters(fid, result, channels);
            else
                write_significant_clusters(fid, result, channels, config);
                write_remaining_nonsig_clusters(fid, result, channels, config);
            end

            % Channel-level summary
            fprintf(fid, 'CHANNEL-LEVEL STATISTICS SUMMARY:\n');
            fprintf(fid, '  Channels with p < %.3f: %d/%d\n', ...
                config.stats.cluster_alpha, ...
                sum(result.obs_p_values < config.stats.cluster_alpha), length(channels));
            fprintf(fid, '  Channels with p < %.3f: %d/%d\n', ...
                config.stats.alpha, ...
                sum(result.obs_p_values < config.stats.alpha), length(channels));

            valid_t = result.obs_t_stats(isfinite(result.obs_t_stats));
            if ~isempty(valid_t)
                fprintf(fid, '  T-statistic range: [%.3f, %.3f]\n', min(valid_t), max(valid_t));
            end
            fprintf(fid, '\n');
        end
    end

    fprintf(fid, '\n========================================\n');
    fprintf(fid, 'END OF STATISTICS REPORT\n');
    fprintf(fid, '========================================\n');
end


%% ========================================================================
%  LOCAL HELPERS
%  ========================================================================

function write_nonsig_clusters(fid, result, channels)
    if isempty(result.observed_clusters), return; end

    fprintf(fid, 'Observed clusters (not significant):\n');
    fprintf(fid, '  Total clusters: %d\n\n', length(result.observed_clusters));

    for cl = 1:length(result.observed_clusters)
        fprintf(fid, '  Cluster %d:\n', cl);
        fprintf(fid, '    Size: %d electrodes\n', length(result.observed_clusters{cl}));
        fprintf(fid, '    p-value: %.4f\n', result.cluster_p_values(cl));
        fprintf(fid, '    Electrodes: %s\n', ...
            strjoin(channels(result.observed_clusters{cl}), ', '));
        fprintf(fid, '    Cluster statistic (sum|t|): %.2f\n\n', ...
            result.cluster_stats(cl));
    end
end


function write_significant_clusters(fid, result, channels, config)
    fprintf(fid, 'SIGNIFICANT CLUSTERS: %d\n\n', length(result.significant_clusters));

    for i = 1:length(result.significant_clusters)
        cluster_idx  = result.significant_clusters(i);
        electrode_idx = result.observed_clusters{cluster_idx};
        electrode_names = channels(electrode_idx);

        fprintf(fid, '--- Cluster %d (SIGNIFICANT) ---\n', i);
        fprintf(fid, 'Cluster size: %d electrodes\n', length(electrode_idx));
        fprintf(fid, 'Cluster p-value: %.4f (p < %.3f)\n', ...
            result.cluster_p_values(cluster_idx), config.stats.alpha);
        fprintf(fid, 'Cluster statistic (sum|t|): %.2f\n\n', ...
            result.cluster_stats(cluster_idx));

        fprintf(fid, 'Electrodes in cluster:\n');
        for e = 1:length(electrode_idx)
            ch_idx = electrode_idx(e);
            fprintf(fid, '  %s: t = %.3f, p = %.4f\n', ...
                electrode_names{e}, result.obs_t_stats(ch_idx), result.obs_p_values(ch_idx));
        end
        fprintf(fid, '\n');

        fprintf(fid, 'Summary: %d-electrode cluster (p = %.4f) including: %s\n\n', ...
            length(electrode_idx), result.cluster_p_values(cluster_idx), ...
            strjoin(electrode_names, ', '));
    end
end


function write_remaining_nonsig_clusters(fid, result, channels, config)
    non_sig = setdiff(1:length(result.observed_clusters), result.significant_clusters);
    if isempty(non_sig), return; end

    fprintf(fid, '\nOBSERVED CLUSTERS (not significant):\n\n');
    for i = 1:length(non_sig)
        cluster_idx  = non_sig(i);
        electrode_idx = result.observed_clusters{cluster_idx};

        fprintf(fid, '--- Cluster %d (not significant) ---\n', cluster_idx);
        fprintf(fid, 'Cluster size: %d electrodes\n', length(electrode_idx));
        fprintf(fid, 'Cluster p-value: %.4f (p >= %.3f)\n', ...
            result.cluster_p_values(cluster_idx), config.stats.alpha);
        fprintf(fid, 'Cluster statistic: %.2f\n', result.cluster_stats(cluster_idx));
        fprintf(fid, 'Electrodes: %s\n\n', ...
            strjoin(channels(electrode_idx), ', '));
    end
end

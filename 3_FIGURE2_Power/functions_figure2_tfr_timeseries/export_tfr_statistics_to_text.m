function export_tfr_statistics_to_text(stats_results, params, condition_pairs, ...
    all_data, freq_axis, output_file)
%EXPORT_TFR_STATISTICS_TO_TEXT Write TFR cluster-corrected statistics to text file.
%   Exports a detailed report of all cluster-corrected permutation statistics
%   from the TFR timeseries analysis for publication reference.
%
%   INPUTS:
%     stats_results   - struct.(comp_name) = FieldTrip stat struct
%     params          - parameter struct
%     condition_pairs - Nx3 cell: {cond1, cond2, label; ...}
%     all_data        - struct.(participant).(condition).{trials, freq, time}
%     freq_axis       - global frequency vector (for analysis-band selection)
%     output_file     - full path to output .txt file

    fprintf('Exporting statistics to %s\n', output_file);

    fid = fopen(output_file, 'w');
    if fid == -1
        error('Could not open file for writing: %s', output_file);
    end
    cleanup = onCleanup(@() fclose(fid));

    % --- Header ---
    fprintf(fid, '========================================\n');
    fprintf(fid, 'FIGURE 2: TFR TIME SERIES\n');
    fprintf(fid, 'CLUSTER-CORRECTED PERMUTATION STATISTICS\n');
    fprintf(fid, '========================================\n\n');
    fprintf(fid, 'Generated: %s\n\n', datestr(now));

    % --- Analysis parameters ---
    fprintf(fid, 'ANALYSIS PARAMETERS\n');
    fprintf(fid, '-------------------\n');
    fprintf(fid, 'ROI electrodes: %s\n', strjoin(params.roi_electrodes, ', '));
    fprintf(fid, 'Conditions: %s\n', strjoin(params.conditions, ', '));
    fprintf(fid, 'Participants: %d (%s ... %s)\n', length(params.participants), ...
        params.participants{1}, params.participants{end});
    fprintf(fid, 'Grand average weighting: %s\n\n', params.grand_avg_weighting);

    fprintf(fid, 'Time-frequency ranges:\n');
    fprintf(fid, '  Display frequency:  %.0f - %.0f Hz\n', params.freq_range_plot);
    fprintf(fid, '  Analysis frequency: %.0f - %.0f Hz\n', params.freq_range_analysis);
    fprintf(fid, '  Time range:         %.2f - %.2f s\n\n', params.time_range);

    fprintf(fid, 'Statistical parameters:\n');
    fprintf(fid, '  Significance level (alpha): %.3f\n', params.stats_alpha);
    fprintf(fid, '  Cluster-forming threshold:  %.3f\n', params.cluster_alpha);
    fprintf(fid, '  Number of permutations:     %d\n', params.n_permutations);
    fprintf(fid, '  dB transform applied:       %s\n', mat2str(params.apply_db_transform));
    fprintf(fid, '  Electrode filtering mode:   %s\n\n', params.electrode_filtering_mode);

    % --- Results per comparison ---
    for p = 1:size(condition_pairs, 1)
        cond1 = condition_pairs{p, 1};
        cond2 = condition_pairs{p, 2};
        label = condition_pairs{p, 3};
        comp_name = sprintf('%s_vs_%s', cond1, cond2);

        fprintf(fid, '\n========================================\n');
        fprintf(fid, 'COMPARISON: %s\n', label);
        fprintf(fid, '========================================\n\n');

        if ~isfield(stats_results, comp_name)
            fprintf(fid, 'No statistics available for this comparison.\n');
            continue;
        end

        stat = stats_results.(comp_name);

        % Basic info
        fprintf(fid, 'Frequency range tested: %.1f - %.1f Hz (%d bins)\n', ...
            stat.freq(1), stat.freq(end), length(stat.freq));
        fprintf(fid, 'Time range tested:      %.3f - %.3f s (%d bins)\n', ...
            stat.time(1), stat.time(end), length(stat.time));

        % Design info
        if isfield(stat, 'cfg') && isfield(stat.cfg, 'design')
            n_subj = max(stat.cfg.design(2,:));
            fprintf(fid, 'Number of subjects:     %d\n\n', n_subj);
        else
            fprintf(fid, '\n');
        end

        % Full-window effect size (a priori band, UNBIASED)
        write_full_window_effect_size(fid, all_data, params.participants, ...
            cond1, cond2, freq_axis, params.freq_range_analysis);

        % T-statistic summary
        t_vals = stat.stat(:);
        t_vals = t_vals(isfinite(t_vals));
        if ~isempty(t_vals)
            fprintf(fid, 'T-STATISTIC SUMMARY:\n');
            fprintf(fid, '  Range: [%.3f, %.3f]\n', min(t_vals), max(t_vals));
            fprintf(fid, '  Mean:  %.3f\n', mean(t_vals));
            fprintf(fid, '  Significant TF-pixels (p < %.3f): %d / %d (%.1f%%)\n\n', ...
                params.stats_alpha, sum(stat.prob(:) < params.stats_alpha), ...
                numel(stat.prob), 100*sum(stat.prob(:) < params.stats_alpha)/numel(stat.prob));
        end

        % Positive clusters
        write_clusters(fid, stat, params.stats_alpha, 'POSITIVE', ...
            'posclusters', 'posclusterslabelmat', 'posdistribution', ...
            all_data, params.participants, cond1, cond2);

        % Negative clusters
        write_clusters(fid, stat, params.stats_alpha, 'NEGATIVE', ...
            'negclusters', 'negclusterslabelmat', 'negdistribution', ...
            all_data, params.participants, cond1, cond2);
    end

    fprintf(fid, '\n========================================\n');
    fprintf(fid, 'END OF STATISTICS REPORT\n');
    fprintf(fid, '========================================\n');
end


%% ========================================================================
%  LOCAL HELPERS
%  ========================================================================

function write_clusters(fid, stat, alpha, direction, cluster_field, label_field, dist_field, ...
    all_data, participants, cond1, cond2)
% Write cluster information for one direction (positive/negative).

    fprintf(fid, '%s CLUSTERS:\n', direction);

    if ~isfield(stat, cluster_field) || isempty(stat.(cluster_field))
        fprintf(fid, '  No %s clusters found.\n\n', lower(direction));
        return;
    end

    clusters = stat.(cluster_field);
    n_sig = sum([clusters.prob] < alpha);
    fprintf(fid, '  Total: %d clusters, %d significant (p < %.3f)\n', ...
        length(clusters), n_sig, alpha);

    % Null distribution summary
    if isfield(stat, dist_field) && ~isempty(stat.(dist_field))
        null_dist = stat.(dist_field);
        null_dist = null_dist(isfinite(null_dist));
        if ~isempty(null_dist)
            fprintf(fid, '  Null distribution: median=%.2f, 95th pctl=%.2f, max=%.2f\n', ...
                median(null_dist), prctile(null_dist, 95), max(null_dist));
        end
    end
    fprintf(fid, '\n');

    for ci = 1:length(clusters)
        is_sig = clusters(ci).prob < alpha;

        if is_sig
            fprintf(fid, '  --- Cluster %d (SIGNIFICANT) ---\n', ci);
        else
            fprintf(fid, '  --- Cluster %d (not significant) ---\n', ci);
        end

        fprintf(fid, '  p-value:          %.4f\n', clusters(ci).prob);
        fprintf(fid, '  Cluster statistic: %.2f\n', clusters(ci).clusterstat);

        % Count and describe TF extent
        if isfield(stat, label_field)
            mask = squeeze(stat.(label_field) == ci);
            n_pixels = sum(mask(:));
            fprintf(fid, '  TF-pixels:        %d\n', n_pixels);

            if n_pixels > 0
                freq_involved = stat.freq(any(mask, 2));
                time_involved = stat.time(any(mask, 1));
                fprintf(fid, '  Frequency extent:  %.1f - %.1f Hz\n', ...
                    min(freq_involved), max(freq_involved));
                fprintf(fid, '  Time extent:       %.3f - %.3f s\n', ...
                    min(time_involved), max(time_involved));

                % Peak t-value within cluster
                t_in_cluster = stat.stat(stat.(label_field) == ci);
                if strcmp(direction, 'POSITIVE')
                    peak_t = max(t_in_cluster);
                else
                    peak_t = min(t_in_cluster);
                end
                fprintf(fid, '  Peak t-value:      %.3f\n', peak_t);

                % Time-frequency profile: how many freq bins active per time point
                n_freq_per_time = sum(mask, 1);
                active_times = stat.time(n_freq_per_time > 0);
                if ~isempty(active_times)
                    fprintf(fid, '  Active time bins:  %d (%.3f - %.3f s)\n', ...
                        length(active_times), active_times(1), active_times(end));
                end

                % Cluster-restricted Cohen's d (DESCRIPTIVE -- selection-biased)
                is_sig = clusters(ci).prob < alpha;
                if is_sig
                    [d_clust, n_pairs, mean_diff, sd_diff] = compute_cluster_cohens_d( ...
                        all_data, participants, cond1, cond2, mask, stat.freq, stat.time);
                    if ~isnan(d_clust)
                        fprintf(fid, '  Within-cluster Cohen''s d (DESCRIPTIVE, biased upward):\n');
                        fprintf(fid, '    d = %.3f   (mean diff = %.4f, SD diff = %.4f, N = %d)\n', ...
                            d_clust, mean_diff, sd_diff, n_pairs);
                        fprintf(fid, '    NOTE: This d is computed on the same data points used to\n');
                        fprintf(fid, '          define the cluster, so it is biased upward and is NOT\n');
                        fprintf(fid, '          a generalizable population effect size. Use the full-\n');
                        fprintf(fid, '          window a priori band d above for inference.\n');
                    end
                end
            end
        end
        fprintf(fid, '\n');
    end
end


function write_full_window_effect_size(fid, all_data, participants, cond1, cond2, ...
    freq_axis, freq_range_analysis)
% Compute and write the a priori band-averaged paired Cohen's d (UNBIASED).

    analysis_fi = freq_axis >= freq_range_analysis(1) & ...
                  freq_axis <= freq_range_analysis(2);
    fa_lo = freq_axis(find(analysis_fi, 1));
    fa_hi = freq_axis(find(analysis_fi, 1, 'last'));

    n_subj = length(participants);
    means1 = nan(n_subj, 1);
    means2 = nan(n_subj, 1);

    for si = 1:n_subj
        subj = participants{si};
        if ~isfield(all_data, subj), continue; end
        if isfield(all_data.(subj), cond1)
            means1(si) = subject_band_mean(all_data.(subj).(cond1), fa_lo, fa_hi);
        end
        if isfield(all_data.(subj), cond2)
            means2(si) = subject_band_mean(all_data.(subj).(cond2), fa_lo, fa_hi);
        end
    end

    valid = ~isnan(means1) & ~isnan(means2);
    diff_vals = means1(valid) - means2(valid);
    n_pairs = sum(valid);

    fprintf(fid, 'FULL-WINDOW EFFECT SIZE (a priori band, UNBIASED):\n');
    fprintf(fid, '  Analysis band:    %.1f - %.1f Hz\n', freq_range_analysis);
    fprintf(fid, '  N pairs:          %d\n', n_pairs);
    if n_pairs >= 2 && std(diff_vals) > 0
        d = mean(diff_vals) / std(diff_vals);
        fprintf(fid, '  Mean difference:  %.4f\n', mean(diff_vals));
        fprintf(fid, '  SD of difference: %.4f\n', std(diff_vals));
        fprintf(fid, '  Cohen''s d:        %.3f\n', d);
    else
        fprintf(fid, '  Cohen''s d:        n/a (insufficient data)\n');
    end
    fprintf(fid, '\n');
end


function m = subject_band_mean(cond_data, fa_lo, fa_hi)
% Per-subject mean over the a priori frequency band and full time window.

    local_freq = cond_data.freq;
    local_fi = local_freq >= fa_lo & local_freq <= fa_hi;
    if ~any(local_fi)
        m = NaN;
        return;
    end
    subj_mean_tfr = squeeze(mean(cond_data.trials, 1, 'omitnan'));  % [freq x time]
    m = mean(subj_mean_tfr(local_fi, :), 'all', 'omitnan');
end

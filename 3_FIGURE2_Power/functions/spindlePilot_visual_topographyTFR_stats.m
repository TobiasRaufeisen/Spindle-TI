function stats_results = spindlePilot_visual_topographyTFR_stats(compute_results, config)
%SPINDLEPILOT_VISUAL_TOPOGRAPHYTFR_STATS Run cluster-corrected statistics.
%
%   stats_results = spindlePilot_visual_topographyTFR_stats(compute_results, config)
%   performs cluster-corrected subject-level statistics on the precomputed data.
%   If COMPUTE_RESULTS is empty, results are loaded from config.io.compute_output_file.

    if nargin < 2 || isempty(config)
        config = spindlePilot_visual_topographyTFR_config();
    end

    if nargin < 1 || isempty(compute_results)
        compute_results = load_compute_results(config.io.compute_output_file);
    end

    if isempty(compute_results)
        error('Compute results are required for statistics.');
    end

    stats_params = config.stats;
    if isfield(stats_params, 'run') && ~stats_params.run
        fprintf('Statistics disabled via config. Returning empty results.\\n');
        stats_results = struct();
        return;
    end

    initialize_fieldtrip(config.paths.fieldtrip);

    fprintf('\\n=== POWER TFR TOPOGRAPHY: STATS ===\\n');

    stats_results = run_cluster_corrected_lme(compute_results.all_data_topo, ...
        compute_results.participants, compute_results.conditions, ...
        compute_results.matched_channels, compute_results.topo_params, ...
        compute_results.layout, stats_params, compute_results.freq_axis, compute_results.time_axis);

    if ~isempty(stats_results)
        plot_cluster_statistics(stats_results, compute_results.matched_channels, ...
            compute_results.layout, stats_params, compute_results.topo_data_computed);
    end
end

function initialize_fieldtrip(ft_path)
    if exist(ft_path, 'dir')
        addpath(ft_path);
    end
    if exist('ft_defaults', 'file')
        try
            ft_defaults;
        catch ME
            warning('Failed to run ft_defaults: %s', ME.message);
        end
    else
        warning('FieldTrip not found on path. Layout/plots may fail.');
    end
end

function compute_results = load_compute_results(result_file)
    compute_results = struct();
    if nargin == 0 || isempty(result_file) || ~exist(result_file, 'file')
        warning('Compute result file not found. Provide results directly or set config.io.compute_output_file.');
        return;
    end
    loaded = load(result_file, 'compute_results');
    if isfield(loaded, 'compute_results')
        compute_results = loaded.compute_results;
    else
        warning('File %s does not contain compute_results.', result_file);
    end
end

function stats_results = run_cluster_corrected_lme(all_data_topo, participants, conditions, ...
    channels, topo_params, layout, stats_params, freq_axis, time_axis)

    fprintf('\n=== CLUSTER-CORRECTED STATISTICS (Subject-Level Permutation) ===\n');
    fprintf('Method: Subject-level sign-flip permutation with consistent p-value thresholding\n');

    stats_results = struct();
    n_windows = size(topo_params.time_freq_windows, 1);

    % Build condition pairs
    pair_indices = nchoosek(1:length(conditions), 2);
    n_pairs = size(pair_indices, 1);

    stats_results.pair_labels = cell(n_pairs, 1);
    for p = 1:n_pairs
        stats_results.pair_labels{p} = sprintf('%s vs %s', ...
            conditions{pair_indices(p,1)}, conditions{pair_indices(p,2)});
    end

    % Create adjacency matrix for cluster analysis
    adjacency = create_adjacency_matrix_tfr(channels, layout);

    % Process each time-frequency window
    for w = 1:n_windows
        freq_win = [topo_params.time_freq_windows{w, 1}, topo_params.time_freq_windows{w, 2}];
        time_win = [topo_params.time_freq_windows{w, 3}, topo_params.time_freq_windows{w, 4}];
        win_label = topo_params.time_freq_windows{w, 5};

        fprintf('\n--- Processing window: %s (%.1f-%.1f Hz, %.1f-%.1f s) ---\n', ...
            win_label, freq_win(1), freq_win(2), time_win(1), time_win(2));

        % Prepare subject-level data in MATRIX form for permutation testing
        % Returns: diff_matrix [n_subjects x n_channels] for each condition pair
        [subject_diff_data, valid_subjects] = prepare_subject_difference_matrix(...
            all_data_topo, participants, conditions, channels, ...
            freq_axis, time_axis, freq_win, time_win, pair_indices);

        if isempty(valid_subjects) || length(valid_subjects) < 3
            fprintf('  Insufficient subjects for permutation analysis (need >= 3)\n');
            continue;
        end

        fprintf('  Valid subjects for analysis: %d\n', length(valid_subjects));

        n_channels = length(channels);

        % Store per-electrode results (from observed data)
        window_result = struct();
        window_result.freq_win = freq_win;
        window_result.time_win = time_win;

        % Initialize storage
        p_vals = nan(n_channels, n_pairs);
        t_stats = nan(n_channels, n_pairs);
        est_diffs = nan(n_channels, n_pairs);
        n_subj_used = nan(n_channels, n_pairs);
        converged = true(n_channels, n_pairs);

        % Perform cluster-based correction for each comparison
        cluster_results = struct();

        for p = 1:n_pairs
            c1 = conditions{pair_indices(p,1)};
            c2 = conditions{pair_indices(p,2)};
            comp_name = sprintf('%s_vs_%s', c1, c2);

            fprintf('  Processing: %s\n', comp_name);

            % Get difference matrix for this comparison [n_subjects x n_channels]
            if ~isfield(subject_diff_data, comp_name)
                fprintf('    No data available for this comparison\n');
                cluster_results.(comp_name) = create_empty_cluster_result(comp_name, nan(n_channels, 1), 0);
                continue;
            end

            diff_matrix = subject_diff_data.(comp_name).diff_matrix;
            subj_list = subject_diff_data.(comp_name).subjects;
            n_subj = size(diff_matrix, 1);

            if n_subj < 3
                fprintf('    Insufficient subjects (%d < 3)\n', n_subj);
                cluster_results.(comp_name) = create_empty_cluster_result(comp_name, nan(n_channels, 1), n_subj);
                continue;
            end

            % ================================================================
            % OBSERVED STATISTICS: One-sample t-test at each electrode
            % ================================================================
            [obs_t, obs_p] = compute_electrode_ttest(diff_matrix);

            % Store for output
            t_stats(:, p) = obs_t;
            p_vals(:, p) = obs_p;
            est_diffs(:, p) = mean(diff_matrix, 1, 'omitnan')';
            n_subj_used(:, p) = sum(~isnan(diff_matrix), 1)';
            converged(:, p) = ~isnan(obs_t);

            % ================================================================
            % OBSERVED CLUSTERS: threshold by p < cluster_alpha
            % ================================================================
            sig_mask = (obs_p < stats_params.cluster_alpha) & ~isnan(obs_p);
            n_sig_channels = sum(sig_mask);
            fprintf('    Observed: %d significant electrodes (p < %.3f)\n', ...
                n_sig_channels, stats_params.cluster_alpha);

            % Find observed clusters
            all_clusters = find_clusters_tfr(sig_mask, adjacency);

            if isempty(all_clusters)
                fprintf('    No clusters found\n');
                cluster_results.(comp_name) = create_empty_cluster_result(comp_name, obs_t, n_subj);
                cluster_results.(comp_name).obs_p_values = obs_p;
                cluster_results.(comp_name).mean_differences = est_diffs(:, p);
                continue;
            end

            % Filter by minimum cluster size
            observed_clusters = {};
            for i = 1:numel(all_clusters)
                if length(all_clusters{i}) >= stats_params.min_cluster_size
                    observed_clusters{end+1} = all_clusters{i};
                end
            end

            if isempty(observed_clusters)
                fprintf('    No clusters meeting minimum size (%d electrodes)\n', ...
                    stats_params.min_cluster_size);
                cluster_results.(comp_name) = create_empty_cluster_result(comp_name, obs_t, n_subj);
                cluster_results.(comp_name).obs_p_values = obs_p;
                cluster_results.(comp_name).mean_differences = est_diffs(:, p);
                continue;
            end

            % Compute observed cluster statistics (sum of t-values, preserving sign)
            % Using sum of t-values (not absolute) to be directional
            cluster_stats = zeros(1, numel(observed_clusters));
            for i = 1:numel(observed_clusters)
                cluster_stats(i) = sum(abs(obs_t(observed_clusters{i})));
            end
            % ================================================================
            % PERMUTATION TESTING: Subject-level sign flips (ROW-WISE)
            % ================================================================
            fprintf('    Running %d subject-level permutations...\n', stats_params.n_permutations);

            max_cluster_stats = zeros(stats_params.n_permutations, 1);

            for perm = 1:stats_params.n_permutations
                % ==========================================================
                % SUBJECT-LEVEL SIGN FLIP: flip each subject's entire topography
                % ==========================================================
                % IMPORTANT: sign_flips must be [n_subj x 1] to apply to subject rows
                sign_flips = randsample([-1, 1], n_subj, true);
                sign_flips = sign_flips(:);  % FORCE COLUMN: [n_subj x 1]

                % Apply sign flips row-wise: [n_subj x n_chan]
                perm_diff_matrix = bsxfun(@times, diff_matrix, sign_flips);

                % ==========================================================
                % RECOMPUTE ELECTRODE-WISE ONE-SAMPLE T-TESTS
                % ==========================================================
                [perm_t, perm_p] = compute_electrode_ttest(perm_diff_matrix);

                % ==========================================================
                % CONSISTENT THRESHOLDING: p < cluster_alpha
                % ==========================================================
                perm_sig_mask = (perm_p < stats_params.cluster_alpha) & ~isnan(perm_p);

                % Find clusters in permuted data
                all_perm_clusters = find_clusters_tfr(perm_sig_mask, adjacency);

                % Filter by minimum cluster size
                perm_clusters = {};
                if ~isempty(all_perm_clusters)
                    for i = 1:numel(all_perm_clusters)
                        if numel(all_perm_clusters{i}) >= stats_params.min_cluster_size
                            perm_clusters{end+1} = all_perm_clusters{i};
                        end
                    end
                end

                % Max cluster mass for this permutation
                if ~isempty(perm_clusters)
                    perm_cluster_stats = zeros(1, numel(perm_clusters));
                    for i = 1:numel(perm_clusters)
                        perm_cluster_stats(i) = sum(abs(perm_t(perm_clusters{i})));
                    end
                    max_cluster_stats(perm) = max(perm_cluster_stats);
                end
            end



            % ================================================================
            % CLUSTER P-VALUES: proportion of permutations with larger max cluster
            % ================================================================
            cluster_p_values = zeros(size(cluster_stats));
            for i = 1:numel(cluster_stats)
                % Add 1 to numerator and denominator for conservative estimate
                cluster_p_values(i) = (sum(max_cluster_stats >= cluster_stats(i)) + 1) / ...
                                      (stats_params.n_permutations + 1);
            end

            % Determine significance
            significant_clusters = find(cluster_p_values < stats_params.alpha);

            % Store results
            cluster_results.(comp_name) = struct(...
                'comparison', comp_name, ...
                'observed_clusters', {observed_clusters}, ...
                'cluster_stats', cluster_stats, ...
                'cluster_p_values', cluster_p_values, ...
                'significant_clusters', significant_clusters, ...
                'max_cluster_null', max_cluster_stats, ...
                'n_subjects', n_subj, ...
                'obs_t_stats', obs_t, ...
                'obs_p_values', obs_p, ...
                'mean_differences', est_diffs(:, p));

            fprintf('    Found %d clusters (%d significant at p < %.3f)\n', ...
                numel(observed_clusters), numel(significant_clusters), stats_params.alpha);

            % Print significant cluster details
            if ~isempty(significant_clusters)
                fprintf('    --- Significant Clusters ---\n');
                for i = 1:length(significant_clusters)
                    cluster_idx = significant_clusters(i);
                    ch_idx = observed_clusters{cluster_idx};
                    ch_names = channels(ch_idx);
                    fprintf('      Cluster %d: mass=%.2f, p=%.4f, electrodes=%s\n', ...
                        cluster_idx, cluster_stats(cluster_idx), ...
                        cluster_p_values(cluster_idx), strjoin(ch_names, ', '));
                end
            end

            % Report null distribution statistics
            fprintf('    Null distribution: median=%.2f, 95th pctl=%.2f, max=%.2f\n', ...
                median(max_cluster_stats), prctile(max_cluster_stats, 95), max(max_cluster_stats));
        end

        % Store per-electrode results
        window_result.p_values = p_vals;
        window_result.t_stats = t_stats;
        window_result.mean_differences = est_diffs;
        window_result.n_subjects = n_subj_used;
        window_result.converged = converged;

        % Store window results
        stats_results.(win_label) = struct();
        stats_results.(win_label).electrode_results = window_result;
        stats_results.(win_label).cluster_results = cluster_results;
    end

    stats_results.conditions = conditions;
    stats_results.pair_indices = pair_indices;
    stats_results.channels = channels;

    fprintf('\nCluster-corrected analysis complete.\n');
end


function [subject_diff_data, valid_subjects] = prepare_subject_difference_matrix(...
    all_data_topo, participants, conditions, channels, ...
    freq_axis, time_axis, freq_win, time_win, pair_indices)
    % Prepare subject-level DIFFERENCE matrices for permutation testing
    %
    % For each condition pair, computes the difference (cond1 - cond2) for each
    % subject at each electrode. This is the data structure needed for subject-level
    % sign-flip permutation testing.
    %
    % OUTPUT:
    %   subject_diff_data - struct with fields for each comparison:
    %       .(comp_name).diff_matrix: [n_subjects x n_channels] difference values
    %       .(comp_name).subjects: cell array of subject IDs included
    %   valid_subjects - cell array of subjects with data in any condition

    % Find indices for time-frequency window
    freq_idx = freq_axis >= freq_win(1) & freq_axis <= freq_win(2);
    time_idx = time_axis >= time_win(1) & time_axis <= time_win(2);

    if ~any(freq_idx) || ~any(time_idx)
        subject_diff_data = [];
        valid_subjects = {};
        return;
    end

    n_channels = length(channels);
    n_pairs = size(pair_indices, 1);

    % First pass: collect power values for each subject/condition/channel
    subject_power = struct();  % subject_power.(subject).(condition) = [1 x n_channels]

    for p = 1:length(participants)
        participant = participants{p};

        if ~isfield(all_data_topo, participant)
            continue;
        end

        subject_power.(participant) = struct();

        for c = 1:length(conditions)
            condition = conditions{c};

            if ~isfield(all_data_topo.(participant), condition)
                continue;
            end

            % Get trial data: [trials x channels x freq x time]
            trial_data = all_data_topo.(participant).(condition).trials;
            data_channels = all_data_topo.(participant).(condition).channels;

            if isempty(trial_data)
                continue;
            end

            % Get summarization method
            if isfield(all_data_topo.(participant).(condition), 'summary_method')
                summary_method = all_data_topo.(participant).(condition).summary_method;
                trim_percent = all_data_topo.(participant).(condition).trim_percent;
            else
                summary_method = 'mean';
                trim_percent = 10;
            end

            num_trials = size(trial_data, 1);

            % Extract power for each channel using trial summarization
            power_vec = nan(1, n_channels);
            for ch = 1:n_channels
                ch_idx = find(strcmp(data_channels, channels{ch}), 1);
                if ~isempty(ch_idx)
                    % Extract channel data: [trials x freq_subset x time_subset]
                    ch_data = squeeze(trial_data(:, ch_idx, freq_idx, time_idx));

                    % Compute full-trial power per trial
                    if ndims(ch_data) == 3
                        trial_powers = squeeze(mean(mean(ch_data, 3, 'omitnan'), 2, 'omitnan'));
                    elseif ismatrix(ch_data) && size(ch_data, 1) == num_trials
                        trial_powers = mean(ch_data, 2, 'omitnan');
                    else
                        trial_powers = ch_data(:);
                    end

                    trial_powers = trial_powers(~isnan(trial_powers));

                    if ~isempty(trial_powers)
                        % Summarize across trials
                        switch summary_method
                            case 'trimmed_mean'
                                power_vec(ch) = trimmean(trial_powers, 2 * trim_percent);
                            case 'median'
                                power_vec(ch) = median(trial_powers, 'omitnan');
                            otherwise
                                power_vec(ch) = mean(trial_powers, 'omitnan');
                        end
                    end
                end
            end

            subject_power.(participant).(condition) = power_vec;
        end
    end

    % Second pass: compute differences for each pair
    subject_diff_data = struct();
    valid_subjects = {};

    for p_idx = 1:n_pairs
        c1 = conditions{pair_indices(p_idx, 1)};
        c2 = conditions{pair_indices(p_idx, 2)};
        comp_name = sprintf('%s_vs_%s', c1, c2);

        % Find subjects with BOTH conditions
        diff_rows = {};
        subj_list = {};

        for p = 1:length(participants)
            participant = participants{p};

            if ~isfield(subject_power, participant)
                continue;
            end

            if isfield(subject_power.(participant), c1) && isfield(subject_power.(participant), c2)
                power1 = subject_power.(participant).(c1);
                power2 = subject_power.(participant).(c2);

                % Compute difference: c1 - c2
                diff_vec = power1 - power2;

                % Only include if subject has valid data
                if any(~isnan(diff_vec))
                    diff_rows{end+1} = diff_vec;
                    subj_list{end+1} = participant;

                    if ~ismember(participant, valid_subjects)
                        valid_subjects{end+1} = participant;
                    end
                end
            end
        end

        if ~isempty(diff_rows)
            % Convert to matrix [n_subjects x n_channels]
            diff_matrix = vertcat(diff_rows{:});

            subject_diff_data.(comp_name) = struct(...
                'diff_matrix', diff_matrix, ...
                'subjects', {subj_list});
        end
    end
end


function [t_vals, p_vals] = compute_electrode_ttest(diff_matrix)
    % Compute one-sample t-test against zero at each electrode
    %
    % INPUT:
    %   diff_matrix: [n_subjects x n_channels] matrix of condition differences
    %
    % OUTPUT:
    %   t_vals: [n_channels x 1] t-statistics
    %   p_vals: [n_channels x 1] two-tailed p-values

    [n_subj, n_channels] = size(diff_matrix);

    t_vals = nan(n_channels, 1);
    p_vals = nan(n_channels, 1);

    for ch = 1:n_channels
        x = diff_matrix(:, ch);
        valid = ~isnan(x);
        n = sum(valid);

        if n < 3
            continue;
        end

        x_valid = x(valid);
        m = mean(x_valid);
        s = std(x_valid);
        se = s / sqrt(n);

        if se > 0
            t_vals(ch) = m / se;
            df = n - 1;
            % Two-tailed p-value
            p_vals(ch) = 2 * (1 - tcdf(abs(t_vals(ch)), df));
        end
    end
end


function adjacency = create_adjacency_matrix_tfr(channels, layout)
    % Create adjacency matrix using FieldTrip's neighbour definition

    fprintf('Creating adjacency matrix using FieldTrip neighbours...\n');

    % Prepare FieldTrip neighbours structure
    cfg_nb = [];
    cfg_nb.method = 'distance';
    cfg_nb.neighbourdist = 0.25;  % Distance threshold
    cfg_nb.layout = layout;
    cfg_nb.feedback = 'no';

    try
        neighbours = ft_prepare_neighbours(cfg_nb);
    catch ME
        warning('TFR:NeighboursFailed', 'ft_prepare_neighbours failed: %s', ME.message);
        % Fallback: create simple distance-based adjacency
        adjacency = create_distance_adjacency(channels, layout, 0.2);
        return;
    end

    % Convert neighbours structure to adjacency matrix
    n_channels = length(channels);
    adjacency = zeros(n_channels, n_channels);

    for i = 1:n_channels
        % Find this channel in neighbours structure
        nb_idx = find(strcmpi({neighbours.label}, channels{i}));
        if isempty(nb_idx)
            continue;
        end

        % Get neighbour labels
        nb_labels = neighbours(nb_idx).neighblabel;

        % Mark neighbours in adjacency matrix
        for j = 1:length(nb_labels)
            nb_chan_idx = find(strcmpi(channels, nb_labels{j}));
            if ~isempty(nb_chan_idx)
                adjacency(i, nb_chan_idx) = 1;
                adjacency(nb_chan_idx, i) = 1;  % Symmetric
            end
        end
    end

    % Report neighbour statistics
    neighbors_per_chan = sum(adjacency, 2);
    fprintf('  Mean neighbors per electrode: %.1f\n', mean(neighbors_per_chan));
    fprintf('  Range: %d to %d neighbors\n', min(neighbors_per_chan), max(neighbors_per_chan));
    fprintf('  Electrodes with 0 neighbors: %d\n', sum(neighbors_per_chan == 0));
end


function adjacency = create_distance_adjacency(channels, layout, dist_threshold)
    % Fallback: create adjacency based on layout positions

    n_channels = length(channels);
    adjacency = zeros(n_channels, n_channels);

    for i = 1:n_channels
        ch_i_idx = find(strcmpi(layout.label, channels{i}), 1);
        if isempty(ch_i_idx)
            continue;
        end
        pos_i = layout.pos(ch_i_idx, :);

        for j = (i+1):n_channels
            ch_j_idx = find(strcmpi(layout.label, channels{j}), 1);
            if isempty(ch_j_idx)
                continue;
            end
            pos_j = layout.pos(ch_j_idx, :);

            dist = sqrt(sum((pos_i - pos_j).^2));
            if dist <= dist_threshold
                adjacency(i, j) = 1;
                adjacency(j, i) = 1;
            end
        end
    end
end


function clusters = find_clusters_tfr(mask, adjacency)
    % Find connected components (clusters) in adjacency graph

    n_channels = length(mask);
    visited = false(n_channels, 1);
    clusters = {};

    for i = 1:n_channels
        if mask(i) && ~visited(i)
            cluster = [];
            stack = i;

            while ~isempty(stack)
                current = stack(end);
                stack(end) = [];

                if visited(current)
                    continue;
                end

                visited(current) = true;
                cluster = [cluster, current];

                % Find unvisited neighbors that are also in mask
                neighbors = find(adjacency(current, :) & mask(:)' & ~visited(:)');
                stack = [stack, neighbors];
            end

            if ~isempty(cluster)
                clusters{end+1} = cluster;
            end
        end
    end
end


function result = create_empty_cluster_result(comp_name, obs_t, n_subj)
    % Create empty cluster result structure

    if nargin < 3
        n_subj = 0;
    end

    result = struct(...
        'comparison', comp_name, ...
        'observed_clusters', {{}}, ...
        'cluster_stats', [], ...
        'cluster_p_values', [], ...
        'significant_clusters', [], ...
        'critical_value', NaN, ...
        'n_subjects', n_subj, ...
        'obs_t_stats', obs_t, ...
        'obs_p_values', [], ...
        'mean_differences', []);
end


function plot_cluster_statistics(stats_results, channels, layout, stats_params, topo_data_computed)
    % Plot statistical results with cluster significance markers
    %
    % Creates:
    %   1. T-statistic topoplots for each comparison with significant cluster markers
    %   2. Difference topoplots for each comparison with significant cluster markers
    %   3. Summary table of significant clusters
    %
    % All t-stat plots share the same colorbar scaling
    % All difference plots share the same colorbar scaling

    fprintf('\n=== PLOTTING CLUSTER STATISTICS ===\n');

    % Process each time-frequency window
    window_labels = fieldnames(stats_results);
    window_labels = window_labels(~ismember(window_labels, ...
        {'conditions', 'pair_indices', 'channels', 'pair_labels'}));

    for w = 1:length(window_labels)
        win_label = window_labels{w};

        if ~isfield(stats_results.(win_label), 'cluster_results')
            continue;
        end

        cluster_results = stats_results.(win_label).cluster_results;
        electrode_results = stats_results.(win_label).electrode_results;
        freq_win = electrode_results.freq_win;
        time_win = electrode_results.time_win;

        % Get trial count data if available
        topo_data_for_window = [];
        if nargin >= 5 && isfield(topo_data_computed, win_label)
            topo_data_for_window = topo_data_computed.(win_label).data;
        end

        fprintf('\nPlotting: %s\n', win_label);

        % ===================================================================
        % FIRST PASS: Determine global color limits for t-stats and differences
        % ===================================================================
        comp_names = fieldnames(cluster_results);

        all_t_stats = [];
        all_differences = [];

        for p = 1:length(comp_names)
            comp_name = comp_names{p};
            cluster_data = cluster_results.(comp_name);

            t_stats = cluster_data.obs_t_stats;
            valid_t_idx = ~isnan(t_stats);
            if sum(valid_t_idx) >= 4
                all_t_stats = [all_t_stats; t_stats(valid_t_idx)]; %#ok<AGROW>
            end

            mean_diffs = cluster_data.mean_differences;
            valid_diff_idx = ~isnan(mean_diffs);
            if sum(valid_diff_idx) >= 4
                all_differences = [all_differences; mean_diffs(valid_diff_idx)]; %#ok<AGROW>
            end
        end

        % Compute global symmetric limits for t-statistics
        if ~isempty(all_t_stats)
            max_abs_t = max(abs(all_t_stats));
            global_t_zlim = [-max_abs_t, max_abs_t];
        else
            global_t_zlim = [-1, 1];  % fallback
        end

        % Compute global symmetric limits for differences
        if ~isempty(all_differences)
            max_abs_diff = max(abs(all_differences));
            global_diff_zlim = [-max_abs_diff, max_abs_diff];
        else
            global_diff_zlim = [-1, 1];  % fallback
        end

        fprintf('Global t-stat color limits: [%.2f, %.2f]\n', global_t_zlim(1), global_t_zlim(2));
        fprintf('Global difference color limits: [%.4f, %.4f]\n', global_diff_zlim(1), global_diff_zlim(2));

        % ===================================================================
        % SECOND PASS: Plot t-statistics and differences with consistent scaling
        % ===================================================================
        for p = 1:length(comp_names)
            comp_name = comp_names{p};
            cluster_data = cluster_results.(comp_name);

            % Get t-statistics and differences
            t_stats = cluster_data.obs_t_stats;
            mean_diffs = cluster_data.mean_differences;
            valid_t_idx = ~isnan(t_stats);
            valid_diff_idx = ~isnan(mean_diffs);

            if sum(valid_t_idx) < 4
                fprintf('  Skipping %s: insufficient valid channels\n', comp_name);
                continue;
            end

            % Get significant cluster info
            sig_cluster_idx = cluster_data.significant_clusters;
            sig_electrodes = [];
            if ~isempty(sig_cluster_idx)
                for c = 1:length(sig_cluster_idx)
                    cluster_num = sig_cluster_idx(c);
                    ch_idx = cluster_data.observed_clusters{cluster_num};
                    sig_electrodes = [sig_electrodes; ch_idx(:)]; %#ok<AGROW>
                end
                sig_electrodes = unique(sig_electrodes);
            end

            n_sig = length(sig_cluster_idx);
            n_total = length(cluster_data.observed_clusters);

            % Extract condition names from comp_name (e.g., "x5HZ_vs_x1HZ")
            cond_parts = strsplit(comp_name, '_vs_');
            trial_info_str = '';
            if length(cond_parts) == 2 && ~isempty(topo_data_for_window)
                cond1 = cond_parts{1};
                cond2 = cond_parts{2};
                if isfield(topo_data_for_window, cond1) && isfield(topo_data_for_window, cond2)
                    trial_info_str = sprintf('\n%s: N=%d, %d trials | %s: N=%d, %d trials', ...
                        cond1, topo_data_for_window.(cond1).n_participants, topo_data_for_window.(cond1).n_trials, ...
                        cond2, topo_data_for_window.(cond2).n_participants, topo_data_for_window.(cond2).n_trials);
                end
            end

            % ===================================================================
            % PLOT 1: T-STATISTICS with significance markers
            % ===================================================================
            ft_data_t = struct();
            ft_data_t.label = channels(valid_t_idx);
            ft_data_t.avg = t_stats(valid_t_idx);
            ft_data_t.dimord = 'chan';
            ft_data_t.time = 1;

            figure('Position', [100, 100, 700, 600], 'Color', 'white');

            cfg = struct();
            cfg.layout = layout;
            cfg.parameter = 'avg';
            cfg.marker = 'on';
            cfg.markersymbol = '.';
            cfg.markersize = 8;
            cfg.markercolor = [0.3 0.3 0.3];
            cfg.style = 'straight';
            cfg.gridscale = 67;
            cfg.interplimits = 'head';
            cfg.comment = 'no';
            cfg.colorbar = 'yes';
            cfg.zlim = global_t_zlim;  % Use global limits

            ft_topoplotER(cfg, ft_data_t);

            % Use diverging colormap
            colormap(create_redblue_colormap(64));

            hold on;

            % Add markers for significant cluster electrodes
            if ~isempty(sig_electrodes)
                for i = 1:length(sig_electrodes)
                    ch_name = channels{sig_electrodes(i)};
                    chan_idx = find(strcmpi(layout.label, ch_name), 1);
                    if ~isempty(chan_idx)
                        pos = layout.pos(chan_idx, :);
                        plot(pos(1), pos(2), 'k*', 'MarkerSize', 18, 'LineWidth', 3);
                    end
                end
            end

            hold off;

            title(sprintf('T-statistics: %s\n%s (%.1f-%.1f Hz, %.1f-%.1f s)\n%d/%d significant clusters (\\alpha=%.2f)%s', ...
                strrep(comp_name, '_', ' '), win_label, ...
                freq_win(1), freq_win(2), time_win(1), time_win(2), ...
                n_sig, n_total, stats_params.alpha, trial_info_str), ...
                'FontSize', 10, 'FontWeight', 'bold');

            fprintf('  Plotted t-stats: %s (%d significant clusters)\n', comp_name, n_sig);

            % ===================================================================
            % PLOT 2: MEAN DIFFERENCES with significance markers
            % ===================================================================
            if sum(valid_diff_idx) >= 4
                ft_data_diff = struct();
                ft_data_diff.label = channels(valid_diff_idx);
                ft_data_diff.avg = mean_diffs(valid_diff_idx);
                ft_data_diff.dimord = 'chan';
                ft_data_diff.time = 1;

                figure('Position', [150, 150, 700, 600], 'Color', 'white');

                cfg = struct();
                cfg.layout = layout;
                cfg.parameter = 'avg';
                cfg.marker = 'on';
                cfg.markersymbol = '.';
                cfg.markersize = 8;
                cfg.markercolor = [0.3 0.3 0.3];
                cfg.style = 'straight';
                cfg.gridscale = 67;
                cfg.interplimits = 'head';
                cfg.comment = 'no';
                cfg.colorbar = 'yes';
                cfg.zlim = global_diff_zlim;  % Use global limits

                ft_topoplotER(cfg, ft_data_diff);

                % Use diverging colormap
                colormap(create_redblue_colormap(64));

                hold on;

                % Add markers for significant cluster electrodes (same as t-stat plot)
                if ~isempty(sig_electrodes)
                    for i = 1:length(sig_electrodes)
                        ch_name = channels{sig_electrodes(i)};
                        chan_idx = find(strcmpi(layout.label, ch_name), 1);
                        if ~isempty(chan_idx)
                            pos = layout.pos(chan_idx, :);
                            plot(pos(1), pos(2), 'k*', 'MarkerSize', 18, 'LineWidth', 3);
                        end
                    end
                end

                hold off;

                title(sprintf('Mean Difference: %s\n%s (%.1f-%.1f Hz, %.1f-%.1f s)\n%d/%d significant clusters (\\alpha=%.2f)%s', ...
                    strrep(comp_name, '_', ' '), win_label, ...
                    freq_win(1), freq_win(2), time_win(1), time_win(2), ...
                    n_sig, n_total, stats_params.alpha, trial_info_str), ...
                    'FontSize', 10, 'FontWeight', 'bold');

                fprintf('  Plotted differences: %s\n', comp_name);
            end
        end

        % Print summary table for this window
        print_cluster_summary_table(cluster_results, channels, win_label);
    end
end


function print_cluster_summary_table(cluster_results, channels, win_label)
    % Print summary table of cluster statistics

    fprintf('\n--- Cluster Summary: %s ---\n', win_label);
    fprintf('%-20s | %8s | %8s | %8s | %s\n', ...
        'Comparison', 'Clusters', 'Sig.', 'Best p', 'Significant Electrodes');
    fprintf('%s\n', repmat('-', 1, 90));

    comp_names = fieldnames(cluster_results);

    for p = 1:length(comp_names)
        comp_name = comp_names{p};
        cluster_data = cluster_results.(comp_name);

        n_clusters = length(cluster_data.observed_clusters);
        n_sig = length(cluster_data.significant_clusters);

        % Get best p-value
        if ~isempty(cluster_data.cluster_p_values)
            best_p = min(cluster_data.cluster_p_values);
        else
            best_p = NaN;
        end

        % Get significant electrode names
        sig_electrodes = {};
        if ~isempty(cluster_data.significant_clusters)
            for c = 1:length(cluster_data.significant_clusters)
                cluster_idx = cluster_data.significant_clusters(c);
                ch_idx = cluster_data.observed_clusters{cluster_idx};
                % Ensure channels are added as row for concatenation
                ch_names = channels(ch_idx);
                if iscolumn(ch_names)
                    ch_names = ch_names';
                end
                sig_electrodes = [sig_electrodes, ch_names];
            end
        end
        sig_str = strjoin(unique(sig_electrodes), ', ');
        if isempty(sig_str)
            sig_str = '-';
        end

        % Format p-value string (handle NaN case)
        if isnan(best_p)
            p_str = '     N/A';
        else
            p_str = sprintf('%8.4f', best_p);
        end

        fprintf('%-20s | %8d | %8d | %s | %s\n', ...
            strrep(comp_name, '_', ' '), n_clusters, n_sig, p_str, sig_str);
    end

    fprintf('\n');
end


function cm = create_redblue_colormap(m)
    % Create red-white-blue diverging colormap

    if nargin < 1, m = 256; end

    m1 = floor(m/2);

    % Blue to white
    r_bw = linspace(0, 1, m1)';
    g_bw = linspace(0, 1, m1)';
    b_bw = ones(m1, 1);

    % White to red
    r_wr = ones(m - m1, 1);
    g_wr = linspace(1, 0, m - m1)';
    b_wr = linspace(1, 0, m - m1)';

    cm = [r_bw, g_bw, b_bw; r_wr, g_wr, b_wr];
end

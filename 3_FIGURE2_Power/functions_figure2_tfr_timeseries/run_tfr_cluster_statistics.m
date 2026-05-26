function stats_results = run_tfr_cluster_statistics(all_data, participants, ...
    conditions, freq_axis, stats_cfg, freq_range_analysis)
% Run cluster-corrected permutation tests on participant-level TFR averages.
%
% Uses FieldTrip's dependent-samples T-test with cluster correction.
% Statistics are run on participant-level means (one observation per participant).
%
% INPUTS
%   all_data            - struct.(participant).(condition).{trials, freq, time}
%   participants        - cell array of participant IDs
%   conditions          - cell array of condition labels
%   freq_axis           - frequency vector
%   stats_cfg           - struct with fields: alpha, cluster_alpha, n_permutations, apply_db_transform
%   freq_range_analysis - [f_low, f_high] Hz for cluster test
%
% OUTPUT
%   stats_results - struct.(comp_name) = FieldTrip stat struct + full_tval field

ft_defaults;
stats_results = struct();

analysis_freq_idx = freq_axis >= freq_range_analysis(1) & freq_axis <= freq_range_analysis(2);
fprintf('  Analysis frequency range: %.0f-%.0f Hz (%d points)\n', ...
    freq_range_analysis(1), freq_range_analysis(2), sum(analysis_freq_idx));

common_time = find_common_time(all_data, participants, conditions);
if isempty(common_time)
    warning('No common time range found — cannot run statistics.');
    return;
end
fprintf('  Common time: %.2f to %.2f s (%d points)\n', ...
    common_time(1), common_time(end), length(common_time));

condition_pairs = nchoosek(1:length(conditions), 2);
apply_db = isfield(stats_cfg, 'apply_db_transform') && stats_cfg.apply_db_transform;

for pair = 1:size(condition_pairs, 1)
    cond1 = conditions{condition_pairs(pair, 1)};
    cond2 = conditions{condition_pairs(pair, 2)};
    comp_name = sprintf('%s_vs_%s', cond1, cond2);
    fprintf('    %s ... ', comp_name);

    [ft_data1, ft_data2] = prepare_ft_tfr_data(all_data, participants, ...
        cond1, cond2, freq_axis, analysis_freq_idx, common_time, apply_db);

    if isempty(ft_data1) || isempty(ft_data2)
        fprintf('insufficient data\n');
        continue;
    end

    n_subj = length(ft_data1);
    fprintf('%d participants\n', n_subj);

    cfg = [];
    cfg.channel          = 'all';
    cfg.latency          = 'all';
    cfg.frequency        = 'all';
    cfg.method           = 'montecarlo';
    cfg.statistic        = 'depsamplesT';
    cfg.correctm         = 'cluster';
    cfg.clusteralpha     = stats_cfg.cluster_alpha;
    cfg.clusterstatistic = 'maxsum';
    cfg.minnbchan        = 0;
    cfg.tail             = 0;
    cfg.clustertail      = 0;
    cfg.alpha            = stats_cfg.alpha;
    cfg.numrandomization = stats_cfg.n_permutations;
    cfg.design           = [ones(1,n_subj), 2*ones(1,n_subj); 1:n_subj, 1:n_subj];
    cfg.ivar = 1;
    cfg.uvar = 2;

    try
        stat = ft_freqstatistics(cfg, ft_data1{:}, ft_data2{:});

        % Full-range t-values for plotting
        stat.full_tval = compute_full_range_tvalues(all_data, participants, ...
            cond1, cond2, freq_axis, common_time, apply_db);

        stats_results.(comp_name) = stat;
        report_significant_clusters(stat, stats_cfg.alpha);
    catch ME
        fprintf('      FAILED: %s\n', ME.message);
    end
end
end


function report_significant_clusters(stat, alpha)
% Print counts of significant positive and negative clusters.
    if isfield(stat, 'posclusters') && ~isempty(stat.posclusters)
        n = sum([stat.posclusters.prob] < alpha);
        if n > 0, fprintf('      %d significant positive cluster(s)\n', n); end
    end
    if isfield(stat, 'negclusters') && ~isempty(stat.negclusters)
        n = sum([stat.negclusters.prob] < alpha);
        if n > 0, fprintf('      %d significant negative cluster(s)\n', n); end
    end
end

function [clusters, cluster_stats] = ps_find_freq_clusters(t_values, threshold, direction)
%PS_FIND_FREQ_CLUSTERS Find contiguous clusters of supra-threshold t-values.
%
%   [clusters, cluster_stats] = ps_find_freq_clusters(t_values, threshold, direction)
%
%   Inputs:
%     t_values  - 1D vector of t-statistics (one per frequency bin)
%     threshold - absolute t-value threshold
%     direction - 'positive': find bins where t > threshold
%                 'negative': find bins where t < threshold
%
%   Outputs:
%     clusters      - cell array of index vectors, one per cluster
%     cluster_stats - sum of t-values within each cluster

    if strcmp(direction, 'positive')
        supra = t_values > threshold;
    else
        supra = t_values < threshold;
    end

    clusters = {};
    cluster_stats = [];

    if ~any(supra)
        return;
    end

    % Find contiguous runs
    d = diff([0, double(supra), 0]);
    starts = find(d == 1);
    ends   = find(d == -1) - 1;

    for i = 1:length(starts)
        idx = starts(i):ends(i);
        clusters{end+1} = idx; %#ok<AGROW>
        cluster_stats(end+1) = sum(t_values(idx)); %#ok<AGROW>
    end
end

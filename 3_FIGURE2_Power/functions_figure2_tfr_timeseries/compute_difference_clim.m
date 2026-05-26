function clim_diff = compute_difference_clim(grand_avg_plot, stats_results, condition_pairs, plot_tvalues)
% Compute symmetric color limits for difference or t-value plots.
%
% INPUTS
%   grand_avg_plot  - struct.(condition) = [freq x time] (for dB diffs)
%   stats_results   - struct from run_tfr_cluster_statistics
%   condition_pairs - Nx3 cell: {cond1, cond2, label; ...}
%   plot_tvalues    - if true, use t-value range; otherwise dB difference range
%
% OUTPUT
%   clim_diff - [-max_abs, max_abs] symmetric color limits

if plot_tvalues
    all_vals = [];
    for p = 1:size(condition_pairs, 1)
        comp = sprintf('%s_vs_%s', condition_pairs{p,1}, condition_pairs{p,2});
        if isfield(stats_results, comp) && isfield(stats_results.(comp), 'full_tval')
            all_vals = [all_vals; stats_results.(comp).full_tval(:)]; %#ok<AGROW>
        end
    end
    if ~isempty(all_vals)
        max_abs = prctile(abs(all_vals), 99);
    else
        max_abs = 5;
    end
else
    all_vals = [];
    for p = 1:size(condition_pairs, 1)
        d = grand_avg_plot.(condition_pairs{p,1}) - grand_avg_plot.(condition_pairs{p,2});
        all_vals = [all_vals; d(:)]; %#ok<AGROW>
    end
    max_abs = prctile(abs(all_vals), 99);
end

clim_diff = [-max_abs, max_abs];
end

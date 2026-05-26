function fig = plot_tvalue_topographies(topo_data, stats_results, ...
    window_label, condition_pairs, channels, layout, pub)
%PLOT_TVALUE_TOPOGRAPHIES Plot t-value maps with significant clusters.
%   FIG = PLOT_TVALUE_TOPOGRAPHIES(...) creates a 1 x N figure with
%   t-statistic topographies using a symmetric diverging colormap.
%   Electrodes in significant clusters are marked with black stars.
%
%   INPUTS:
%     topo_data       - computed topography data struct (for trial counts)
%     stats_results   - cluster-corrected statistics results
%     window_label    - time-freq window label (e.g., 'StimClean')
%     condition_pairs - {N x 3} cell: {cond1, cond2, title_label}
%     channels        - matched channel labels
%     layout          - FieldTrip layout struct
%     pub             - publication settings struct
%
%   OUTPUTS:
%     fig - figure handle

    fprintf('  Creating t-value maps with clusters...\n');

    n_pairs = size(condition_pairs, 1);
    fig_w   = pub.fig_width_cm;
    fig_h   = pub.fig_height_cm / 2;

    fig = figure('Units', 'centimeters', 'Position', [2, -6, fig_w, fig_h], ...
        'Color', 'white', 'PaperUnits', 'centimeters', ...
        'PaperSize', [fig_w, fig_h], 'PaperPosition', [0, 0, fig_w, fig_h]);

    % Global symmetric color limits across all t-value maps
    all_tvals = [];
    for p = 1:n_pairs
        comp_name = sprintf('%s_vs_%s', condition_pairs{p,1}, condition_pairs{p,2});
        if isfield(stats_results.(window_label), 'cluster_results') && ...
           isfield(stats_results.(window_label).cluster_results, comp_name)
            tval_data = stats_results.(window_label).cluster_results.(comp_name).obs_t_stats;
            all_tvals = [all_tvals; tval_data(:)]; %#ok<AGROW>
        end
    end
    max_abs = max(abs(all_tvals));
    zlim_tval = [-max_abs, max_abs];

    cb_arr = cell(n_pairs, 1);
    for p = 1:n_pairs
        subplot(1, n_pairs, p);
        cb_arr{p} = plot_single_tvalue(topo_data, stats_results, ...
            condition_pairs{p,1}, condition_pairs{p,2}, condition_pairs{p,3}, ...
            window_label, channels, layout, pub, zlim_tval);
    end
    sync_colorbar_sizes(cb_arr);
end


%% ========================================================================
%  LOCAL HELPERS
%  ========================================================================

function cb = plot_single_tvalue(topo_data, stats_results, cond1, cond2, ...
    title_str, window_label, channels, layout, pub, zlim_range)

    comp_name      = sprintf('%s_vs_%s', cond1, cond2);
    n_trials_cond1 = topo_data.(window_label).data.(cond1).n_trials;
    n_trials_cond2 = topo_data.(window_label).data.(cond2).n_trials;

    if ~isfield(stats_results, window_label) || ...
       ~isfield(stats_results.(window_label), 'cluster_results') || ...
       ~isfield(stats_results.(window_label).cluster_results, comp_name)
        error('T-statistics not found for comparison: %s in window: %s', comp_name, window_label);
    end

    data_tval = stats_results.(window_label).cluster_results.(comp_name).obs_t_stats;

    cfg = [];
    cfg.layout       = layout;
    cfg.figure       = 'gca';
    cfg.marker       = 'on';
    cfg.markersymbol = '.';
    cfg.markersize   = 4;
    cfg.markercolor  = [0.5 0.5 0.5];
    cfg.comment      = 'no';
    cfg.colorbar     = 'yes';
    cfg.colormap     = create_diverging_colormap(256);
    cfg.gridscale    = 200;
    cfg.interplimits = 'head';
    cfg.style        = 'straight';
    cfg.contournum   = 0;
    cfg.zlim         = zlim_range;

    ft_data = struct('label', {channels(:)}, 'avg', data_tval(:), ...
        'time', 0, 'dimord', 'chan_time');
    ft_topoplotER(cfg, ft_data);

    set(findobj(gca, 'Type', 'line'), 'LineWidth', 0.5);

    % Overlay significant cluster electrodes
    overlay_significant_clusters(stats_results, window_label, comp_name, channels, layout);

    title(sprintf('%s\n(%d vs %d trials)', title_str, n_trials_cond1, n_trials_cond2), ...
        'FontName', pub.font_name, 'FontSize', pub.font_size_title, 'FontWeight', 'bold');

    cb = colorbar;
    ylabel(cb, 't-value', 'FontName', pub.font_name, 'FontSize', pub.font_size_label);
    set(cb, 'FontName', pub.font_name, 'FontSize', pub.font_size_axis);

    ax = gca;
    ax.Position(3) = ax.Position(3) * 0.85;
    cb_pos = cb.Position;
    orig_h = cb_pos(4);
    cb_pos(4) = orig_h * 0.6;
    cb_pos(2) = cb_pos(2) + orig_h * 0.2;
    cb.Position = cb_pos;
end


function overlay_significant_clusters(stats_results, window_label, comp_name, channels, layout)
    if ~isfield(stats_results, window_label) || ...
       ~isfield(stats_results.(window_label), 'cluster_results') || ...
       ~isfield(stats_results.(window_label).cluster_results, comp_name)
        return;
    end

    result = stats_results.(window_label).cluster_results.(comp_name);
    if isempty(result.significant_clusters), return; end

    hold on;
    for i = 1:length(result.significant_clusters)
        cluster_idx   = result.significant_clusters(i);
        electrode_idx = result.observed_clusters{cluster_idx};
        for j = 1:length(electrode_idx)
            ch_name = channels{electrode_idx(j)};
            chan_idx = find(strcmpi(layout.label, ch_name));
            if ~isempty(chan_idx)
                plot(layout.pos(chan_idx(1), 1), layout.pos(chan_idx(1), 2), ...
                    'k*', 'MarkerSize', 4, 'LineWidth', 0.3);
            end
        end
    end
    hold off;
end


function sync_colorbar_sizes(colorbars)
    if isempty(colorbars), return; end
    positions = zeros(length(colorbars), 4);
    for i = 1:length(colorbars)
        if isvalid(colorbars{i}), positions(i,:) = colorbars{i}.Position; end
    end
    max_h = max(positions(:,4));
    max_w = max(positions(:,3));
    for i = 1:length(colorbars)
        if isvalid(colorbars{i})
            pos = colorbars{i}.Position;
            pos(3) = max_w;  pos(4) = max_h;
            colorbars{i}.Position = pos;
        end
    end
end

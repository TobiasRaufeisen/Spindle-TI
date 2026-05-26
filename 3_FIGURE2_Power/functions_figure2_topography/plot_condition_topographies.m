function fig = plot_condition_topographies(topo_data, window_label, ...
    conditions, channels, layout, pub)
%PLOT_CONDITION_TOPOGRAPHIES Plot average power topography per condition.
%   FIG = PLOT_CONDITION_TOPOGRAPHIES(...) creates a 1 x N figure with
%   condition-average topographies using a shared parula color scale.
%
%   INPUTS:
%     topo_data    - computed topography data struct
%     window_label - time-freq window label (e.g., 'StimClean')
%     conditions   - cell array of condition names
%     channels     - matched channel labels
%     layout       - FieldTrip layout struct
%     pub          - publication settings struct
%
%   OUTPUTS:
%     fig - figure handle

    fprintf('  Creating condition-average topographies...\n');

    n_cond = length(conditions);
    fig_w  = pub.fig_width_cm;
    fig_h  = pub.fig_height_cm / 2;

    fig = figure('Units', 'centimeters', 'Position', [2, 10, fig_w, fig_h], ...
        'Color', 'white', 'PaperUnits', 'centimeters', ...
        'PaperSize', [fig_w, fig_h], 'PaperPosition', [0, 0, fig_w, fig_h]);

    % Global color limits across conditions (cap at 80% of max)
    all_vals = [];
    for c = 1:n_cond
        all_vals = [all_vals; topo_data.(window_label).data.(conditions{c}).data(:)]; %#ok<AGROW>
    end
    zlim_avg = [min(all_vals), 0.8 * max(all_vals)];

    cb_arr = cell(n_cond, 1);
    for c = 1:n_cond
        subplot(1, n_cond, c);
        cb_arr{c} = plot_single_condition(topo_data, conditions{c}, ...
            window_label, channels, layout, pub, zlim_avg);
    end
    sync_colorbar_sizes(cb_arr);
end


%% ========================================================================
%  LOCAL HELPERS
%  ========================================================================

function cb = plot_single_condition(topo_data, condition, window_label, ...
    channels, layout, pub, zlim_range)

    data_vec = topo_data.(window_label).data.(condition).data;
    n_part   = topo_data.(window_label).data.(condition).n_participants;
    n_trial  = topo_data.(window_label).data.(condition).n_trials;

    cfg = [];
    cfg.layout       = layout;
    cfg.figure       = 'gca';
    cfg.marker       = 'on';
    cfg.markersymbol = '.';
    cfg.markersize   = 4;
    cfg.markercolor  = [1 1 1];
    cfg.comment      = 'no';
    cfg.colorbar     = 'yes';
    cfg.colormap     = parula(256);
    cfg.gridscale    = 200;
    cfg.interplimits = 'head';
    cfg.style        = 'straight';
    cfg.shading      = 'flat';
    cfg.contournum   = 0;
    cfg.zlim         = zlim_range;

    ft_data = struct('label', {channels(:)}, 'avg', data_vec(:), ...
        'time', 0, 'dimord', 'chan_time');
    ft_topoplotER(cfg, ft_data);

    set(findobj(gca, 'Type', 'line'), 'LineWidth', 0.5);
    ax = gca;
    set(ax.Children, 'Clipping', 'on');

    title_str = strrep(strrep(condition, 'x', ''), 'HZ', ' Hz');
    title(sprintf('%s\n(N=%d, %d trials)', title_str, n_part, n_trial), ...
        'FontName', pub.font_name, 'FontSize', pub.font_size_title, 'FontWeight', 'bold');

    cb = colorbar;
    ylabel(cb, 'Power (dB)', 'FontName', pub.font_name, 'FontSize', pub.font_size_label);
    set(cb, 'FontName', pub.font_name, 'FontSize', pub.font_size_axis);

    % Adjust to prevent clipping
    ax.Position(3) = ax.Position(3) * 0.85;
    cb_pos = cb.Position;
    orig_h = cb_pos(4);
    cb_pos(4) = orig_h * 0.6;
    cb_pos(2) = cb_pos(2) + orig_h * 0.2;
    cb.Position = cb_pos;
end


function sync_colorbar_sizes(colorbars)
    % Synchronize colorbar height and width across subplots
    if isempty(colorbars), return; end
    positions = zeros(length(colorbars), 4);
    for i = 1:length(colorbars)
        if isvalid(colorbars{i})
            positions(i, :) = colorbars{i}.Position;
        end
    end
    max_h = max(positions(:, 4));
    max_w = max(positions(:, 3));
    for i = 1:length(colorbars)
        if isvalid(colorbars{i})
            pos = colorbars{i}.Position;
            pos(3) = max_w;
            pos(4) = max_h;
            colorbars{i}.Position = pos;
        end
    end
end

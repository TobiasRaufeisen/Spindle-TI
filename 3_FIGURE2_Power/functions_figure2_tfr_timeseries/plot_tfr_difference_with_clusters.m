function plot_tfr_difference_with_clusters(grand_avg, stats_results, ...
    cond1, cond2, title_str, freq_axis, time_axis, alpha, pub, ...
    clim_range, plot_tvalues, freq_range_analysis, freq_range_plot, apply_db_transform)
% Plot a difference TFR (or t-value map) with significant cluster contours.
%
% INPUTS
%   grand_avg        - struct.(condition) = [freq x time] (dB or raw)
%   stats_results    - struct from run_tfr_cluster_statistics
%   cond1, cond2     - conditions being compared (cond1 minus cond2)
%   title_str        - subplot title
%   freq_axis, time_axis - axis vectors
%   alpha            - significance threshold for cluster highlighting
%   pub              - publication settings struct
%   clim_range       - [lo, hi] symmetric color limits
%   plot_tvalues     - if true, plot t-value map; otherwise dB difference
%   freq_range_analysis - [f_lo, f_hi] drawn as dashed rectangle
%   freq_range_plot  - [f_lo, f_hi] y-axis display range
%   apply_db_transform - true if grand_avg is in dB

if nargin < 14, apply_db_transform = false; end

comp_name = sprintf('%s_vs_%s', cond1, cond2);

if plot_tvalues && isfield(stats_results, comp_name) && ...
        isfield(stats_results.(comp_name), 'full_tval')
    plot_data  = stats_results.(comp_name).full_tval;
    stat_time  = stats_results.(comp_name).time;
    cbar_label = 't-value';
else
    plot_data = grand_avg.(cond1) - grand_avg.(cond2);
    stat_time = time_axis;
    if apply_db_transform
        cbar_label = '\Delta Power (dB)';
    else
        cbar_label = '\Delta Power (\muV^2)';
    end
end

imagesc(stat_time, freq_axis, plot_data);
axis xy;
colormap(gca, create_diverging_colormap(256));

if ~isempty(clim_range)
    clim(clim_range);
else
    max_abs = max(abs(plot_data(:)));
    clim([-max_abs, max_abs]);
end
if ~isempty(freq_range_plot), ylim(freq_range_plot); end

cb = colorbar;
ylabel(cb, cbar_label, 'FontName', pub.font_name, 'FontSize', pub.font_size_label);
xlabel('Time (s)', 'FontName', pub.font_name, 'FontSize', pub.font_size_label);
ylabel('Frequency (Hz)', 'FontName', pub.font_name, 'FontSize', pub.font_size_label);
title(title_str, 'FontName', pub.font_name, 'FontSize', pub.font_size_title, 'FontWeight', 'bold');
set(gca, 'FontName', pub.font_name, 'FontSize', pub.font_size_axis);

% Overlay cluster contours
hold on;
if isfield(stats_results, comp_name)
    stat = stats_results.(comp_name);
    overlay_cluster_contours(stat, alpha);
    plot([0 0], ylim, 'w--', 'LineWidth', 1.5);
else
    plot([0 0], ylim, 'k--', 'LineWidth', 1.5);
end

if ~isempty(freq_range_analysis)
    xl = xlim;
    rectangle('Position', [xl(1), freq_range_analysis(1), ...
        xl(2)-xl(1), diff(freq_range_analysis)], ...
        'EdgeColor', 'w', 'LineStyle', '--', 'LineWidth', 0.8);
end
hold off;
end


function overlay_cluster_contours(stat, alpha)
% Draw contours around significant clusters.
% Pad mask with zeros so contours close at analysis-region edges.
    dt = mean(diff(stat.time));
    df = mean(diff(stat.freq));
    padded_time = [stat.time(1)-dt, stat.time, stat.time(end)+dt];
    padded_freq = [stat.freq(1)-df, stat.freq, stat.freq(end)+df];

    if isfield(stat, 'posclusters') && ~isempty(stat.posclusters)
        for i = find([stat.posclusters.prob] < alpha)
            mask = double(squeeze(stat.posclusterslabelmat == i));
            padded_mask = zeros(size(mask,1)+2, size(mask,2)+2);
            padded_mask(2:end-1, 2:end-1) = mask;
            contour(padded_time, padded_freq, padded_mask, [0.5 0.5], 'k-', 'LineWidth', 2);
        end
    end
    if isfield(stat, 'negclusters') && ~isempty(stat.negclusters)
        for i = find([stat.negclusters.prob] < alpha)
            mask = double(squeeze(stat.negclusterslabelmat == i));
            padded_mask = zeros(size(mask,1)+2, size(mask,2)+2);
            padded_mask(2:end-1, 2:end-1) = mask;
            contour(padded_time, padded_freq, padded_mask, [0.5 0.5], 'k--', 'LineWidth', 2);
        end
    end
end

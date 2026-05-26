function plot_tfr_condition(tfr_data, freq_axis, time_axis, condition, pub, ...
    clim_range, freq_range_analysis, freq_range_plot, apply_db_transform)
% Plot a single-condition TFR plot.
%
% INPUTS
%   tfr_data             - [freq x time] power matrix
%   freq_axis, time_axis - axis vectors
%   condition            - condition label for title
%   pub                  - publication settings struct
%   clim_range           - [lo, hi] color limits
%   freq_range_analysis  - [f_lo, f_hi] drawn as dashed rectangle
%   freq_range_plot      - [f_lo, f_hi] y-axis display range
%   apply_db_transform   - true if data is in dB

if nargin < 9, apply_db_transform = false; end

imagesc(time_axis, freq_axis, tfr_data);
axis xy;
colormap(gca, parula);

if ~isempty(clim_range), clim(clim_range); end
if ~isempty(freq_range_plot), ylim(freq_range_plot); end

cb = colorbar;
if apply_db_transform
    ylabel(cb, 'Power (dB)', 'FontName', pub.font_name, 'FontSize', pub.font_size_label);
else
    ylabel(cb, 'Power (\muV^2)', 'FontName', pub.font_name, 'FontSize', pub.font_size_label);
end

xlabel('Time (s)', 'FontName', pub.font_name, 'FontSize', pub.font_size_label);
ylabel('Frequency (Hz)', 'FontName', pub.font_name, 'FontSize', pub.font_size_label);

title_str = strrep(strrep(condition, 'x', ''), 'HZ', ' Hz');
title(title_str, 'FontName', pub.font_name, 'FontSize', pub.font_size_title, 'FontWeight', 'bold');
set(gca, 'FontName', pub.font_name, 'FontSize', pub.font_size_axis);

hold on;
plot([0 0], ylim, 'k--', 'LineWidth', 1.5);
if ~isempty(freq_range_analysis)
    xl = xlim;
    rectangle('Position', [xl(1), freq_range_analysis(1), ...
        xl(2)-xl(1), diff(freq_range_analysis)], ...
        'EdgeColor', 'w', 'LineStyle', '--', 'LineWidth', 0.8);
end
hold off;
end

function figure3_emmFromTextReport(show_connected_points)
%% FIGURE 3 (MATLAB): EMM + CI from R text report
% Builds two MATLAB figures from GLMM_statistical_results.txt:
% 1) Per-condition EMM + CI subplots + cross-condition sig bars
% 2) Grouped-bar EMM + CI + cross-condition sig bars
%
% Source file:
%   4_FIGURE3_Events/outputs/GLMM_statistical_results.txt
%
% Optional input (default = false):
%   show_connected_points (logical scalar)
%
% Examples:
%   figure3_emmFromTextReport
%   figure3_emmFromTextReport(true)

clc;

% Config
alpha_sig = 0.05;

show_connected_points = false;

if ~(isscalar(show_connected_points) && (islogical(show_connected_points) || isnumeric(show_connected_points)))
    error('show_connected_points must be a logical/numeric scalar.');
end
opts = struct('show_connected_points', logical(show_connected_points));

scriptFile = mfilename('fullpath');
if isempty(scriptFile) || startsWith(scriptFile, tempdir)
    scriptFile = matlab.desktop.editor.getActiveFilename;
end
REPO_ROOT = fileparts(fileparts(scriptFile));  % repo root (portable)
OUTPUT_DIR = fullfile(REPO_ROOT, '4_FIGURE3_Events', 'outputs');
TEXT_REPORT = fullfile(OUTPUT_DIR, 'GLMM_statistical_results.txt');

if ~isfile(TEXT_REPORT)
    error('Text report not found: %s', TEXT_REPORT);
end

pub = struct();
pub.font_name = 'Arial';
pub.font_size_axis = 8;
pub.font_size_label = 9;
pub.font_size_title = 10;
pub.line_width = 1.2;

colors = struct();
colors.x1HZ = [0.0, 0.2, 0.6];   % Blue
colors.x5HZ = [1.0, 0.55, 0.0];  % Orange
colors.OFF  = [0.6, 0.6, 0.6];   % Gray

condition_order = {'x5HZ', 'x1HZ', 'OFF'};
group_order = {'x5HZ', 'x1HZ', 'OFF'};
cond_labels = containers.Map({'x5HZ', 'x1HZ', 'OFF'}, {'5 Hz', '1 Hz', 'OFF'});

% Read text report
raw_txt = fileread(TEXT_REPORT);
raw_txt = strrep(raw_txt, sprintf('\r\n'), sprintf('\n'));
lines = splitlines(string(raw_txt));
trimmed = strtrim(lines);
is_output_line = ~startsWith(trimmed, ">");

% Parse best model label
best_line_idx = find(is_output_line & contains(lines, "*** Best model:"), 1, 'first');
if isempty(best_line_idx)
    error('Could not find "Best model" line in text report.');
end

best_tokens = regexp(lines(best_line_idx), '\*\*\*\s*Best model:\s*(.*?)\s*\(AIC:', 'tokens', 'once');
if isempty(best_tokens)
    error('Could not parse best model label from line: %s', lines(best_line_idx));
end
best_model_label = strtrim(best_tokens{1});

% Parse time-bin metadata
n_bins = NaN;
time_min = NaN;
time_max = NaN;
tb_line_idx = find(is_output_line & contains(lines, 'Time Bins:'), 1, 'first');
if ~isempty(tb_line_idx)
    tb_tokens = regexp(lines(tb_line_idx), ...
        'Time Bins:\s*(\d+)\s*\(([-+]?\d*\.?\d+)\s*to\s*([-+]?\d*\.?\d+)\s*s\)', ...
        'tokens', 'once');
    if ~isempty(tb_tokens)
        n_bins = str2double(tb_tokens{1});
        time_min = str2double(tb_tokens{2});
        time_max = str2double(tb_tokens{3});
    end
end

% Isolate best-model section
sec_header = "GLMM: " + best_model_label;
sec_start = find(contains(lines, sec_header), 1, 'first');
if isempty(sec_start)
    sec_start = find(contains(lines, "GLMM: M5"), 1, 'first');
end
if isempty(sec_start)
    error('Could not locate best-model section in report.');
end

next_glmm_rel = find(startsWith(strtrim(lines(sec_start + 1:end)), "GLMM:"), 1, 'first');
if isempty(next_glmm_rel)
    sec_end = numel(lines);
else
    sec_end = sec_start + next_glmm_rel - 1;
end
sec_lines = lines(sec_start:sec_end);

% Parse EMM table and contrast table from best-model section
emm_tbl = parse_emm_table(sec_lines);
contrast_tbl = parse_condition_contrasts(sec_lines);

% Build bin-center mapping
unique_bins = unique(emm_tbl.TimeBin)';
if ~isnan(n_bins) && ~isnan(time_min) && ~isnan(time_max) && n_bins == numel(unique_bins)
    bin_centers = linspace(time_min, time_max, n_bins);
else
    bin_centers = unique_bins;
end
bin_map = containers.Map(num2cell(unique_bins), num2cell(bin_centers));

emm_tbl.BinCenter = zeros(height(emm_tbl), 1);
for r = 1:height(emm_tbl)
    emm_tbl.BinCenter(r) = bin_map(emm_tbl.TimeBin(r));
end

if ~isempty(contrast_tbl)
    contrast_tbl.BinCenter = zeros(height(contrast_tbl), 1);
    for r = 1:height(contrast_tbl)
        contrast_tbl.BinCenter(r) = bin_map(contrast_tbl.TimeBin(r));
    end
end

sig_tbl = table();
if ~isempty(contrast_tbl)
    sig_mask = ~isnan(contrast_tbl.PValue) & contrast_tbl.PValue < alpha_sig;
    sig_tbl = contrast_tbl(sig_mask, :);
    if ~isempty(sig_tbl)
        sig_tbl.Stars = strings(height(sig_tbl), 1);
        for r = 1:height(sig_tbl)
            sig_tbl.Stars(r) = string(p_to_stars(sig_tbl.PValue(r)));
        end
    end
end

% Shared axis bounds
y_data_max = max(emm_tbl.UCL);
y_axis_max = y_data_max * 1.22;
y_axis_min = 0;

if numel(unique(bin_centers)) > 1
    x_step = median(diff(sort(unique(bin_centers))));
else
    x_step = 1;
end
x_left = min(bin_centers) - x_step / 2;
x_right = max(bin_centers) + x_step / 2;

% ---------------------------------------------------------------
% Figure 1: Per-condition subplots + cross-condition significance bars
% Layout matches temporalHistogram for vertical stacking
% ---------------------------------------------------------------
n_cond = numel(condition_order);
n_sig_levels = height(sig_tbl);

% Layout constants (must match temporalHistogram exactly)
left_margin   = 0.08;
right_margin  = 0.02;
gap           = 0.04;
bottom_margin = 0.15;

fig_title_bot = 0.93;
cond_lbl_h    = 0.04;
sig_pad       = 0.01;

cond_lbl_bot  = fig_title_bot - cond_lbl_h ...
                - n_sig_levels * 0.025 - sig_pad;
cond_lbl_top  = cond_lbl_bot + cond_lbl_h;

plot_top      = cond_lbl_bot - 0.005;
plot_height_n = plot_top - bottom_margin;
plot_width_n  = (1 - left_margin - right_margin - (n_cond-1)*gap) / n_cond;

fig_width_cm  = 18;
fig_height_cm = max(7, 5.5 + n_sig_levels * 0.3);

fig_emm = figure('Units', 'centimeters', ...
    'Position', [2, 2, fig_width_cm, fig_height_cm], ...
    'Color', 'white', ...
    'PaperUnits', 'centimeters', ...
    'PaperSize', [fig_width_cm, fig_height_cm], ...
    'PaperPosition', [0, 0, fig_width_cm, fig_height_cm]);

ax_handles = gobjects(1, n_cond);

for c = 1:n_cond
    cond = condition_order{c};
    left_pos = left_margin + (c-1) * (plot_width_n + gap);
    ax_handles(c) = axes('Parent', fig_emm, ...
        'Position', [left_pos, bottom_margin, plot_width_n, plot_height_n]);
    hold(ax_handles(c), 'on');

    sub = emm_tbl(emm_tbl.Condition == cond, :);
    sub = sortrows(sub, 'TimeBin');

    if any(sub.BinCenter < 0)
        x_pre_left = min(sub.BinCenter) - x_step / 2;
        x_pre_right = 0;
        patch(ax_handles(c), [x_pre_left, x_pre_right, x_pre_right, x_pre_left], ...
            [y_axis_min, y_axis_min, y_axis_max, y_axis_max], ...
            [0.94, 0.94, 0.94], ...
            'EdgeColor', 'none', 'FaceAlpha', 0.7);
        x_pre_center = mean([x_pre_left, x_pre_right]);
    else
        x_pre_center = min(sub.BinCenter);
    end

    b = bar(ax_handles(c), sub.BinCenter, sub.Prob, 0.85, ...
        'FaceColor', colors.(cond), ...
        'EdgeColor', 'none', ...
        'FaceAlpha', 0.8);
    b.ShowBaseLine = 'off';

    err_low = sub.Prob - sub.LCL;
    err_high = sub.UCL - sub.Prob;
    errorbar(ax_handles(c), sub.BinCenter, sub.Prob, err_low, err_high, ...
        'LineStyle', 'none', ...
        'Color', [0.2, 0.2, 0.2], ...
        'LineWidth', 1.2, ...
        'CapSize', 4);

    if opts.show_connected_points
        plot(ax_handles(c), sub.BinCenter, sub.Prob, '-o', ...
            'Color', colors.(cond), ...
            'LineWidth', 1.1, ...
            'MarkerSize', 4.5, ...
            'MarkerFaceColor', 'white', ...
            'MarkerEdgeColor', colors.(cond));
    end

    xline(ax_handles(c), 0, '--', 'Color', [0.4, 0.4, 0.4], 'LineWidth', pub.line_width);

    x_post_center = mean([max(0, x_left), x_right]);
    text(ax_handles(c), x_pre_center, y_axis_max * 0.92, 'Pre', ...
        'FontName', pub.font_name, 'FontSize', 7, ...
        'HorizontalAlignment', 'center', 'VerticalAlignment', 'top', ...
        'Color', [0.35, 0.35, 0.35]);
    text(ax_handles(c), x_post_center, y_axis_max * 0.92, 'Post', ...
        'FontName', pub.font_name, 'FontSize', 7, ...
        'HorizontalAlignment', 'center', 'VerticalAlignment', 'top', ...
        'Color', [0.35, 0.35, 0.35]);

    hold(ax_handles(c), 'off');

    set(ax_handles(c), 'FontName', pub.font_name, ...
        'FontSize', pub.font_size_axis, ...
        'Box', 'off', ...
        'TickDir', 'out', ...
        'TickLength', [0.02, 0.02], ...
        'LineWidth', 0.8, ...
        'XColor', [0, 0, 0], ...
        'YColor', [0, 0, 0]);

    xticks(ax_handles(c), sort(unique(sub.BinCenter)));
    xticklabels(ax_handles(c), compose('%.2f', sort(unique(sub.BinCenter))));
    xlim(ax_handles(c), [x_left, x_right]);
    ylim(ax_handles(c), [y_axis_min, y_axis_max]);
    xlabel(ax_handles(c), 'Time from trial onset (s)', ...
        'FontName', pub.font_name, ...
        'FontSize', pub.font_size_label);

    if c == 1
        ylabel(ax_handles(c), 'Estimated spindle probability', ...
            'FontName', pub.font_name, ...
            'FontSize', pub.font_size_label);
    else
        set(ax_handles(c), 'YTickLabel', []);
    end

end

% Significance brackets
sig_bracket_bot = cond_lbl_top + sig_pad;
sig_bracket_top = fig_title_bot - 0.022;

if ~isempty(sig_tbl)
    draw_cross_condition_brackets(fig_emm, ax_handles, sig_tbl, condition_order, ...
        x_left, x_right, pub, sig_bracket_bot, sig_bracket_top);
end

% Condition labels (matches temporalHistogram annotation style)
for c = 1:n_cond
    pos_c = get(ax_handles(c), 'Position');
    x_center = pos_c(1) + pos_c(3) / 2;
    annotation(fig_emm, 'textbox', ...
        [x_center - 0.06, cond_lbl_bot, 0.12, cond_lbl_h], ...
        'String', cond_labels(condition_order{c}), ...
        'EdgeColor', 'none', ...
        'HorizontalAlignment', 'center', ...
        'VerticalAlignment', 'middle', ...
        'FontName', pub.font_name, ...
        'FontSize', pub.font_size_title, ...
        'FontWeight', 'bold', ...
        'Margin', 0);
end

% Figure title (matches temporalHistogram annotation style)
annotation(fig_emm, 'textbox', [0.0, fig_title_bot, 1.0, 1.0 - fig_title_bot], ...
    'String', sprintf('Best-model EMMs (95%% CI): %s', best_model_label), ...
    'EdgeColor', 'none', ...
    'HorizontalAlignment', 'center', ...
    'VerticalAlignment', 'middle', ...
    'FontName', pub.font_name, ...
    'FontSize', pub.font_size_title + 1, ...
    'FontWeight', 'bold', ...
    'Margin', 0);

out_emm_png = fullfile(OUTPUT_DIR, 'emm_ci_bestModel_fromText_matlab.png');
out_emm_svg = fullfile(OUTPUT_DIR, 'emm_ci_bestModel_fromText_matlab.svg');
out_emm_fig = fullfile(OUTPUT_DIR, 'emm_ci_bestModel_fromText_matlab.fig');
saveas(fig_emm, out_emm_png);
saveas(fig_emm, out_emm_svg);
savefig(fig_emm, out_emm_fig);

% ---------------------------------------------------------------
% Figure 2: Grouped bars + significance bars
% Same proportions as Figure 1 / temporalHistogram for stacking
% ---------------------------------------------------------------
n_bins_local = numel(unique_bins);
n_conds_group = numel(group_order);

mean_mat = nan(n_bins_local, n_conds_group);
lcl_mat = nan(n_bins_local, n_conds_group);
ucl_mat = nan(n_bins_local, n_conds_group);

for i = 1:n_bins_local
    b_id = unique_bins(i);
    for j = 1:n_conds_group
        cond = group_order{j};
        row = emm_tbl(emm_tbl.TimeBin == b_id & emm_tbl.Condition == cond, :);
        if ~isempty(row)
            mean_mat(i, j) = row.Prob(1);
            lcl_mat(i, j) = row.LCL(1);
            ucl_mat(i, j) = row.UCL(1);
        end
    end
end

% Same figure dimensions as the per-condition figure
grp_plot_height = fig_title_bot - 0.01 - bottom_margin;

fig_group = figure('Units', 'centimeters', ...
    'Position', [2, 2, fig_width_cm, fig_height_cm], ...
    'Color', 'white', ...
    'PaperUnits', 'centimeters', ...
    'PaperSize', [fig_width_cm, fig_height_cm], ...
    'PaperPosition', [0, 0, fig_width_cm, fig_height_cm]);

% Single axes spanning the full plot width (same left/right margins)
axg = axes('Parent', fig_group, ...
    'Position', [left_margin, bottom_margin, ...
                 1 - left_margin - right_margin, grp_plot_height]);
hold(axg, 'on');

if any(bin_centers < 0)
    x_pre_left = min(bin_centers) - x_step / 2;
    x_pre_right = 0;
    patch(axg, [x_pre_left, x_pre_right, x_pre_right, x_pre_left], ...
        [y_axis_min, y_axis_min, y_axis_max * 1.15, y_axis_max * 1.15], ...
        [0.94, 0.94, 0.94], ...
        'EdgeColor', 'none', 'FaceAlpha', 0.7);
end

bar_handles = bar(axg, bin_centers, mean_mat, 'grouped', 'BarWidth', 0.82);
for j = 1:n_conds_group
    bar_handles(j).FaceColor = colors.(group_order{j});
    bar_handles(j).EdgeColor = 'none';
    bar_handles(j).FaceAlpha = 0.8;
end

x_bar = get_grouped_x_positions(bar_handles, bin_centers);
for j = 1:n_conds_group
    err_low = mean_mat(:, j) - lcl_mat(:, j);
    err_high = ucl_mat(:, j) - mean_mat(:, j);
    errorbar(axg, x_bar(:, j), mean_mat(:, j), err_low, err_high, ...
        'LineStyle', 'none', ...
        'Color', [0.2, 0.2, 0.2], ...
        'LineWidth', 1.2, ...
        'CapSize', 4);
end

if opts.show_connected_points
    for j = 1:n_conds_group
        cond = group_order{j};
        plot(axg, x_bar(:, j), mean_mat(:, j), '-o', ...
            'Color', colors.(cond), ...
            'LineWidth', 1.1, ...
            'MarkerSize', 4.5, ...
            'MarkerFaceColor', 'white', ...
            'MarkerEdgeColor', colors.(cond));
    end
end

xline(axg, 0, '--', 'Color', [0.4, 0.4, 0.4], 'LineWidth', 1.2);

if ~isempty(sig_tbl)
    draw_grouped_brackets(axg, sig_tbl, group_order, unique_bins, x_bar, ucl_mat);
end

set(axg, 'FontName', pub.font_name, ...
    'FontSize', pub.font_size_axis, ...
    'Box', 'off', ...
    'TickDir', 'out', ...
    'TickLength', [0.02, 0.02], ...
    'LineWidth', 0.8, ...
    'XColor', [0, 0, 0], ...
    'YColor', [0, 0, 0]);

xticks(axg, sort(bin_centers));
xticklabels(axg, compose('%.2f', sort(bin_centers)));
xlim(axg, [x_left, x_right]);
xlabel(axg, 'Time from trial onset (s)', ...
    'FontName', pub.font_name, ...
    'FontSize', pub.font_size_label);
ylabel(axg, 'Estimated spindle probability', ...
    'FontName', pub.font_name, ...
    'FontSize', pub.font_size_label);

legend(axg, bar_handles, ...
    {cond_labels('x5HZ'), cond_labels('x1HZ'), cond_labels('OFF')}, ...
    'Location', 'northeast', ...
    'Box', 'off', ...
    'FontSize', pub.font_size_axis);

onset_norm = (0 - x_left) / (x_right - x_left);
onset_norm = max(0, min(1, onset_norm));
if any(bin_centers < 0)
    text(axg, onset_norm / 2, 0.965, 'Pre', ...
        'Units', 'normalized', ...
        'FontName', pub.font_name, ...
        'FontSize', 7, ...
        'HorizontalAlignment', 'center', ...
        'VerticalAlignment', 'top', ...
        'Color', [0.35, 0.35, 0.35]);
end
text(axg, onset_norm + (1 - onset_norm) / 2, 0.965, 'Post', ...
    'Units', 'normalized', ...
    'FontName', pub.font_name, ...
    'FontSize', 7, ...
    'HorizontalAlignment', 'center', ...
    'VerticalAlignment', 'top', ...
    'Color', [0.35, 0.35, 0.35]);

hold(axg, 'off');

% Figure title (matches the per-condition figure annotation style)
annotation(fig_group, 'textbox', [0.0, fig_title_bot, 1.0, 1.0 - fig_title_bot], ...
    'String', sprintf('Best-model EMMs (95%% CI), grouped: %s', best_model_label), ...
    'EdgeColor', 'none', ...
    'HorizontalAlignment', 'center', ...
    'VerticalAlignment', 'middle', ...
    'FontName', pub.font_name, ...
    'FontSize', pub.font_size_title + 1, ...
    'FontWeight', 'bold', ...
    'Margin', 0);

out_group_png = fullfile(OUTPUT_DIR, 'emm_ci_bestModel_grouped_fromText_matlab.png');
out_group_svg = fullfile(OUTPUT_DIR, 'emm_ci_bestModel_grouped_fromText_matlab.svg');
out_group_fig = fullfile(OUTPUT_DIR, 'emm_ci_bestModel_grouped_fromText_matlab.fig');
saveas(fig_group, out_group_png);
saveas(fig_group, out_group_svg);
savefig(fig_group, out_group_fig);

% Figure 3: Contrast forest plot (Condition contrasts within each TimeBin)
out_contrast_png = '';
out_contrast_svg = '';
out_contrast_fig = '';
if ~isempty(contrast_tbl)
    contrast_plot_tbl = contrast_tbl;

    % Reverse direction: swap conditions and invert OR
    % so labels read "A > B" meaning "A has X times the odds of B"
    temp_cond = contrast_plot_tbl.Condition1;
    contrast_plot_tbl.Condition1 = contrast_plot_tbl.Condition2;
    contrast_plot_tbl.Condition2 = temp_cond;
    contrast_plot_tbl.OddsRatio = 1 ./ contrast_plot_tbl.OddsRatio;

    contrast_plot_tbl.Contrast = strcat(contrast_plot_tbl.Condition1, " > ", contrast_plot_tbl.Condition2);
    contrast_plot_tbl.LogOR = log(contrast_plot_tbl.OddsRatio);
    contrast_plot_tbl.CI_L = exp(contrast_plot_tbl.LogOR - 1.96 * contrast_plot_tbl.SE);
    contrast_plot_tbl.CI_U = exp(contrast_plot_tbl.LogOR + 1.96 * contrast_plot_tbl.SE);

    pair_order = {'x1HZ > OFF', 'x5HZ > OFF', 'x5HZ > x1HZ'};
    pair_display = cellfun(@(s) strrep(strrep(s, 'x1HZ', '1 Hz'), 'x5HZ', '5 Hz'), ...
        pair_order, 'UniformOutput', false);
    n_pairs = numel(pair_order);

    % Symmetric axis limits in log-space around OR = 1
    log_extreme = max(abs(log([min(contrast_plot_tbl.CI_L); max(contrast_plot_tbl.CI_U)])));
    log_extreme = log_extreme * 1.15;           % 15 % padding
    log_extreme = max(log_extreme, log(1.1));    % minimum visible range
    x_min = exp(-log_extreme);
    x_max = exp( log_extreme);

    fig_contrast = figure('Units', 'centimeters', ...
        'Position', [2, 2, 19, 6.5], ...
        'Color', 'white', ...
        'PaperUnits', 'centimeters', ...
        'PaperSize', [19, 6.5], ...
        'PaperPosition', [0, 0, 19, 6.5]);

    tc = tiledlayout(1, n_bins_local, 'TileSpacing', 'compact', 'Padding', 'compact');

    for bi = 1:n_bins_local
        b_id = unique_bins(bi);
        axc = nexttile(tc, bi);
        hold(axc, 'on');

        sub = contrast_plot_tbl(contrast_plot_tbl.TimeBin == b_id, :);

        for pj = 1:n_pairs
            pair_name = string(pair_order{pj});
            row = sub(sub.Contrast == pair_name, :);
            if isempty(row)
                continue;
            end

            y = n_pairs - pj + 1;
            or_val = row.OddsRatio(1);
            ci_l = row.CI_L(1);
            ci_u = row.CI_U(1);
            pval = row.PValue(1);

            plot(axc, [ci_l, ci_u], [y, y], '-', ...
                'Color', [0.2, 0.2, 0.2], ...
                'LineWidth', 1.35);

            if ~isnan(pval) && pval < alpha_sig
                marker_face = [0.1, 0.1, 0.1];
            else
                marker_face = [1, 1, 1];
            end

            plot(axc, or_val, y, 'o', ...
                'MarkerSize', 5.5, ...
                'MarkerEdgeColor', [0, 0, 0], ...
                'MarkerFaceColor', marker_face, ...
                'LineWidth', 1.0);

            if ~isnan(pval) && pval < alpha_sig
                text(axc, min(ci_u * 1.03, x_max * 0.985), y + 0.10, p_to_stars(pval), ...
                    'FontSize', 8, ...
                    'HorizontalAlignment', 'left', ...
                    'VerticalAlignment', 'bottom', ...
                    'Color', [0, 0, 0]);
            end
        end

        xline(axc, 1, '--', ...
            'Color', [0.45, 0.45, 0.45], ...
            'LineWidth', 1.0);

        set(axc, 'FontName', pub.font_name, ...
            'FontSize', pub.font_size_axis, ...
            'Box', 'off', ...
            'TickDir', 'out', ...
            'TickLength', [0.02, 0.02], ...
            'LineWidth', 0.8, ...
            'XColor', [0, 0, 0], ...
            'YColor', [0, 0, 0]);

        xlim(axc, [x_min, x_max]);
        ylim(axc, [0.5, n_pairs + 0.5]);
        xticks(axc, nice_log_ticks(x_min, x_max));
        set(axc, 'XScale', 'log');
        xlabel(axc, 'Odds ratio', ...
            'FontName', pub.font_name, ...
            'FontSize', pub.font_size_label);

        if bi == 1
            yticks(axc, 1:n_pairs);
            yticklabels(axc, fliplr(pair_display));
            ylabel(axc, 'Condition contrast', ...
                'FontName', pub.font_name, ...
                'FontSize', pub.font_size_label);
        else
            yticks(axc, 1:n_pairs);
            yticklabels(axc, repmat({''}, 1, n_pairs));
        end

        t_center = bin_map(b_id);
        title(axc, sprintf('TimeBin %d (%.2f s)', b_id, t_center), ...
            'FontName', pub.font_name, ...
            'FontSize', pub.font_size_title, ...
            'FontWeight', 'bold');

        hold(axc, 'off');
    end

    title(tc, sprintf('Condition Contrasts by Time Bin (OR, 95%% Wald CI): %s', best_model_label), ...
        'FontName', pub.font_name, ...
        'FontSize', pub.font_size_title + 1, ...
        'FontWeight', 'bold');

    out_contrast_png = fullfile(OUTPUT_DIR, 'contrast_forest_bestModel_fromText_matlab.png');
    out_contrast_svg = fullfile(OUTPUT_DIR, 'contrast_forest_bestModel_fromText_matlab.svg');
    out_contrast_fig = fullfile(OUTPUT_DIR, 'contrast_forest_bestModel_fromText_matlab.fig');
    saveas(fig_contrast, out_contrast_png);
    saveas(fig_contrast, out_contrast_svg);
    savefig(fig_contrast, out_contrast_fig);
end

% Console summary
fprintf('Saved per-condition EMM+CI figure with significance bars:\n');
fprintf('  %s\n', out_emm_png);
fprintf('  %s\n', out_emm_svg);
fprintf('  %s\n', out_emm_fig);
fprintf('Saved grouped EMM+CI figure with significance bars:\n');
fprintf('  %s\n', out_group_png);
fprintf('  %s\n', out_group_svg);
fprintf('  %s\n', out_group_fig);
if ~isempty(out_contrast_png)
    fprintf('Saved contrast forest plot:\n');
    fprintf('  %s\n', out_contrast_png);
    fprintf('  %s\n', out_contrast_svg);
    fprintf('  %s\n', out_contrast_fig);
end
fprintf('Connected points overlay: %s\n', ternary_str(opts.show_connected_points, 'ON', 'OFF'));

end

function emm_tbl = parse_emm_table(sec_lines)
emm_header_idx = find(contains(sec_lines, "Estimated Marginal Means (Probability Scale):"), 1, 'first');
if isempty(emm_header_idx)
    error('Could not find EMM header inside best-model section.');
end

emm_condition = strings(0, 1);
emm_timebin = [];
emm_prob = [];
emm_se = [];
emm_lcl = [];
emm_ucl = [];

row_pattern = '^\s*(OFF|x1HZ|x5HZ)\s+(\d+)\s+([-+]?\d*\.?\d+(?:[eE][-+]?\d+)?)\s+([-+]?\d*\.?\d+(?:[eE][-+]?\d+)?)\s+\S+\s+([-+]?\d*\.?\d+(?:[eE][-+]?\d+)?)\s+([-+]?\d*\.?\d+(?:[eE][-+]?\d+)?)\s*$';

for i = emm_header_idx + 1:numel(sec_lines)
    line_i = char(sec_lines(i));
    if contains(sec_lines(i), "Confidence level used:")
        break;
    end

    tokens = regexp(line_i, row_pattern, 'tokens', 'once');
    if isempty(tokens)
        continue;
    end

    emm_condition(end + 1, 1) = string(tokens{1}); %#ok<AGROW>
    emm_timebin(end + 1, 1) = str2double(tokens{2}); %#ok<AGROW>
    emm_prob(end + 1, 1) = str2double(tokens{3}); %#ok<AGROW>
    emm_se(end + 1, 1) = str2double(tokens{4}); %#ok<AGROW>
    emm_lcl(end + 1, 1) = str2double(tokens{5}); %#ok<AGROW>
    emm_ucl(end + 1, 1) = str2double(tokens{6}); %#ok<AGROW>
end

if isempty(emm_timebin)
    error('Failed to parse EMM rows from best-model section.');
end

emm_tbl = table(emm_condition, emm_timebin, emm_prob, emm_se, emm_lcl, emm_ucl, ...
    'VariableNames', {'Condition', 'TimeBin', 'Prob', 'SE', 'LCL', 'UCL'});
end

function contrast_tbl = parse_condition_contrasts(sec_lines)
contrast_tbl = table();

start_idx = find(contains(sec_lines, "Post-hoc Contrasts: Conditions within Time Bins:"), 1, 'first');
if isempty(start_idx)
    return;
end

end_rel = find(contains(sec_lines(start_idx + 1:end), ...
    "Post-hoc Contrasts: Time Bins within Conditions:"), 1, 'first');
if isempty(end_rel)
    end_idx = numel(sec_lines);
else
    end_idx = start_idx + end_rel - 1;
end

block = sec_lines(start_idx + 1:end_idx);

cond1 = strings(0, 1);
cond2 = strings(0, 1);
timebin = [];
odds_ratio = [];
se_val = [];
z_ratio = [];
pval = [];

current_bin = NaN;

for i = 1:numel(block)
    line_i = char(block(i));

    tb_tok = regexp(line_i, '^\s*TimeBin\s*=\s*(\d+):', 'tokens', 'once');
    if ~isempty(tb_tok)
        current_bin = str2double(tb_tok{1});
        continue;
    end

    row_tok = regexp(line_i, ...
        '^\s*(OFF|x1HZ|x5HZ)\s*/\s*(OFF|x1HZ|x5HZ)\s+([-+]?\d*\.?\d+(?:[eE][-+]?\d+)?)\s+([-+]?\d*\.?\d+(?:[eE][-+]?\d+)?)\s+\S+\s+\S+\s+([-+]?\d*\.?\d+(?:[eE][-+]?\d+)?)\s+(\S+)\s*$', ...
        'tokens', 'once');
    if isempty(row_tok) || isnan(current_bin)
        continue;
    end

    p_num = parse_pvalue_token(row_tok{6});

    cond1(end + 1, 1) = string(row_tok{1}); %#ok<AGROW>
    cond2(end + 1, 1) = string(row_tok{2}); %#ok<AGROW>
    timebin(end + 1, 1) = current_bin; %#ok<AGROW>
    odds_ratio(end + 1, 1) = str2double(row_tok{3}); %#ok<AGROW>
    se_val(end + 1, 1) = str2double(row_tok{4}); %#ok<AGROW>
    z_ratio(end + 1, 1) = str2double(row_tok{5}); %#ok<AGROW>
    pval(end + 1, 1) = p_num; %#ok<AGROW>
end

if ~isempty(timebin)
    contrast_tbl = table(cond1, cond2, timebin, odds_ratio, se_val, z_ratio, pval, ...
        'VariableNames', {'Condition1', 'Condition2', 'TimeBin', 'OddsRatio', 'SE', 'ZRatio', 'PValue'});
end
end

function p = parse_pvalue_token(tok)
tok = strtrim(string(tok));
if startsWith(tok, "<") || startsWith(tok, ">")
    tok = extractAfter(tok, 1);
end
p = str2double(tok);
end

function s = p_to_stars(p)
if isnan(p) || p >= 0.05
    s = '';
elseif p < 0.001
    s = '***';
elseif p < 0.01
    s = '**';
else
    s = '*';
end
end

function draw_cross_condition_brackets(fig_h, ax_handles, sig_tbl, cond_order, x_left, x_right, pub, sig_bot, sig_top)
if isempty(sig_tbl)
    return;
end

n_axes = numel(ax_handles);
ax_pos = zeros(n_axes, 4);
for i = 1:n_axes
    ax_pos(i, :) = get(ax_handles(i), 'Position');
end

% Build comparison list and assign one unique y-level per comparison.
n_comp = height(sig_tbl);
if n_comp == 0
    return;
end

span = zeros(n_comp, 1);
for i = 1:n_comp
    i1 = find(strcmp(cond_order, char(sig_tbl.Condition1(i))), 1, 'first');
    i2 = find(strcmp(cond_order, char(sig_tbl.Condition2(i))), 1, 'first');
    span(i) = abs(i1 - i2);
end

% Stable ordering: by bin, then by span, then p-value.
[~, ord] = sortrows([sig_tbl.BinCenter, span, sig_tbl.PValue], [1, 2, 3]);
sub = sig_tbl(ord, :);

% Bracket band passed by caller (matches temporalHistogram layout)
bottom_limit = sig_bot;
top_limit = sig_top;

if n_comp == 1
    step_y = 0.02;
    y_levels = (top_limit + bottom_limit) / 2;
else
    y_levels = linspace(bottom_limit, top_limit, n_comp)';
    step_y = y_levels(2) - y_levels(1);
end

tick_y = min(0.0045, max(0.0028, step_y * 0.28));
star_offset = max(tick_y + 0.0015, step_y * 0.42);
star_h = min(0.014, max(0.010, step_y * 0.36));
star_w = 0.028;
x_pad = 0.003;  % inset endpoints so adjacent brackets do not visually merge

for i = 1:n_comp
    cond1 = char(sub.Condition1(i));
    cond2 = char(sub.Condition2(i));
    idx1 = find(strcmp(cond_order, cond1), 1, 'first');
    idx2 = find(strcmp(cond_order, cond2), 1, 'first');
    if isempty(idx1) || isempty(idx2) || idx1 == idx2
        continue;
    end

    x_norm = (sub.BinCenter(i) - x_left) / (x_right - x_left);
    x_norm = max(0, min(1, x_norm));

    x1 = ax_pos(idx1, 1) + x_norm * ax_pos(idx1, 3);
    x2 = ax_pos(idx2, 1) + x_norm * ax_pos(idx2, 3);
    if x1 > x2
        tmp = x1;
        x1 = x2;
        x2 = tmp;
    end
    if (x2 - x1) > 2 * x_pad
        x1 = x1 + x_pad;
        x2 = x2 - x_pad;
    end

    y = y_levels(i);

    annotation(fig_h, 'line', [x1, x2], [y, y], ...
        'Color', 'k', 'LineWidth', 0.8);
    annotation(fig_h, 'line', [x1, x1], [y - tick_y, y], ...
        'Color', 'k', 'LineWidth', 0.8);
    annotation(fig_h, 'line', [x2, x2], [y - tick_y, y], ...
        'Color', 'k', 'LineWidth', 0.8);

    star = p_to_stars(sub.PValue(i));
    annotation(fig_h, 'textbox', [mean([x1, x2]) - star_w / 2, y + star_offset, star_w, star_h], ...
        'String', star, ...
        'EdgeColor', 'none', ...
        'HorizontalAlignment', 'center', ...
        'VerticalAlignment', 'bottom', ...
        'FontName', pub.font_name, ...
        'FontSize', 8);
end
end

function x_pos = get_grouped_x_positions(bar_handles, x_groups)
n_groups = numel(x_groups);
n_bars = numel(bar_handles);
x_pos = nan(n_groups, n_bars);

for b = 1:n_bars
    if isprop(bar_handles(b), 'XEndPoints') && numel(bar_handles(b).XEndPoints) == n_groups
        x_pos(:, b) = bar_handles(b).XEndPoints(:);
    else
        groupwidth = min(0.8, n_bars / (n_bars + 1.5));
        x_pos(:, b) = x_groups(:) - groupwidth / 2 + (2 * b - 1) * groupwidth / (2 * n_bars);
    end
end
end

function draw_grouped_brackets(ax, sig_tbl, cond_order, unique_bins, x_bar, ucl_mat)
if isempty(sig_tbl)
    return;
end

max_ucl_per_bin = max(ucl_mat, [], 2);
y_data_max = max(ucl_mat(:));
base_offset = y_data_max * 0.055;
step = y_data_max * 0.10;
tick = y_data_max * 0.022;

y_peak = max_ucl_per_bin;

for i = 1:numel(unique_bins)
    b_id = unique_bins(i);
    sub = sig_tbl(sig_tbl.TimeBin == b_id, :);
    if isempty(sub)
        continue;
    end

    span = zeros(height(sub), 1);
    for r = 1:height(sub)
        idx1 = find(strcmp(cond_order, char(sub.Condition1(r))), 1, 'first');
        idx2 = find(strcmp(cond_order, char(sub.Condition2(r))), 1, 'first');
        span(r) = abs(idx1 - idx2);
    end
    [~, ord] = sort(span, 'ascend');
    sub = sub(ord, :);

    for r = 1:height(sub)
        idx1 = find(strcmp(cond_order, char(sub.Condition1(r))), 1, 'first');
        idx2 = find(strcmp(cond_order, char(sub.Condition2(r))), 1, 'first');
        if isempty(idx1) || isempty(idx2) || idx1 == idx2
            continue;
        end

        x1 = x_bar(i, idx1);
        x2 = x_bar(i, idx2);
        if x1 > x2
            tmp = x1;
            x1 = x2;
            x2 = tmp;
        end

        y = max_ucl_per_bin(i) + base_offset + (r - 1) * step;
        y_peak(i) = max(y_peak(i), y);

        plot(ax, [x1, x2], [y, y], 'k-', 'LineWidth', 0.8);
        plot(ax, [x1, x1], [y - tick, y], 'k-', 'LineWidth', 0.8);
        plot(ax, [x2, x2], [y - tick, y], 'k-', 'LineWidth', 0.8);
        text(ax, mean([x1, x2]), y + tick * 0.75, p_to_stars(sub.PValue(r)), ...
            'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', ...
            'FontSize', 8, 'Color', 'k');
        y_peak(i) = max(y_peak(i), y + tick * 1.6);
    end
end

yl = ylim(ax);
y_top_needed = max(y_peak) + base_offset * 1.25;
ylim(ax, [yl(1), y_top_needed]);
end

function out = ternary_str(cond, true_str, false_str)
if cond
    out = true_str;
else
    out = false_str;
end
end

function ticks = nice_log_ticks(xmin, xmax)
% Clean reciprocal pairs: 0.25/4, 0.5/2, 1 (standard for OR forest plots)
base_ticks = [0.25, 0.5, 1, 2, 4];
ticks = base_ticks(base_ticks >= xmin & base_ticks <= xmax);
if isempty(ticks)
    ticks = [xmin, 1, xmax];
end
ticks = unique(ticks);
end

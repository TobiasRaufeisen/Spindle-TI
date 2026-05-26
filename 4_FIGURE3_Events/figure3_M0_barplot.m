%% figure3_M0_barplot.m
% =========================================================================
% Barplot of GLMM M0 estimated spindle probability by condition.
% Reads CSV data exported by eventHistStats.R (section B15b).
% Visual style matches figure3_metricsBarplot.m exactly.
%
% Condition order: 5 Hz - 1 Hz - Off
% =========================================================================
clear;clc;
%% Setup
scriptFile = mfilename('fullpath');
if isempty(scriptFile) || startsWith(scriptFile, tempdir)
    scriptFile = matlab.desktop.editor.getActiveFilename;
end
OUTPUT_DIR = fullfile(fileparts(scriptFile), 'outputs');  % portable

% --- Publication formatting (matches metricsBarplot.m) ---
pub.fig_width_cm   = 6;
pub.fig_height_cm  = 5;
pub.bar_width      = 0.6;
pub.font_name      = 'Arial';
pub.font_size_axis = 7;
pub.font_size_label = 8;
pub.font_size_title = 9;
pub.alpha           = 0.05;

colors = [
    1.0, 0.55, 0.0;   % Orange  -- 5 Hz
    0.0, 0.20, 0.6;   % Blue    -- 1 Hz
    0.6, 0.60, 0.6    % Grey    -- Off
];

cond_labels = {'5 Hz', '1 Hz', 'Off'};
n_cond = 3;

%% Load data exported from R
% Subject-level data (wide: Subject | x5HZ | x1HZ | OFF)
T_subj = readtable(fullfile(OUTPUT_DIR, 'M0_barplot_subject_data.csv'));
data = [T_subj.x5HZ, T_subj.x1HZ, T_subj.OFF];  % N x 3 matrix

% Summary statistics
T_summ = readtable(fullfile(OUTPUT_DIR, 'M0_barplot_summary.csv'));
% Reorder to match display order: x5HZ, x1HZ, OFF
[~, idx] = ismember({'x5HZ','x1HZ','OFF'}, T_summ.Condition);
means = T_summ.Mean(idx)';
sems  = T_summ.SEM(idx)';

% Post-hoc pairwise contrasts
T_ph = readtable(fullfile(OUTPUT_DIR, 'M0_barplot_posthoc.csv'));

% Omnibus p-value
fid = fopen(fullfile(OUTPUT_DIR, 'M0_barplot_omnibus_p.txt'), 'r');
omnibus_p = str2double(fgetl(fid));
fclose(fid);

%% Build posthoc structure
% Map condition names to display-order indices
cond_map = containers.Map({'x5HZ','x1HZ','OFF'}, {1, 2, 3});

posthoc = struct('pairs', {}, 'p_holm', {});
for k = 1:height(T_ph)
    posthoc(k).pairs  = [cond_map(T_ph.cond1{k}), cond_map(T_ph.cond2{k})];
    posthoc(k).p_holm = T_ph.p_value(k);
end

%% Create figure
fig = figure('Units', 'centimeters', ...
    'Position', [2, 5, pub.fig_width_cm, pub.fig_height_cm], ...
    'Color', 'white', ...
    'PaperUnits', 'centimeters', ...
    'PaperSize', [pub.fig_width_cm, pub.fig_height_cm], ...
    'PaperPosition', [0, 0, pub.fig_width_cm, pub.fig_height_cm]);

hold on;

% --- Bars ---
for c = 1:n_cond
    bar(c, means(c), pub.bar_width, ...
        'FaceColor', colors(c,:), 'EdgeColor', 'none');
end

% --- Error bars (SEM) ---
errorbar(1:n_cond, means, sems, 'k.', 'LineWidth', 1.5, 'CapSize', 8);

% --- Connecting lines (per subject across conditions) ---
n_pts = size(data, 1);
for s_idx = 1:n_pts
    subj_data = data(s_idx, :);
    valid = ~isnan(subj_data);
    if sum(valid) >= 2
        x_pos = find(valid);
        plot(x_pos, subj_data(valid), '-', ...
            'Color', [0.5, 0.5, 0.5, 0.3], 'LineWidth', 0.5);
    end
end

% --- Individual data points ---
for c = 1:n_cond
    data_pts = data(:, c);
    valid = ~isnan(data_pts);
    scatter(ones(sum(valid), 1) * c, data_pts(valid), 15, colors(c,:), 'o', ...
        'MarkerEdgeColor', [0, 0, 0], ...
        'MarkerEdgeAlpha', 0.4, ...
        'MarkerFaceAlpha', 0.4, ...
        'LineWidth', 0.5);
end

% --- Significance brackets ---
max_pt = max(data(:), [], 'omitnan');
y_off  = max_pt * 1.15;
bracket_h = range([means(:); data(:)]) * 0.05;
has_sig = false;

for k = 1:length(posthoc)
    if posthoc(k).p_holm < pub.alpha
        has_sig = true;
        c1 = posthoc(k).pairs(1);
        c2 = posthoc(k).pairs(2);

        % Horizontal bracket
        plot([c1 c2], [y_off y_off], 'k-', 'LineWidth', 1.5);

        % Significance stars
        if posthoc(k).p_holm < 0.001
            sig = '***';
        elseif posthoc(k).p_holm < 0.01
            sig = '**';
        else
            sig = '*';
        end
        text(mean([c1 c2]), y_off + bracket_h * 0.3, sig, ...
            'HorizontalAlignment', 'center', ...
            'FontSize', 10, 'FontWeight', 'bold');

        y_off = y_off + bracket_h * 2;
    end
end

if has_sig
    ylim([0, y_off + bracket_h]);
end

hold off;

% --- Axis formatting ---
set(gca, 'XTick', 1:n_cond, 'XTickLabel', cond_labels, ...
    'FontName', pub.font_name, 'FontSize', pub.font_size_axis, ...
    'Box', 'off', 'TickDir', 'out');
ylabel('Estimated Spindle Probability', ...
    'FontName', pub.font_name, ...
    'FontSize', pub.font_size_label, 'FontWeight', 'bold');
% No title p-value on this plot
grid on;

%% Save
filename_base = 'emm_barplot_M0_condition';
print(fig, fullfile(OUTPUT_DIR, [filename_base '.png']), '-dpng', '-r300');
print(fig, fullfile(OUTPUT_DIR, [filename_base '.svg']), '-dsvg', '-vector');
savefig(fig, fullfile(OUTPUT_DIR, [filename_base '.fig']));

fprintf('M0 barplot saved to: %s (.png, .svg, .fig)\n', OUTPUT_DIR);

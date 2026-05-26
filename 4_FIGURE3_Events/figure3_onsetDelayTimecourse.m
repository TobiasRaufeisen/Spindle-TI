function figure3_onsetDelayTimecourse()
%% FIGURE 3: Spindle Onset Delay Timecourse "Horse Race"
% Shows spindles as timecourse traces across conditions
% X-axis: Time from condition onset (0-2+ seconds)
% Y-axis: Conditions (OFF, 5Hz, 1Hz) in separate rows
% Displays: Average onset, peak, and end markers with simulated spindle waveforms
% Waveform shows average number of oscillations based on frequency and duration

clear; clc;

% Configuration
% Paths
scriptFile = mfilename('fullpath');
if isempty(scriptFile) || startsWith(scriptFile, tempdir)
    scriptFile = matlab.desktop.editor.getActiveFilename;
end
REPO_ROOT = fileparts(fileparts(scriptFile));  % repo root (portable)
RESULTS_DIR = fullfile(REPO_ROOT, '1_eventDetection', 'eventDetectionResults');
DATA_FILE = fullfile(RESULTS_DIR, 'comprehensive_analysis.mat');
OUTPUT_DIR = fullfile(REPO_ROOT, '4_FIGURE3_Events', 'outputs');

% Analysis parameters
conditions = {'OFF', 'x5HZ', 'x1HZ'};
condition_labels = {'OFF', '5 Hz', '1 Hz'};
sleep_stages = {'N2'};
roi_electrodes = 'all';  % Or set to 'all' to use all electrodes

% Spindle filtering criteria
freq_range = [12, 16];
dur_range = [0.3, 3.0];
amp_range = [15, 100];
delay_max_window = 8.0;  % Maximum delay to consider (seconds)

% Visualization parameters
time_window = [0, 2.0];  % Time window to display (will extend if needed)
waveform_amplitude = 0.25;  % Visual amplitude of spindle waveform (relative to row spacing)

% Publication settings
pub = struct();
pub.fig_width_cm = 14;
pub.fig_height_cm = 8;
pub.font_name = 'Arial';
pub.font_size_axis = 10;
pub.font_size_label = 11;
pub.font_size_title = 12;
pub.marker_size = 100;  % For scatter markers
pub.line_width = 2;

% Colors for conditions
colors = [
    0.6, 0.6, 0.6;   % Gray for OFF
    1.0, 0.55, 0.0;  % Orange for x5HZ
    0.0, 0.2, 0.6    % Dark blue for x1HZ
];

fprintf('=== FIGURE 3: Spindle Timecourse ===\n');

% Load Data
fprintf('\nLoading data...\n');
loaded = load(DATA_FILE, 'all_spindles');
spindles = loaded.all_spindles;
fprintf('Loaded %d spindles\n', height(spindles));

% Filter and Prepare Data
fprintf('\nFiltering spindles...\n');

% Extract primary channels
primary_channels = cellfun(@(x) extract_primary_channel(x), ...
    spindles.Channel, 'UniformOutput', false);
spindles.PrimaryChannel = primary_channels;

% Compute onset delay and end time
if ismember('ConditionStartTime', spindles.Properties.VariableNames) && ...
   ismember('Start', spindles.Properties.VariableNames)
    spindles.OnsetDelay = spindles.Start - spindles.ConditionStartTime;
    spindles.EndDelay = spindles.OnsetDelay + spindles.Duration;
    spindles.PeakDelay = spindles.OnsetDelay + spindles.Duration / 2;  % Assume peak at midpoint
else
    error('Cannot compute onset delay (missing ConditionStartTime or Start)');
end

% Apply filters
spindles = spindles(ismember(spindles.SleepStage, sleep_stages), :);
spindles = spindles(ismember(spindles.Condition, conditions), :);

% Handle 'all' electrodes option
if ischar(roi_electrodes) && strcmpi(roi_electrodes, 'all')
    roi_electrodes = unique(spindles.PrimaryChannel);
    fprintf('Using all electrodes: %s\n', strjoin(roi_electrodes, ', '));
end

spindles = spindles(ismember(spindles.PrimaryChannel, roi_electrodes), :);

spindles = spindles(spindles.Frequency >= freq_range(1) & ...
                   spindles.Frequency <= freq_range(2), :);
spindles = spindles(spindles.Duration >= dur_range(1) & ...
                   spindles.Duration <= dur_range(2), :);
spindles = spindles(spindles.Amplitude >= amp_range(1) & ...
                   spindles.Amplitude <= amp_range(2), :);

% Filter by valid onset delay
spindles = spindles(spindles.OnsetDelay >= 0 & ...
                   spindles.OnsetDelay <= delay_max_window & ...
                   isfinite(spindles.OnsetDelay), :);

fprintf('Final filtered spindles: %d\n', height(spindles));

% Calculate Average Spindle Characteristics per Condition
fprintf('\nCalculating average spindle characteristics...\n');

n_cond = length(conditions);
avg_stats = struct();

for c = 1:n_cond
    cond = conditions{c};
    cond_mask = strcmp(spindles.Condition, cond);
    cond_spindles = spindles(cond_mask, :);

    if height(cond_spindles) > 0
        avg_stats.(cond).onset = mean(cond_spindles.OnsetDelay, 'omitnan');
        avg_stats.(cond).peak = mean(cond_spindles.PeakDelay, 'omitnan');
        avg_stats.(cond).end = mean(cond_spindles.EndDelay, 'omitnan');
        avg_stats.(cond).duration = mean(cond_spindles.Duration, 'omitnan');
        avg_stats.(cond).frequency = mean(cond_spindles.Frequency, 'omitnan');
        avg_stats.(cond).amplitude = mean(cond_spindles.Amplitude, 'omitnan');  % Average YASA amplitude
        avg_stats.(cond).n_oscillations = avg_stats.(cond).frequency * avg_stats.(cond).duration;
        avg_stats.(cond).n_spindles = height(cond_spindles);

        % SEMs for error bars
        avg_stats.(cond).onset_sem = std(cond_spindles.OnsetDelay, 'omitnan') / sqrt(sum(~isnan(cond_spindles.OnsetDelay)));
        avg_stats.(cond).peak_sem = std(cond_spindles.PeakDelay, 'omitnan') / sqrt(sum(~isnan(cond_spindles.PeakDelay)));
        avg_stats.(cond).end_sem = std(cond_spindles.EndDelay, 'omitnan') / sqrt(sum(~isnan(cond_spindles.EndDelay)));

        fprintf('  %s: onset=%.3fs, peak=%.3fs, end=%.3fs, freq=%.2fHz, amp=%.1fuV, n_osc=%.1f, n=%d\n', ...
            cond, avg_stats.(cond).onset, avg_stats.(cond).peak, avg_stats.(cond).end, ...
            avg_stats.(cond).frequency, avg_stats.(cond).amplitude, avg_stats.(cond).n_oscillations, avg_stats.(cond).n_spindles);
    else
        fprintf('  %s: No spindles found!\n', cond);
        avg_stats.(cond) = struct('onset', NaN, 'peak', NaN, 'end', NaN, ...
            'duration', NaN, 'frequency', NaN, 'amplitude', NaN, 'n_oscillations', NaN, 'n_spindles', 0);
    end
end

% Extend time window if needed to show all spindles
max_end_time = 0;
for c = 1:n_cond
    cond = conditions{c};
    if ~isnan(avg_stats.(cond).end)
        max_end_time = max(max_end_time, avg_stats.(cond).end);
    end
end
time_window(2) = max(time_window(2), ceil(max_end_time * 1.1));

fprintf('\nTime window: [%.1f, %.1f] seconds\n', time_window(1), time_window(2));

% Calculate amplitude normalization factor for visualization
% Find max amplitude across all conditions for scaling
max_amplitude = 0;
for c = 1:n_cond
    cond = conditions{c};
    if ~isnan(avg_stats.(cond).amplitude)
        max_amplitude = max(max_amplitude, avg_stats.(cond).amplitude);
    end
end
fprintf('Max amplitude across conditions: %.1f uV\n', max_amplitude);

% Create Figure
fprintf('\nCreating figure...\n');

if ~exist(OUTPUT_DIR, 'dir')
    mkdir(OUTPUT_DIR);
end

fig = figure('Units', 'centimeters', ...
             'Position', [5, 5, pub.fig_width_cm, pub.fig_height_cm], ...
             'Color', 'white', ...
             'PaperUnits', 'centimeters', ...
             'PaperSize', [pub.fig_width_cm, pub.fig_height_cm], ...
             'PaperPosition', [0, 0, pub.fig_width_cm, pub.fig_height_cm]);

hold on;

% Y-positions for each condition (reversed for top-to-bottom: OFF, 5Hz, 1Hz)
% Closer spacing to remove gaps between conditions
y_positions = [2.6, 1.8, 1.0];  % OFF at top, 1Hz at bottom

% Draw condition backgrounds and labels
for c = 1:n_cond
    cond = conditions{c};
    y_pos = y_positions(c);

    % Light background rectangle
    rectangle('Position', [time_window(1), y_pos - 0.4, time_window(2) - time_window(1), 0.8], ...
        'FaceColor', [colors(c,:), 0.1], 'EdgeColor', 'none');

    % Baseline (zero line)
    plot(time_window, [y_pos, y_pos], 'k-', 'LineWidth', 0.5, 'Color', [0.3, 0.3, 0.3]);

    % Condition label on left
    text(time_window(1) - 0.15, y_pos, condition_labels{c}, ...
        'FontName', pub.font_name, 'FontSize', pub.font_size_label, ...
        'FontWeight', 'bold', 'HorizontalAlignment', 'right', ...
        'VerticalAlignment', 'middle', 'Color', colors(c,:));
end

% Plot spindle timecourse for each condition
for c = 1:n_cond
    cond = conditions{c};
    y_pos = y_positions(c);
    stats = avg_stats.(cond);

    if isnan(stats.onset)
        continue;
    end

    % Generate simulated spindle waveform
    t_start = stats.onset;
    t_end = stats.end;
    t_peak = stats.peak;

    % Time vector for waveform (high resolution)
    t_waveform = linspace(t_start, t_end, 1000);

    % Oscillation: sine wave with frequency
    oscillation = sin(2 * pi * stats.frequency * (t_waveform - t_start));

    % Envelope: Gaussian-like amplitude modulation peaking at center
    envelope = exp(-4 * ((t_waveform - t_peak).^2) / (stats.duration^2));

    % Scale amplitude based on detected YASA amplitude (normalized to max)
    amplitude_scale = (stats.amplitude / max_amplitude) * waveform_amplitude;

    % Combined waveform with YASA-detected amplitude
    waveform = y_pos + amplitude_scale * oscillation .* envelope;

    % Plot waveform
    plot(t_waveform, waveform, '-', 'Color', colors(c,:), ...
        'LineWidth', pub.line_width);

    % Plot vertical lines for onset and end
    % Onset line
    plot([stats.onset, stats.onset], [y_pos - 0.3, y_pos + 0.3], '-', ...
        'Color', colors(c,:), 'LineWidth', pub.line_width);

    % Peak marker (triangle)
    scatter(stats.peak, y_pos, pub.marker_size * 1.2, '^', ...
        'MarkerFaceColor', colors(c,:), 'MarkerEdgeColor', 'k', ...
        'LineWidth', 1.5, 'MarkerFaceAlpha', 0.8);

    % End line
    plot([stats.end, stats.end], [y_pos - 0.3, y_pos + 0.3], '-', ...
        'Color', colors(c,:), 'LineWidth', pub.line_width);

    % Add text annotations for key times
    text(stats.onset, y_pos + 0.35, sprintf('%.2fs', stats.onset), ...
        'FontName', pub.font_name, 'FontSize', 8, ...
        'HorizontalAlignment', 'center', 'Color', colors(c,:), 'FontWeight', 'bold');

    text(stats.end, y_pos + 0.35, sprintf('%.2fs', stats.end), ...
        'FontName', pub.font_name, 'FontSize', 8, ...
        'HorizontalAlignment', 'center', 'Color', colors(c,:), 'FontWeight', 'bold');

    % Add oscillation count annotation
    text(t_peak, y_pos - 0.35, sprintf('%.1f cycles', stats.n_oscillations), ...
        'FontName', pub.font_name, 'FontSize', 8, ...
        'HorizontalAlignment', 'center', 'Color', colors(c,:), 'FontAngle', 'italic');

    % Add amplitude axis description on the left side (inside plot, next to condition label)
    % Calculate the visual amplitude extent
    amplitude_scale = (stats.amplitude / max_amplitude) * waveform_amplitude;

    % YASA amplitude is already peak-to-peak
    peak_to_peak = stats.amplitude;  % YASA amplitude is already peak-to-peak

    % Draw small vertical scale bar on the left (inside the plot)
    scale_x = time_window(1) + 0.08;
    plot([scale_x, scale_x], [y_pos - amplitude_scale, y_pos + amplitude_scale], '-', ...
        'Color', [0.3, 0.3, 0.3], 'LineWidth', 1.5);
    plot([scale_x - 0.02, scale_x + 0.02], [y_pos - amplitude_scale, y_pos - amplitude_scale], '-', ...
        'Color', [0.3, 0.3, 0.3], 'LineWidth', 1.5);  % Bottom tick
    plot([scale_x - 0.02, scale_x + 0.02], [y_pos + amplitude_scale, y_pos + amplitude_scale], '-', ...
        'Color', [0.3, 0.3, 0.3], 'LineWidth', 1.5);  % Top tick

    % Add amplitude label showing peak-to-peak (positioned slightly above center)
    text(scale_x + 0.06, y_pos + 0.08, sprintf('%.0f \\muV', peak_to_peak), ...
        'FontName', pub.font_name, 'FontSize', 7, ...
        'HorizontalAlignment', 'left', 'VerticalAlignment', 'middle', 'Color', [0.3, 0.3, 0.3]);
end

% Draw vertical line at condition onset (t=0)
plot([0, 0], [0.5, 3.1], 'k--', 'LineWidth', 2);

hold off;

% Formatting
xlim(time_window);
ylim([0.5, 3.1]);
set(gca, 'YTick', [], 'YTickLabel', {});  % Hide y-axis ticks (we have custom labels)
set(gca, 'FontName', pub.font_name, 'FontSize', pub.font_size_axis, ...
    'Box', 'off', 'TickDir', 'out');

xlabel('Time from Condition Onset (s)', 'FontName', pub.font_name, ...
    'FontSize', pub.font_size_label, 'FontWeight', 'bold');

title(sprintf('Spindle Timecourse (ROI: %s, N2 Sleep)', ...
    strjoin(roi_electrodes, ', ')), ...
    'FontName', pub.font_name, 'FontSize', pub.font_size_title, 'FontWeight', 'bold');

grid on;

%% Save Figure
filename_base = 'figure3_onsetDelayTimecourse_Cz';

print(fig, fullfile(OUTPUT_DIR, [filename_base '.png']), '-dpng', '-r300');
set(fig, 'Renderer', 'painters');  % Ensure vector output
print(fig, fullfile(OUTPUT_DIR, [filename_base '.svg']), '-dsvg', '-painters');
savefig(fig, fullfile(OUTPUT_DIR, [filename_base '.fig']));

save(fullfile(OUTPUT_DIR, [filename_base '.mat']), ...
     'avg_stats', 'conditions', 'condition_labels', 'roi_electrodes', ...
     'time_window', 'colors', 'pub', '-v7.3');

fprintf('\nFigure saved to: %s\n', OUTPUT_DIR);
fprintf('  - %s.png (300 DPI)\n', filename_base);
fprintf('  - %s.svg\n', filename_base);
fprintf('  - %s.fig\n', filename_base);
fprintf('  - %s.mat (data)\n', filename_base);
fprintf('=== Done ===\n');

end

%% Helper Functions

function primary = extract_primary_channel(ch)
    if iscell(ch), ch = ch{1}; end
    ch = strtok(ch, '+');
    ch = regexprep(ch, 'A[12]', '');
    ch = regexprep(ch, '[^A-Za-z0-9]', '');
    primary = upper(ch);
end

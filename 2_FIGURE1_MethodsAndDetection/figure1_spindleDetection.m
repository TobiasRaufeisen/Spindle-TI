function figure1_spindleDetection()
%% FIGURE 1: Example EEG Trials with Spindle Detection
% Shows representative trials from each condition (OFF, 1Hz, 5Hz) with
% detected spindles marked, demonstrating that spindle detection works
% across all conditions
%
% This validates that the analysis is not biased by stimulation

clear; clc;

% Configuration
scriptFile = mfilename('fullpath');
if isempty(scriptFile) || startsWith(scriptFile, tempdir)
    scriptFile = matlab.desktop.editor.getActiveFilename;
end
REPO_ROOT = fileparts(fileparts(scriptFile));  % repo root (portable)
PROCESSED_DATA_DIR = fullfile(REPO_ROOT, 'data');  % in-repo, gitignored (see README "Data Availability")
RESULTS_DIR = fullfile(REPO_ROOT, '1_eventDetection', 'eventDetectionResults');
OUTPUT_DIR = fullfile(REPO_ROOT, '2_FIGURE1_MethodsAndDetection', 'outputs');

% Subject and session
participant = 'sub11';
session = 'ses1';

% Trial selection
selected_trials = struct('x5HZ', 22, 'x1HZ', 25, 'OFF', 33);

% Analysis parameters
electrode = 'Cz';  % Single electrode for clarity
conditions = {'x5HZ', 'x1HZ', 'OFF'};
condition_labels = {'5 Hz', '1 Hz', 'OFF'};
time_window = [-1, 4];  % Time relative to condition onset (seconds)

% Publication settings
pub = struct();
pub.fig_width_cm = 8.5;
pub.fig_height_cm = 12;
pub.font_name = 'Arial';
pub.font_size_axis = 7;
pub.font_size_label = 8;
pub.font_size_title = 9;
pub.line_width = 1.0;
pub.marker_size = 5;
pub.scale_bar_uV = 75;
pub.colors = {[1.00, 0.55, 0.00], ...    % Orange (5 Hz)
              [0.00, 0.20, 0.60], ...    % Dark Blue (1 Hz)
              [0.55, 0.55, 0.55]};       % Gray (OFF)
pub.ti_color = [0.85, 0.65, 0.10];       % TIS indicator color

fprintf('=== FIGURE 1: Spindle Detection Examples ===\n');
fprintf('Subject: %s %s, Electrode: %s\n', participant, session, electrode);

% Load data
analysis_data_path = fullfile(PROCESSED_DATA_DIR, 'analysis');
analysis_file = fullfile(analysis_data_path, sprintf('%s_%s_ANALYSIS.mat', participant, session));

fprintf('Loading analysis data...\n');
if ~exist(analysis_file, 'file')
    error('Analysis file not found: %s', analysis_file);
end
load(analysis_file, 'analysisData_saved');

participant_data = analysisData_saved.(participant).(session);
clear analysisData_saved;

% Load spindle detection data
spindle_file = fullfile(RESULTS_DIR, 'comprehensive_analysis.mat');
fprintf('Loading spindle data...\n');
if ~exist(spindle_file, 'file')
    error('Spindle file not found: %s', spindle_file);
end
load(spindle_file, 'all_spindles');

fprintf('Data loaded successfully\n');

% Extract data and create figure
continuous_eeg = participant_data.eeg.trial{1};
fs = participant_data.eeg.fsample;
channel_labels = participant_data.eeg.label;

% Find electrode index
elec_idx = find(strcmp(channel_labels, electrode));
if isempty(elec_idx)
    error('Electrode %s not found', electrode);
end

fprintf('Sampling rate: %d Hz\n', fs);

% Create figure
fig = figure('Units', 'centimeters', ...
             'Position', [5, 5, pub.fig_width_cm, pub.fig_height_cm], ...
             'Color', 'white', ...
             'PaperUnits', 'centimeters', ...
             'PaperSize', [pub.fig_width_cm, pub.fig_height_cm], ...
             'PaperPosition', [0, 0, pub.fig_width_cm, pub.fig_height_cm]);

% Subplot layout
n_cond = length(conditions);
margin_left = 0.15;
margin_right = 0.05;
margin_top = 0.06;
margin_bottom = 0.10;
subplot_gap = 0.08;
subplot_width = 1 - margin_left - margin_right;
subplot_height = (1 - margin_top - margin_bottom - (n_cond-1)*subplot_gap) / n_cond;

% Process each condition
pre_samples = round(abs(time_window(1)) * fs);
post_samples = round(time_window(2) * fs);

for c = 1:n_cond
    condition = conditions{c};
    trial_idx = selected_trials.(condition);

    fprintf('\nProcessing %s, trial %d\n', condition, trial_idx);

    % Get trial data
    epoch_data = participant_data.epochedData.(condition);

    % Get condition onset sample
    condition_onset = getOnsetSample(epoch_data, trial_idx, fs);
    win_start = max(1, condition_onset - pre_samples);
    win_end = min(size(continuous_eeg, 2), condition_onset + post_samples - 1);

    % Extract EEG segment
    eeg_segment = continuous_eeg(elec_idx, win_start:win_end);
    eeg_segment = eeg_segment - mean(eeg_segment);  % Baseline correct

    % Create time vector
    n_samples = length(eeg_segment);
    actual_pre = condition_onset - win_start;
    plot_time = ((-actual_pre):(n_samples-actual_pre-1)) / fs;

    % Get spindle peaks for this trial
    spindle_peaks = getSpindlePeaksInTrial(all_spindles, participant, condition, ...
                                           electrode, win_start, win_end, ...
                                           condition_onset, fs, time_window);

    % Create subplot
    subplot_bottom = 1 - margin_top - c*subplot_height - (c-1)*subplot_gap;
    ax = axes('Position', [margin_left, subplot_bottom, subplot_width, subplot_height]);

    hold on;

    % Plot EEG trace
    plot(plot_time, eeg_segment, 'Color', pub.colors{c}, 'LineWidth', pub.line_width);

    % Add stimulus onset line
    y_lim = [-pub.scale_bar_uV, pub.scale_bar_uV];
    plot([0, 0], y_lim, 'k--', 'LineWidth', 0.8);

    % Mark detected spindles
    if ~isempty(spindle_peaks)
        marker_y = y_lim(2) * 0.85;  % Fixed position near top of plot
        for p = 1:length(spindle_peaks)
            plot(spindle_peaks(p), marker_y, 'v', ...
                 'MarkerSize', pub.marker_size, 'MarkerFaceColor', [0.2, 0.2, 0.2], ...
                 'MarkerEdgeColor', 'k', 'LineWidth', 0.5);
        end
        fprintf('  Found %d spindles\n', length(spindle_peaks));
    else
        fprintf('  No spindles detected\n');
    end

    % Formatting
    xlim(time_window);
    ylim(y_lim);
    set(gca, 'FontName', pub.font_name, 'FontSize', pub.font_size_axis, ...
             'Box', 'off', 'TickDir', 'out', 'YTick', [], 'YColor', 'none');

    % X-axis labels only on bottom subplot
    if c == n_cond
        xlabel('Time (s)', 'FontName', pub.font_name, 'FontSize', pub.font_size_label);
    end

    % Add condition label
    text(time_window(1) + 0.1, y_lim(2) * 0.85, condition_labels{c}, ...
         'FontName', pub.font_name, 'FontSize', pub.font_size_title, ...
         'FontWeight', 'bold', 'Color', pub.colors{c});

    % Add scale bar
    scale_x = time_window(1) - 0.15;
    scale_y = [-pub.scale_bar_uV/2, pub.scale_bar_uV/2];
    plot([scale_x, scale_x], scale_y, 'k-', 'LineWidth', 1.3, 'Clipping', 'off');
    text(scale_x - 0.1, 0, sprintf('%d uV', pub.scale_bar_uV), ...
         'FontName', pub.font_name, 'FontSize', pub.font_size_axis, ...
         'HorizontalAlignment', 'right', 'VerticalAlignment', 'middle', ...
         'Clipping', 'off');

    % Add TIS indicator below the trace (frequency-specific envelope)
    y_range = diff(y_lim);
    ti_center = y_lim(1) + 0.08 * y_range;
    ti_amp = 0.06 * y_range;

    % Set frequency based on condition
    if strcmp(condition, 'x5HZ')
        ti_freq = 2.5;
    elseif strcmp(condition, 'x1HZ')
        ti_freq = 0.5;
    else
        ti_freq = 0;
    end

    ti_end = min(2, time_window(2));  % Stimulation runs for first 2 s
    if ti_freq > 0
        ti_mask = plot_time >= 0 & plot_time <= ti_end;
        ti_time = plot_time(ti_mask);
        if ~isempty(ti_time)
            % TIS envelope: double-sided, filled, full-wave rectified sine (phase 0 at t=0)
            env = abs(sin(2*pi*ti_freq*ti_time));
            upper = ti_center + ti_amp * env;
            lower = ti_center - ti_amp * env;
            fill([ti_time, fliplr(ti_time)], [upper, fliplr(lower)], pub.ti_color, ...
                 'FaceAlpha', 0.75, 'EdgeColor', 'none', 'Clipping', 'off');
            ti_label_x = ti_time(1) + 0.02 * ti_end;
            ti_label_y = ti_center + 1.8 * ti_amp;
            lbl_ti = text(ti_label_x, ti_label_y, 'TIS', ...
                'FontName', pub.font_name, 'FontSize', pub.font_size_axis, ...
                'Color', pub.ti_color, 'HorizontalAlignment', 'left', ...
                'VerticalAlignment', 'middle');
            set(lbl_ti, 'Clipping', 'off');
        end
    else
        % OFF: flat line to indicate no envelope
        plot([0, ti_end], [ti_center, ti_center], 'Color', pub.ti_color, 'LineWidth', 1.0, 'Clipping', 'off');
    end

    hold off;
end

%% Save figure
if ~exist(OUTPUT_DIR, 'dir')
    mkdir(OUTPUT_DIR);
end

filename_base = sprintf('figure1_spindleDetection_%s_%s', participant, session);
print(fig, fullfile(OUTPUT_DIR, [filename_base '.png']), '-dpng', '-r300');
set(fig, 'Renderer', 'painters');  % Ensure vector output
print(fig, fullfile(OUTPUT_DIR, [filename_base '.svg']), '-dsvg', '-painters');
savefig(fig, fullfile(OUTPUT_DIR, [filename_base '.fig']));

% Save data
save(fullfile(OUTPUT_DIR, [filename_base '.mat']), ...
     'selected_trials', 'conditions', 'electrode', 'participant', 'session', ...
     'time_window', 'pub');

fprintf('\nFigure saved to: %s\n', OUTPUT_DIR);
fprintf('  - %s.png (300 DPI)\n', filename_base);
fprintf('  - %s.svg\n', filename_base);
fprintf('  - %s.fig\n', filename_base);
fprintf('  - %s.mat (data)\n', filename_base);
fprintf('=== Done ===\n');

end

%% Helper functions
function onset_sample = getOnsetSample(epoch_data, trial_idx, fs)
    onset_sample = epoch_data.sampleinfo(trial_idx, 1);
    if isfield(epoch_data, 'time') && numel(epoch_data.time) >= trial_idx
        offset_samples = round(epoch_data.time{trial_idx}(1) * fs);
        onset_sample = onset_sample - offset_samples;
    end
end

function peaks_rel = getSpindlePeaksInTrial(spindle_tbl, subj, cond, elec, ...
                                            win_start, win_end, onset_sample, fs, tw)
    peaks_rel = [];
    if isempty(spindle_tbl)
        return;
    end

    % Map condition names
    cond_map = containers.Map({'x1HZ', 'x5HZ', 'OFF'}, {'1HZ', '5HZ', 'OFF'});
    if cond_map.isKey(cond)
        cond = cond_map(cond);
    end

    % Filter spindle table
    mask = strcmp(spindle_tbl.Subject, subj) & ...
           contains(string(spindle_tbl.Condition), cond, 'IgnoreCase', true) & ...
           contains(spindle_tbl.Channel, elec);
    sub_tbl = spindle_tbl(mask, :);

    if isempty(sub_tbl)
        return;
    end

    % Filter to current trial window
    if ismember('EventSample', sub_tbl.Properties.VariableNames)
        trial_mask = sub_tbl.EventSample >= win_start & sub_tbl.EventSample <= win_end;
        sub_tbl = sub_tbl(trial_mask, :);
    end

    if isempty(sub_tbl)
        return;
    end

    % Extract peak times
    vars = sub_tbl.Properties.VariableNames;
    if ismember('PeakSample', vars)
        peak_times_rel = (sub_tbl.PeakSample - onset_sample) / fs;
    elseif ismember('Peak', vars)
        peak_times_rel = sub_tbl.Peak - (onset_sample / fs);
    elseif ismember('Start', vars)
        onset_time = onset_sample / fs;
        peak_times_rel = sub_tbl.Start - onset_time;
        if ismember('Duration', vars)
            peak_times_rel = peak_times_rel + sub_tbl.Duration / 2;
        end
    else
        return;
    end

    % Filter to time window
    in_window = peak_times_rel >= tw(1) & peak_times_rel <= tw(2);
    peaks_rel = unique(peak_times_rel(in_window));
end

%% 1. Load Data, Correct EEG Timestamps, and Align Streams
data = load_xdf('D:\data\SpindlePilot\sub-P999\ses-S020\eeg\sub-P999_ses-S020_task-Default_run-001_eeg.xdf');

% Recreate EEG timestamps at 25000 Hz and add its first_timestamp
nSamples = size(data{1,3}.time_series, 2);
newEEGTimeStamps = (0:nSamples-1) / 25000;
firstTimestamp = str2double(data{1,3}.info.first_timestamp);
data{1,3}.time_stamps = newEEGTimeStamps + firstTimestamp;

% Align streams (LSL: data{1,2}, EEG: data{1,3}, DAQ: data{1,4})
global_min = min([min(data{1,2}.time_stamps), min(data{1,3}.time_stamps), min(data{1,4}.time_stamps)]);
data{1,2}.time_stamps = data{1,2}.time_stamps - global_min;
data{1,3}.time_stamps = data{1,3}.time_stamps - global_min;
data{1,4}.time_stamps = data{1,4}.time_stamps - global_min;
fprintf('LSL: %.4f, EEG: %.4f, DAQ: %.4f\n', data{1,2}.time_stamps(1), data{1,3}.time_stamps(1), data{1,4}.time_stamps(1));

%% 2. Extract Trigger Start Times from Each Stream
% LSL markers (data{1,2}) use the label 'DEFAULT_START'
LSL_start = data{1,2}.time_stamps(strcmp(data{1,2}.time_series, 'DEFAULT_START'));

% EEG markers from channel 2 in data{1,3} (detect rising edge from -1 to 255)
eeg_time = data{1,3}.time_stamps;
eeg_digital = double(data{1,3}.time_series(2,:));
raw_idx = find(diff(eeg_digital) == 256) + 1;  % each rising edge
EEG_start = eeg_time(raw_idx);
% (No trimming is done at this stage; all detected triggers are kept.)

% DAQ markers from channel 4 in data{1,4} (spike detection)
daq_time = data{1,4}.time_stamps;
daq_signal = double(data{1,4}.time_series(4,:));
baseline = median(daq_signal);
sigma = std(daq_signal);
minPeakHeight = baseline + 3*sigma;
[~, DAQ_start] = findpeaks(daq_signal, daq_time, 'MinPeakHeight', minPeakHeight, 'MinPeakDistance', 0.1);

%% 3. Match Triggers Across Streams
% Choose the stream with the fewest triggers as reference.
nLSL = length(LSL_start); nEEG = length(EEG_start); nDAQ = length(DAQ_start);
[count, refIdx] = min([nLSL, nEEG, nDAQ]);
switch refIdx
    case 1, refName = 'LSL'; refTrig = LSL_start; other1 = EEG_start; other2 = DAQ_start;
    case 2, refName = 'EEG'; refTrig = EEG_start; other1 = LSL_start; other2 = DAQ_start;
    case 3, refName = 'DAQ'; refTrig = DAQ_start; other1 = LSL_start; other2 = EEG_start;
end

matchedRef = refTrig;
matchedOther1 = zeros(length(refTrig),1);
matchedOther2 = zeros(length(refTrig),1);
for i = 1:length(refTrig)
    t = refTrig(i);
    [~, idx1] = min(abs(other1 - t));
    matchedOther1(i) = other1(idx1);
    [~, idx2] = min(abs(other2 - t));
    matchedOther2(i) = other2(idx2);
end

% Now, reorganize matches so that the table always lists LSL, EEG, and DAQ triggers.
switch refName
    case 'LSL'
        LSL_matched = matchedRef;
        EEG_matched = matchedOther1;
        DAQ_matched = matchedOther2;
    case 'EEG'
        EEG_matched = matchedRef;
        LSL_matched = matchedOther1;
        DAQ_matched = matchedOther2;
    case 'DAQ'
        DAQ_matched = matchedRef;
        LSL_matched = matchedOther1;
        EEG_matched = matchedOther2;
end

%% 4. Compute Delays Relative to LSL
LSL_matched = LSL_matched';
EEG_delay = EEG_matched - LSL_matched;
DAQ_delay = DAQ_matched - LSL_matched;

%% 5. Descriptive Statistics, Summary Table, and Plots

% Remove the outlier from DAQ_delay by replacing it with the median value.
[~, idx] = min(DAQ_delay);    % find the index of the smallest delay
DAQ_delay(idx) = median(DAQ_delay);

nMatched = length(LSL_matched);
fprintf('Matched triggers: %d\n', nMatched);
fprintf('EEG delay:  mean = %.4f s, std = %.4f s\n', mean(EEG_delay), std(EEG_delay));
fprintf('DAQ delay:  mean = %.4f s, std = %.4f s\n', mean(DAQ_delay), std(DAQ_delay));

Pair = (1:nMatched)';
Summary = table(Pair, LSL_matched, EEG_matched, DAQ_matched, EEG_delay, DAQ_delay, ...
    'VariableNames', {'Pair','LSL_Start','EEG_Start','DAQ_Start','EEG_Delay','DAQ_Delay'});
disp(Summary);

figure;
hold on;
plot(LSL_matched, ones(nMatched,1), 'bo','MarkerFaceColor','b');
plot(EEG_matched, ones(nMatched,1)*0.8, 'ks','MarkerFaceColor','k');
plot(DAQ_matched, ones(nMatched,1)*0.6, 'mo','MarkerFaceColor','m');
legend('LSL','EEG','DAQ','Location','best');
xlabel('Time (s)'); ylabel('Trigger Indicator');
title('Matched Trigger Start Times');
hold off;

figure;
subplot(2,1,1);
histogram(EEG_delay,30);
xlabel('EEG Delay (s)'); ylabel('Count');
title('Histogram of EEG Delays');
subplot(2,1,2);
histogram(DAQ_delay,30);
xlabel('DAQ Delay (s)'); ylabel('Count');
title('Histogram of DAQ Delays');

%% 9. Additional Plot: Compare EEG vs. DAQ Delay
figure;
scatter(EEG_delay, DAQ_delay, 'filled');
hold on;
lims = [min([EEG_delay; DAQ_delay]), max([EEG_delay; DAQ_delay])];
plot(lims, lims, 'r--','LineWidth',2);  % Plot y=x line for reference
xlabel('EEG Delay (s)');
ylabel('DAQ Delay (s)');
title('Scatter Plot: EEG Delay vs. DAQ Delay');
grid on;
hold off;

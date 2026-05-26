function spindlePilot_interactiveDataExplorer(allData, subjectID)
% SPINDLEPILOT_INTERACTIVEDATAEXPLORER Interactive EEG data visualization with live spectral analysis
%
% This function creates an interactive GUI for exploring EEG data with real-time
% power spectrum and time-frequency analysis for the currently visible window.
%
% USAGE:
%   spindlePilot_interactiveDataExplorer(allData, subjectID)
%
% INPUTS:
%   allData   - Structure containing preprocessed EEG data
%   subjectID - String specifying subject (e.g., 'sub24')
%
% FEATURES:
%   - Interactive scrolling through continuous EEG data
%   - Adjustable window length, amplitude scaling, and channel selection
%   - Live power spectrum computation for current window
%   - Live time-frequency analysis for current window
%   - Synchronized navigation across all displays
%
% EXAMPLE:
%   load('sub24_ses1_COMPLETE.mat');
%   spindlePilot_interactiveDataExplorer(allData, 'sub24');

%% Input validation and data extraction
if nargin < 2
    error('Both allData and subjectID are required inputs');
end

if ~isfield(allData, subjectID)
    error('Subject %s not found in allData structure', subjectID);
end

if ~isfield(allData.(subjectID).ses1, 'eeg_main')
    error('eeg_main data not found for %s', subjectID);
end

% Extract EEG data
eegData = allData.(subjectID).ses1.eeg_main;
data = eegData.trial{1}; % [channels x timepoints]
timeVec = eegData.time{1}; % time vector
channelLabels = eegData.label;
fs = eegData.fsample;

% Extract event markers
if isfield(allData.(subjectID).ses1, 'eventMarker')
    eventMarkers = allData.(subjectID).ses1.eventMarker;
    markerTimes = eventMarkers.time_stamps;
    markerLabels = eventMarkers.time_series;
    fprintf('Found %d event markers\n', length(markerTimes));
else
    markerTimes = [];
    markerLabels = {};
    fprintf('No event markers found\n');
end

fprintf('Loaded EEG data: %d channels, %.2f minutes, %.1f Hz sampling rate\n', ...
    size(data,1), timeVec(end)/60, fs);

%% Initialize GUI parameters
gui = struct();
gui.fs = fs;
gui.data = data;
gui.timeVec = timeVec;
gui.channelLabels = channelLabels;
gui.nChannels = length(channelLabels);
gui.totalTime = timeVec(end);

% Store event markers
gui.markerTimes = markerTimes;
gui.markerLabels = markerLabels;

% Default settings
gui.windowLength = 10; % seconds
gui.currentTime = 0; % start time
gui.amplitudeScale = 100; % microvolts
gui.selectedChannels = 1:min(16, gui.nChannels); % show first 16 channels
gui.channelSpacing = 1.2; % vertical spacing multiplier

% Spectral analysis parameters
gui.nfft = 2^nextpow2(gui.fs * 2); % 2-second window for FFT
gui.overlap = 0.5; % 50% overlap for time-frequency
gui.freqRange = [0.5, 40]; % frequency range for display

%% Create main figure
gui.fig = figure('Name', sprintf('EEG Explorer - %s', subjectID), ...
    'NumberTitle', 'off', 'Position', [100, 50, 1400, 900], ...
    'CloseRequestFcn', @closeFigure, 'KeyPressFcn', @keyPress);

% Create layout
gui.mainPanel = uipanel('Parent', gui.fig, 'Position', [0.25, 0, 0.75, 1], ...
    'BorderType', 'none');
gui.controlPanel = uipanel('Parent', gui.fig, 'Position', [0, 0, 0.25, 1], ...
    'Title', 'Controls', 'FontSize', 12, 'FontWeight', 'bold');

%% Create subplots in main panel
% EEG time series (top)
gui.ax_eeg = subplot(3, 1, 1, 'Parent', gui.mainPanel);
gui.ax_eeg.Position = [0.08, 0.7, 0.88, 0.25];
title('EEG Time Series', 'FontSize', 14, 'FontWeight', 'bold');
xlabel('Time (s)');
ylabel('Channels');
grid on;

% Power spectrum (bottom left)
gui.ax_power = subplot(3, 2, 5, 'Parent', gui.mainPanel);
gui.ax_power.Position = [0.08, 0.05, 0.4, 0.25];
title('Power Spectrum', 'FontSize', 12, 'FontWeight', 'bold');
xlabel('Frequency (Hz)');
ylabel('Power (μV²/Hz)');
grid on;
set(gui.ax_power, 'YScale', 'log');

% Time-frequency plot (bottom right)
gui.ax_tf = subplot(3, 2, 6, 'Parent', gui.mainPanel);
gui.ax_tf.Position = [0.52, 0.05, 0.43, 0.25];
title('Time-Frequency Analysis', 'FontSize', 12, 'FontWeight', 'bold');
xlabel('Time (s)');
ylabel('Frequency (Hz)');

%% Create control elements
yPos = 0.9;
spacing = 0.08;

% Time navigation
uicontrol('Parent', gui.controlPanel, 'Style', 'text', ...
    'String', 'Time Navigation', 'FontWeight', 'bold', ...
    'Units', 'normalized', 'Position', [0.05, yPos, 0.9, 0.04]);
yPos = yPos - spacing;

uicontrol('Parent', gui.controlPanel, 'Style', 'text', ...
    'String', 'Current Time (s):', ...
    'Units', 'normalized', 'Position', [0.05, yPos, 0.6, 0.04]);
gui.timeEdit = uicontrol('Parent', gui.controlPanel, 'Style', 'edit', ...
    'String', '0', 'Callback', @updateTimeFromEdit, ...
    'Units', 'normalized', 'Position', [0.65, yPos, 0.3, 0.04]);
yPos = yPos - spacing/2;

gui.timeSlider = uicontrol('Parent', gui.controlPanel, 'Style', 'slider', ...
    'Min', 0, 'Max', gui.totalTime-gui.windowLength, 'Value', 0, ...
    'Callback', @updateTimeFromSlider, ...
    'Units', 'normalized', 'Position', [0.05, yPos, 0.9, 0.04]);
yPos = yPos - spacing;

% Window length
uicontrol('Parent', gui.controlPanel, 'Style', 'text', ...
    'String', 'Window Length (s):', ...
    'Units', 'normalized', 'Position', [0.05, yPos, 0.6, 0.04]);
gui.windowEdit = uicontrol('Parent', gui.controlPanel, 'Style', 'edit', ...
    'String', num2str(gui.windowLength), 'Callback', @updateWindowLength, ...
    'Units', 'normalized', 'Position', [0.65, yPos, 0.3, 0.04]);
yPos = yPos - spacing;

% Amplitude scaling
uicontrol('Parent', gui.controlPanel, 'Style', 'text', ...
    'String', 'Amplitude Scale (μV):', ...
    'Units', 'normalized', 'Position', [0.05, yPos, 0.6, 0.04]);
gui.amplitudeEdit = uicontrol('Parent', gui.controlPanel, 'Style', 'edit', ...
    'String', num2str(gui.amplitudeScale), 'Callback', @updateAmplitudeScale, ...
    'Units', 'normalized', 'Position', [0.65, yPos, 0.3, 0.04]);
yPos = yPos - spacing;

% Channel selection
uicontrol('Parent', gui.controlPanel, 'Style', 'text', ...
    'String', 'Channel Selection', 'FontWeight', 'bold', ...
    'Units', 'normalized', 'Position', [0.05, yPos, 0.9, 0.04]);
yPos = yPos - spacing/2;

gui.channelList = uicontrol('Parent', gui.controlPanel, 'Style', 'listbox', ...
    'String', gui.channelLabels, 'Max', length(gui.channelLabels), ...
    'Value', gui.selectedChannels, 'Callback', @updateChannelSelection, ...
    'Units', 'normalized', 'Position', [0.05, yPos-0.25, 0.9, 0.25]);
yPos = yPos - 0.3;

% Navigation buttons
uicontrol('Parent', gui.controlPanel, 'Style', 'text', ...
    'String', 'Quick Navigation', 'FontWeight', 'bold', ...
    'Units', 'normalized', 'Position', [0.05, yPos, 0.9, 0.04]);
yPos = yPos - spacing/2;

uicontrol('Parent', gui.controlPanel, 'Style', 'pushbutton', ...
    'String', '← Prev', 'Callback', @previousWindow, ...
    'Units', 'normalized', 'Position', [0.05, yPos, 0.42, 0.05]);
uicontrol('Parent', gui.controlPanel, 'Style', 'pushbutton', ...
    'String', 'Next →', 'Callback', @nextWindow, ...
    'Units', 'normalized', 'Position', [0.53, yPos, 0.42, 0.05]);
yPos = yPos - spacing;

% Analysis options
uicontrol('Parent', gui.controlPanel, 'Style', 'text', ...
    'String', 'Analysis Options', 'FontWeight', 'bold', ...
    'Units', 'normalized', 'Position', [0.05, yPos, 0.9, 0.04]);
yPos = yPos - spacing/2;

uicontrol('Parent', gui.controlPanel, 'Style', 'text', ...
    'String', 'Freq Range (Hz):', ...
    'Units', 'normalized', 'Position', [0.05, yPos, 0.5, 0.04]);
gui.freqEdit = uicontrol('Parent', gui.controlPanel, 'Style', 'edit', ...
    'String', sprintf('%.1f-%.1f', gui.freqRange), 'Callback', @updateFreqRange, ...
    'Units', 'normalized', 'Position', [0.55, yPos, 0.4, 0.04]);
yPos = yPos - spacing;

% Export button
uicontrol('Parent', gui.controlPanel, 'Style', 'pushbutton', ...
    'String', 'Export Current View', 'Callback', @exportCurrentView, ...
    'Units', 'normalized', 'Position', [0.05, yPos, 0.9, 0.05]);

%% Store GUI data and initialize display
guidata(gui.fig, gui);
updateDisplay();

%% Callback functions
    function updateTimeFromSlider(src, ~)
        gui = guidata(src);
        gui.currentTime = get(src, 'Value');
        set(gui.timeEdit, 'String', sprintf('%.1f', gui.currentTime));
        guidata(src, gui);
        updateDisplay();
    end

    function updateTimeFromEdit(src, ~)
        gui = guidata(src);
        newTime = str2double(get(src, 'String'));
        if ~isnan(newTime) && newTime >= 0 && newTime <= gui.totalTime - gui.windowLength
            gui.currentTime = newTime;
            set(gui.timeSlider, 'Value', newTime);
            guidata(src, gui);
            updateDisplay();
        else
            set(src, 'String', sprintf('%.1f', gui.currentTime));
        end
    end

    function updateWindowLength(src, ~)
        gui = guidata(src);
        newLength = str2double(get(src, 'String'));
        if ~isnan(newLength) && newLength > 0 && newLength <= gui.totalTime
            gui.windowLength = newLength;
            % Update slider range
            set(gui.timeSlider, 'Max', gui.totalTime - gui.windowLength);
            if gui.currentTime > gui.totalTime - gui.windowLength
                gui.currentTime = gui.totalTime - gui.windowLength;
                set(gui.timeSlider, 'Value', gui.currentTime);
                set(gui.timeEdit, 'String', sprintf('%.1f', gui.currentTime));
            end
            guidata(src, gui);
            updateDisplay();
        else
            set(src, 'String', num2str(gui.windowLength));
        end
    end

    function updateAmplitudeScale(src, ~)
        gui = guidata(src);
        newScale = str2double(get(src, 'String'));
        if ~isnan(newScale) && newScale > 0
            gui.amplitudeScale = newScale;
            guidata(src, gui);
            updateDisplay();
        else
            set(src, 'String', num2str(gui.amplitudeScale));
        end
    end

    function updateChannelSelection(src, ~)
        gui = guidata(src);
        gui.selectedChannels = get(src, 'Value');
        guidata(src, gui);
        updateDisplay();
    end

    function updateFreqRange(src, ~)
        gui = guidata(src);
        freqStr = get(src, 'String');
        try
            % Handle different input formats: "1-30", "1 30", "1,30"
            freqStr = strrep(freqStr, '-', ' '); % Replace dash with space
            freqStr = strrep(freqStr, ',', ' '); % Replace comma with space
            freqNums = str2num(freqStr); %#ok<ST2NM>
            
            if length(freqNums) == 2 && freqNums(1) < freqNums(2) && all(freqNums > 0) && freqNums(2) <= gui.fs/2
                gui.freqRange = freqNums;
                guidata(src, gui);
                updateDisplay();
            else
                error('Invalid frequency range');
            end
        catch
            set(src, 'String', sprintf('%.1f-%.1f', gui.freqRange));
            fprintf('Invalid frequency range. Use format: "1-30" or "1 30"\n');
        end
    end

    function previousWindow(src, ~)
        gui = guidata(src);
        newTime = max(0, gui.currentTime - gui.windowLength);
        gui.currentTime = newTime;
        set(gui.timeSlider, 'Value', newTime);
        set(gui.timeEdit, 'String', sprintf('%.1f', newTime));
        guidata(src, gui);
        updateDisplay();
    end

    function nextWindow(src, ~)
        gui = guidata(src);
        newTime = min(gui.totalTime - gui.windowLength, gui.currentTime + gui.windowLength);
        gui.currentTime = newTime;
        set(gui.timeSlider, 'Value', newTime);
        set(gui.timeEdit, 'String', sprintf('%.1f', newTime));
        guidata(src, gui);
        updateDisplay();
    end

    function keyPress(src, event)
        gui = guidata(src);
        switch event.Key
            case 'leftarrow'
                previousWindow(src, []);
            case 'rightarrow'
                nextWindow(src, []);
            case 'uparrow'
                gui.amplitudeScale = gui.amplitudeScale * 1.2;
                set(gui.amplitudeEdit, 'String', num2str(gui.amplitudeScale));
                guidata(src, gui);
                updateDisplay();
            case 'downarrow'
                gui.amplitudeScale = gui.amplitudeScale / 1.2;
                set(gui.amplitudeEdit, 'String', num2str(gui.amplitudeScale));
                guidata(src, gui);
                updateDisplay();
        end
    end

    function exportCurrentView(src, ~)
        gui = guidata(src);
        timestamp = datestr(now, 'yyyymmdd_HHMMSS');
        filename = sprintf('%s_EEGExplorer_%s.png', subjectID, timestamp);
        
        % Temporarily hide control panel for clean export
        set(gui.controlPanel, 'Visible', 'off');
        set(gui.mainPanel, 'Position', [0, 0, 1, 1]);
        
        print(gui.fig, filename, '-dpng', '-r300');
        
        % Restore layout
        set(gui.controlPanel, 'Visible', 'on');
        set(gui.mainPanel, 'Position', [0.25, 0, 0.75, 1]);
        
        fprintf('Exported current view to: %s\n', filename);
    end

    function closeFigure(src, ~)
        delete(src);
    end

%% Main display update function
    function updateDisplay()
        gui = guidata(gui.fig);
        
        % Calculate time indices for current window
        startIdx = find(gui.timeVec >= gui.currentTime, 1);
        endIdx = find(gui.timeVec <= gui.currentTime + gui.windowLength, 1, 'last');
        
        if isempty(startIdx) || isempty(endIdx)
            return;
        end
        
        % Extract current window data
        windowTime = gui.timeVec(startIdx:endIdx);
        windowData = gui.data(gui.selectedChannels, startIdx:endIdx);
        
        % Update EEG time series plot
        axes(gui.ax_eeg);
        cla;
        hold on;
        
        nSelectedChannels = length(gui.selectedChannels);
        colors = jet(nSelectedChannels);
        
        for i = 1:nSelectedChannels
            chanData = windowData(i, :);
            % Remove DC offset and scale
            chanData = chanData - mean(chanData);
            yOffset = (i - 1) * gui.amplitudeScale * gui.channelSpacing;
            plot(windowTime, chanData + yOffset, 'Color', colors(i, :), 'LineWidth', 1);
        end
        
        % Set y-axis labels to channel names
        yticks = (0:(nSelectedChannels-1)) * gui.amplitudeScale * gui.channelSpacing;
        channelLabelsSelected = gui.channelLabels(gui.selectedChannels);
        
        set(gca, 'YTick', yticks, 'YTickLabel', channelLabelsSelected);
        xlim([gui.currentTime, gui.currentTime + gui.windowLength]);
        ylim([-gui.amplitudeScale, nSelectedChannels * gui.amplitudeScale * gui.channelSpacing]);
        
        % Add event markers to EEG plot
        if ~isempty(gui.markerTimes)
            yLimits = ylim;
            currentWindow = [gui.currentTime, gui.currentTime + gui.windowLength];
            
            % Find markers within current window
            visibleMarkers = gui.markerTimes >= currentWindow(1) & gui.markerTimes <= currentWindow(2);
            
            if any(visibleMarkers)
                markerTimesVisible = gui.markerTimes(visibleMarkers);
                markerLabelsVisible = gui.markerLabels(visibleMarkers);
                
                for i = 1:length(markerTimesVisible)
                    % Draw vertical line
                    line([markerTimesVisible(i), markerTimesVisible(i)], yLimits, ...
                        'Color', 'red', 'LineWidth', 2, 'LineStyle', '--');
                    
                    % Add text label
                    if iscell(markerLabelsVisible)
                        labelText = markerLabelsVisible{i};
                    else
                        labelText = num2str(markerLabelsVisible(i));
                    end
                    
                    % Position text at top of plot
                    text(markerTimesVisible(i), yLimits(2) * 0.95, labelText, ...
                        'Color', 'red', 'FontWeight', 'bold', 'FontSize', 10, ...
                        'HorizontalAlignment', 'center', 'VerticalAlignment', 'top', ...
                        'BackgroundColor', 'white', 'EdgeColor', 'red', 'Margin', 2, ...
                        'Interpreter', 'none');
                end
            end
        end
        
        grid on;
        title(sprintf('EEG Time Series (%.1f - %.1f s)', gui.currentTime, ...
            gui.currentTime + gui.windowLength));
        xlabel('Time (s)');
        
        % Compute and display power spectrum
        updatePowerSpectrum(windowData, gui);
        
        % Compute and display time-frequency analysis
        updateTimeFrequency(windowData, windowTime, gui);
        
        drawnow;
    end

    function updatePowerSpectrum(windowData, gui)
        axes(gui.ax_power);
        cla;
        hold on;
        
        % Compute power spectrum for each selected channel
        nSelectedChannels = size(windowData, 1);
        colors = jet(nSelectedChannels);
        
        for i = 1:nSelectedChannels
            chanData = windowData(i, :);
            
            % Remove DC and apply Hanning window
            chanData = chanData - mean(chanData);
            chanData = chanData .* hanning(length(chanData))';
            
            % Compute power spectrum
            [pxx, f] = pwelch(chanData, [], [], gui.nfft, gui.fs);
            
            % Convert to µV²/Hz and plot
            pxx = pxx * 1e12; % Convert from V²/Hz to µV²/Hz
            
            % Limit to frequency range
            freqMask = f >= gui.freqRange(1) & f <= gui.freqRange(2);
            
            plot(f(freqMask), pxx(freqMask), 'Color', colors(i, :), ...
                'LineWidth', 1.5, 'DisplayName', gui.channelLabels{gui.selectedChannels(i)});
        end
        
        xlabel('Frequency (Hz)');
        ylabel('Power (μV²/Hz)');
        title('Power Spectrum');
        xlim(gui.freqRange);
        set(gca, 'YScale', 'log');
        grid on;
        
        if nSelectedChannels <= 8  % Only show legend if not too many channels
            legend('Location', 'best', 'FontSize', 8);
        end
    end

    function updateTimeFrequency(windowData, windowTime, gui)
        axes(gui.ax_tf);
        cla;
        
        % Use first selected channel for time-frequency analysis
        chanData = windowData(1, :);
        chanData = chanData - mean(chanData);
        
        % Parameters for time-frequency analysis
        windowSamples = round(gui.fs * 0.5); % 0.5-second windows
        overlapSamples = round(windowSamples * gui.overlap);
        
        % Compute spectrogram
        [S, F, T, P] = spectrogram(chanData, windowSamples, overlapSamples, ...
            linspace(gui.freqRange(1), gui.freqRange(2), 100), gui.fs);
        
        % Convert power to dB and µV²
        P_dB = 10 * log10(P * 1e12); % Convert to µV² and dB
        
        % Adjust time vector to match current window
        T_adjusted = T + windowTime(1);
        
        % Create time-frequency plot
        imagesc(T_adjusted, F, P_dB);
        axis xy;
        colorbar;
        
        xlabel('Time (s)');
        ylabel('Frequency (Hz)');
        title(sprintf('Time-Frequency (%s)', gui.channelLabels{gui.selectedChannels(1)}));
        xlim([windowTime(1), windowTime(end)]);
        ylim(gui.freqRange);
        
        % Colormap and colorbar
        colormap(gui.ax_tf, 'jet');
        c = colorbar;
        c.Label.String = 'Power (dB µV²)';
    end

%% Helper function to get current condition
    function conditionName = getCurrentCondition(currentTime, gui)
        conditionName = '';
        
        if isempty(gui.markerTimes)
            return;
        end
        
        % Find the most recent marker before or at current time
        validMarkers = gui.markerTimes <= currentTime;
        
        if any(validMarkers)
            [~, lastMarkerIdx] = max(gui.markerTimes .* validMarkers);
            
            if iscell(gui.markerLabels)
                conditionName = gui.markerLabels{lastMarkerIdx};
            else
                conditionName = num2str(gui.markerLabels(lastMarkerIdx));
            end
        end
    end

fprintf('EEG Explorer initialized successfully!\n');
if ~isempty(markerTimes)
    fprintf('Found %d condition markers - displayed as red dashed lines\n', length(markerTimes));
end
fprintf('Navigation: Arrow keys or buttons\n');
fprintf('- Left/Right: Navigate windows\n');
fprintf('- Up/Down: Adjust amplitude scale\n');

end
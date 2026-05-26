%% Specify options
options = struct();
options.tiChannel = 1;           % Analyze TI channel 3 instead of default 2
options.freqRange = [1900 2500];   % Focus on frequencies between 5-2500 Hz
%options.startTime = 60;          % Start analysis at 60 seconds (skip interactive selection)
options.outputDir = 'D:\matlab\projects\SpindlePilot\spindlePilot_analysis\'; % Save results in this directory
allData.sub2.ses1.TI.time_stamps = [0:0.00005:4714.54070];

runEEGAndTIAnalysis('D:\matlab\projects\SpindlePilot\spindlePilot_analysis\allData.mat', options);

%%
function runEEGAndTIAnalysis(dataFile, options)
    % Convenience function to run the full analysis pipeline
    % Inputs:
    %   dataFile - Path to .mat file containing the allData structure
    %   options - Analysis options structure (optional)
    %     .useFieldTrip - Boolean flag to use FieldTrip toolbox (default: false)
    %     .tiChannel - Channel index to analyze from TI data (default: 2)
    %     .freqRange - Frequency range [min max] in Hz (default: [5 2500])
    %     .startTime - Time point to start analysis (default: 0 = interactive selection)
    %     .outputDir - Directory to save results (default: 'analysis_results' in current folder)
    
    % Set default options
    if nargin < 2
        options = struct();
    end

    % Set default output directory
    if ~isfield(options, 'outputDir')
        options.outputDir = fullfile(pwd, 'analysis_results');
    end

    % Create output directory if it doesn't exist
    if ~exist(options.outputDir, 'dir')
        mkdir(options.outputDir);
    end

    % Load data
    fprintf('Loading data from %s...\n', dataFile);
    load(dataFile, 'allData');

    % Check if data loaded correctly
    if ~exist('allData', 'var')
        error('Failed to load ''allData'' from the specified file.');
    end

    % Check if the expected structure is present
    if ~isfield(allData, 'sub2') || ~isfield(allData.sub2, 'ses1')
        error('The data structure does not contain the expected fields (sub2.ses1).');
    end
    
    % Run analysis
    fprintf('Running analysis with the following options:\n');
    fprintf('- TI channel: %d\n', get_or_default(options, 'tiChannel', 2));
    fprintf('- Frequency range: [%d %d] Hz\n', get_or_default(options, 'freqRange', [5 2500]));
    % Removed notch frequencies output
    if isfield(options, 'startTime') && options.startTime > 0
        fprintf('- Starting time: %.2f s\n', options.startTime);
    else
        fprintf('- Starting time: Interactive selection\n');
    end
    minEEG = min(allData.sub2.ses1.eeg.time{1});
    allData.sub2.ses1.eeg.time{1} = allData.sub2.ses1.eeg.time{1} - minEEG;
    allData.sub2.ses1.eventMarker.time_stamps = allData.sub2.ses1.eventMarker.time_stamps - minEEG;
    minTI = min(allData.sub2.ses1.TI.time_stamps);
    allData.sub2.ses1.TI.time_stamps = allData.sub2.ses1.TI.time_stamps - minTI;

    processedData = analyzeEEGAndTI(allData, options);

    % Save results
    resultFile = fullfile(options.outputDir, 'processed_results.mat');
    fprintf('Saving results to %s...\n', resultFile);
    save(resultFile, 'processedData', '-v7.3');
    
    % Save all figures
    fprintf('Saving figures...\n');
    figHandles = findall(0, 'Type', 'figure');
    for i = 1:length(figHandles)
        figFile = fullfile(options.outputDir, sprintf('figure_%d.fig', i));
        savefig(figHandles(i), figFile);
        
        % Save as PNG as well
        pngFile = fullfile(options.outputDir, sprintf('figure_%d.png', i));
        saveas(figHandles(i), pngFile);
    end
    
    fprintf('Analysis complete! Results saved to %s\n', options.outputDir);
end

function value = get_or_default(options, field, defaultValue)
    % Helper function to get option value or return default
    if isfield(options, field)
        value = options.(field);
    else
        value = defaultValue;
    end
end

function processedData = analyzeEEGAndTI(allData, options)
    % Main function to process EEG and TI data with improved options
    % Inputs:
    %   allData - The data structure containing EEG, event markers, and TI data
    %   options - Structure with analysis parameters
    %     .useFieldTrip - Boolean flag to use FieldTrip toolbox (default: false)
    %     .tiChannel - Channel index to analyze from TI data (default: 2)
    %     .freqRange - Frequency range [min max] in Hz (default: [5 2500])
    %     .startTime - Time point to start analysis (default: 0 = use all data)
    
    % Set default options if not provided
    if nargin < 2
        options = struct();
    end
    
    % Default options
    if ~isfield(options, 'useFieldTrip')
        options.useFieldTrip = false;
    end
    if ~isfield(options, 'tiChannel')
        options.tiChannel = 2;
    end
    if ~isfield(options, 'freqRange')
        options.freqRange = [5 2500];
    end
    if ~isfield(options, 'startTime')
        options.startTime = 0; % 0 means use all data
    end
    
    % Extract session data
    sessionData = allData.sub2.ses1;
    
    % Use the original EEG data without downsampling
    dsEEG = sessionData.eeg;
    
    % New step: Visualize DAQ channel and let user select a time point
    if options.startTime == 0
        selectedTime = visualizeDAQChannelAndSelectTime(dsEEG);
        options.startTime = selectedTime;
    else
        selectedTime = options.startTime;
    end
    
    % Trim data based on selected time
    fprintf('2. Trimming data starting from %.2f seconds...\n', selectedTime);
    [trimmedEEG, trimmedTI, trimmedEventMarker] = trimDataFromTime(dsEEG, sessionData.TI, sessionData.eventMarker, selectedTime);
    
    % Skip notch filtering - use trimmed data directly
    filteredEEG = trimmedEEG;
    
    % 4. Extract string marker times from eventMarker
    fprintf('3. Extracting string markers...\n');  % Updated step number
    markerInfo = extractStringMarkers(trimmedEventMarker);
    
    % 5. Extract DAQ marker times from EEG channel 37
    fprintf('4. Extracting DAQ markers from channel 37...\n');  % Updated step number
    daqMarkers = extractDAQMarkers(filteredEEG);
    
    % 6. Divide data into trials based on DAQ markers
    fprintf('5. Dividing data into trials based on DAQ markers...\n');  % Updated step number
    [eegTrials, tiTrials] = extractTrials(filteredEEG, trimmedTI, daqMarkers.times, options.useFieldTrip);
    
    % 7. Calculate power and find peaks in specified TI channel
    fprintf('6. Calculating power spectra and finding peaks in TI channel %d...\n', options.tiChannel);  % Updated step number
    powerAnalysis = analyzePower(tiTrials, options.tiChannel, options.freqRange, options.useFieldTrip);
    
    % 8. Analyze marker-peak relationships
    fprintf('7. Analyzing relationships between markers and subsequent peaks...\n');  % Updated step number
    markerPeakAnalysis = analyzeMarkerPeakRelationships(markerInfo, daqMarkers, powerAnalysis);
    
    % 9. Create visualizations
    fprintf('8. Creating visualizations...\n');  % Updated step number
    plotMarkerPeakRelationships(markerPeakAnalysis, powerAnalysis, options.tiChannel);
    plotPeakFrequencyTimeframe(daqMarkers.times, powerAnalysis);
    plotSpecificMarkerAnalysis(markerPeakAnalysis, powerAnalysis, 'SPINDLE');
    
    % Return processed data
    processedData = struct();
    processedData.dsEEG = dsEEG;
    processedData.filteredEEG = filteredEEG;  
    processedData.markerInfo = markerInfo;
    processedData.daqMarkers = daqMarkers;
    processedData.eegTrials = eegTrials;
    processedData.tiTrials = tiTrials;
    processedData.powerAnalysis = powerAnalysis;
    processedData.markerPeakAnalysis = markerPeakAnalysis;
    processedData.options = options;
    
    fprintf('Analysis complete!\n');
end

function selectedTime = visualizeDAQChannelAndSelectTime(eegData)
    % Visualize the DAQ channel (channel 37) and let user select a time point
    
    % Extract channel 37 data (DAQ channel)
    daqChannel = eegData.trial{1}(37, :);
    timeVector = eegData.time{1};
    
    % Create figure
    figure('Position', [100, 100, 1200, 500], 'Name', 'DAQ Channel Selection');
    
    % Plot DAQ channel
    plot(timeVector, daqChannel);
    xlabel('Time (s)');
    ylabel('Amplitude');
    title('DAQ Channel (EEG Channel 37) - Select starting time point for analysis');
    grid on;
    
    % Add instructions
    annotation('textbox', [0.5, 0.01, 0.45, 0.08], 'String', ...
        'Click on the point where you want to start the analysis. Data before this point will be excluded.', ...
        'FitBoxToText', 'on', 'EdgeColor', 'none', 'HorizontalAlignment', 'center');
    
    % Let user select a point
    [selectedTime, ~] = ginput(1);
    
    % Add a vertical line at the selected point
    hold on;
    line([selectedTime, selectedTime], ylim, 'Color', 'r', 'LineStyle', '--', 'LineWidth', 2);
    text(selectedTime, max(ylim)*0.9, sprintf('Selected: %.2f s', selectedTime), ...
        'Color', 'r', 'FontWeight', 'bold', 'HorizontalAlignment', 'left');
    hold off;
    
    % Wait for user to acknowledge
    uiwait(msgbox(sprintf('Analysis will start from %.2f seconds.', selectedTime), 'Selection Confirmed'));
end

function [trimmedEEG, trimmedTI, trimmedEventMarker] = trimDataFromTime(eegData, tiData, eventMarker, startTime)
    % Trim all datasets to start from the specified time point
    
    % Trim EEG data
    eegTime = eegData.time{1};
    startIdx = find(eegTime >= startTime, 1, 'first');
    
    trimmedEEG = eegData;
    trimmedEEG.time{1} = eegTime(startIdx:end) - startTime; % Reset time to start from 0
    trimmedEEG.trial{1} = eegData.trial{1}(:, startIdx:end);
    
    % Trim TI data
    tiTime = tiData.time_stamps;
    tiStartIdx = find(tiTime >= startTime, 1, 'first');
    
    trimmedTI = tiData;
    trimmedTI.time_stamps = tiTime(tiStartIdx:end) - startTime; % Reset time to start from 0
    trimmedTI.time_series = tiData.time_series(:, tiStartIdx:end);
    
    % Trim event markers
    markerTimes = eventMarker.time_stamps;
    markerIndices = find(markerTimes >= startTime);
    
    trimmedEventMarker = eventMarker;
    trimmedEventMarker.time_stamps = markerTimes(markerIndices) - startTime; % Reset time to start from 0
    trimmedEventMarker.time_series = eventMarker.time_series(markerIndices);
end

% Removed applyNotchFilters function as it's no longer needed

function markerInfo = extractStringMarkers(eventMarker)
    % Extract string markers from event markers
    markerInfo = struct();
    markerInfo.times = eventMarker.time_stamps;
    markerInfo.strings = eventMarker.time_series;
    markerInfo.info = eventMarker.info;
    
    % Create a more usable format with unique marker types
    uniqueMarkers = unique(eventMarker.time_series);
    markerInfo.uniqueTypes = uniqueMarkers;
    
    % Organize by marker type
    markerInfo.byType = struct();
    for i = 1:length(uniqueMarkers)
        markerType = uniqueMarkers{i};
        markerIndices = find(strcmp(eventMarker.time_series, markerType));
        markerInfo.byType.(genvarname(markerType)) = struct(...
            'times', eventMarker.time_stamps(markerIndices), ...
            'indices', markerIndices);
    end
end

function daqMarkers = extractDAQMarkers(eegData)
    % Extract DAQ markers from EEG channel 37
    
    % Get channel 37 data (contains trigger spikes)
    channel37 = eegData.trial{1}(37, :);
    
    % Get time vector
    timeVector = eegData.time{1};
    
    % Find peaks (triggers) in channel 37
    threshold = 3 * std(channel37); % Adjust threshold as needed
    [peaks, peakIndices] = findpeaks(channel37, 'MinPeakHeight', threshold);
    
    % Store results
    daqMarkers = struct();
    daqMarkers.times = timeVector(peakIndices);
    daqMarkers.indices = peakIndices;
    daqMarkers.values = peaks;
end

function [eegTrials, tiTrials] = extractTrials(eegData, tiData, triggerTimes, useFieldTrip)
    % Extract trials from EEG and TI data based on trigger times
    
    % Define trial window (in seconds)
    preTime = 0.5;  % Time before trigger
    postTime = 2.0; % Time after trigger
    
    if useFieldTrip
        % For FieldTrip version - EEG trials
        % Create a trial definition for FieldTrip
        trl = zeros(length(triggerTimes), 3);
        
        % Get EEG sampling rate
        eegFs = eegData.fsample;
        
        % For each trigger, define trial start and end in samples
        for i = 1:length(triggerTimes)
            % Find the sample index of this trigger in the EEG data
            [~, triggerSample] = min(abs(eegData.time{1} - triggerTimes(i)));
            
            % Define trial start and end in samples
            trlBegin = triggerSample - round(preTime * eegFs);
            trlEnd = triggerSample + round(postTime * eegFs);
            
            % Store in the trl matrix (format: [begin end offset])
            trl(i, :) = [trlBegin trlEnd -round(preTime * eegFs)];
        end
        
        % Segment EEG data into trials using FieldTrip
        cfg = [];
        cfg.trl = trl;
        eegTrials = ft_redefinetrial(cfg, eegData);
    else
        % For native MATLAB version - EEG trials
        eegTrials = struct();
        eegTrials.time = cell(length(triggerTimes), 1);
        eegTrials.data = cell(length(triggerTimes), 1);
        
        % Get EEG time
        eegTime = eegData.time{1};
        
        % Loop through each trigger
        for i = 1:length(triggerTimes)
            % Define time window for this trial
            trialStart = triggerTimes(i) - preTime;
            trialEnd = triggerTimes(i) + postTime;
            
            % Find indices for EEG data
            eegStartIdx = find(eegTime >= trialStart, 1, 'first');
            eegEndIdx = find(eegTime <= trialEnd, 1, 'last');
            
            % Extract EEG trial if valid indices found
            if ~isempty(eegStartIdx) && ~isempty(eegEndIdx)
                eegTrials.data{i} = eegData.trial{1}(:, eegStartIdx:eegEndIdx);
                eegTrials.time{i} = eegTime(eegStartIdx:eegEndIdx);
            else
                warning('Trial %d: EEG indices out of range', i);
                eegTrials.data{i} = [];
                eegTrials.time{i} = [];
            end
        end
        
        % Store additional info
        eegTrials.triggerTimes = triggerTimes;
        eegTrials.preTime = preTime;
        eegTrials.postTime = postTime;
        eegTrials.nTrials = length(triggerTimes);
        eegTrials.label = eegData.label;
    end
    
    % For TI data (always using native MATLAB)
    tiTrials = struct();
    tiTrials.time = cell(length(triggerTimes), 1);
    tiTrials.data = cell(length(triggerTimes), 1);
    
    % Extract TI trials based on absolute timing
    tiTime = tiData.time_stamps;
    tiData_all = tiData.time_series;
    
    % Loop through each trigger
    for i = 1:length(triggerTimes)
        % Define time window for this trial
        trialStart = triggerTimes(i) - preTime;
        trialEnd = triggerTimes(i) + postTime;
        
        % Find indices for TI data
        tiStartIdx = find(tiTime >= trialStart, 1, 'first');
        tiEndIdx = find(tiTime <= trialEnd, 1, 'last');
        
        % Extract TI trial if valid indices found
        if ~isempty(tiStartIdx) && ~isempty(tiEndIdx)
            tiTrials.data{i} = tiData_all(:, tiStartIdx:tiEndIdx);
            tiTrials.time{i} = tiTime(tiStartIdx:tiEndIdx);
        else
            warning('Trial %d: TI indices out of range', i);
            tiTrials.data{i} = [];
            tiTrials.time{i} = [];
        end
    end
    
    % Store additional info
    tiTrials.triggerTimes = triggerTimes;
    tiTrials.preTime = preTime;
    tiTrials.postTime = postTime;
    tiTrials.nTrials = length(triggerTimes);
end

function powerAnalysis = analyzePower(tiTrials, channelIdx, freqRange, useFieldTrip)
    % Calculate power spectra and find peaks in the TI data
    
    % Initialize output structure
    powerAnalysis = struct();
    powerAnalysis.peakFreq = zeros(tiTrials.nTrials, 1);
    powerAnalysis.peakPower = zeros(tiTrials.nTrials, 1);
    powerAnalysis.freqs = cell(tiTrials.nTrials, 1);
    powerAnalysis.power = cell(tiTrials.nTrials, 1);
    powerAnalysis.channelIdx = channelIdx;
    
    if useFieldTrip
        % Using FieldTrip for power analysis
        cfg = [];
        cfg.method = 'mtmfft';
        cfg.taper = 'hanning';
        cfg.foi = linspace(freqRange(1), freqRange(2), 1000); % Frequency resolution
        
        % Loop through trials
        for i = 1:tiTrials.nTrials
            if ~isempty(tiTrials.data{i})
                % Create temporary FieldTrip data structure
                tempData = [];
                tempData.trial = {tiTrials.data{i}};
                tempData.time = {tiTrials.time{i}};
                tempData.label = {sprintf('TI_CH%d', channelIdx)};
                tempData.fsample = 1 / mean(diff(tiTrials.time{i}));
                
                % Select only the specified channel
                cfg.channel = 1; % Since we only included one channel
                
                % Calculate power spectrum
                spectrum = ft_freqanalysis(cfg, tempData);
                
                % Store frequency and power data
                powerAnalysis.freqs{i} = spectrum.freq;
                powerAnalysis.power{i} = squeeze(spectrum.powspctrm);
                
                % Find peak in the specified frequency range
                [maxPower, maxIdx] = max(powerAnalysis.power{i});
                powerAnalysis.peakPower(i) = maxPower;
                powerAnalysis.peakFreq(i) = powerAnalysis.freqs{i}(maxIdx);
            end
        end
    else
        % Using native MATLAB for power analysis
        for i = 1:tiTrials.nTrials
            if ~isempty(tiTrials.data{i})
                % Extract channel data
                channelData = tiTrials.data{i}(channelIdx, :);
                
                % Calculate sampling frequency
                Fs = 1 / mean(diff(tiTrials.time{i}));
                
                % Create Hanning window
                win = hanning(length(channelData))';
                
                % Apply window
                windowedData = channelData .* win;
                
                % Calculate FFT
                N = length(windowedData);
                fftData = fft(windowedData);
                
                % Get single-sided spectrum and frequency vector
                P2 = abs(fftData/N);
                P1 = P2(1:floor(N/2)+1);
                P1(2:end-1) = 2*P1(2:end-1);
                
                % Create frequency vector
                f = Fs * (0:(N/2))/N;
                
                % Store frequency and power data
                powerAnalysis.freqs{i} = f;
                powerAnalysis.power{i} = P1;
                
                % Find peak in the specified frequency range
                freqRangeIndices = find(f >= freqRange(1) & f <= freqRange(2));
                [maxPower, maxIdx] = max(P1(freqRangeIndices));
                powerAnalysis.peakPower(i) = maxPower;
                powerAnalysis.peakFreq(i) = f(freqRangeIndices(maxIdx));
            end
        end
    end
end

function markerPeakAnalysis = analyzeMarkerPeakRelationships(markerInfo, daqMarkers, powerAnalysis)
    % Analyze relationships between markers and subsequent power peaks
    
    markerPeakAnalysis = struct();
    
    % For each marker type, check if it predicts peaks in subsequent trials
    uniqueMarkerTypes = markerInfo.uniqueTypes;
    
    % For storing results by marker type
    markerPeakAnalysis.byType = struct();
    
    % Trial mapping for each marker
    markerPeakAnalysis.markerToTrial = cell(length(markerInfo.times), 1);
    markerPeakAnalysis.trialToMarker = cell(length(daqMarkers.times), 1);
    
    % Map each marker to the nearest subsequent trial
    for i = 1:length(markerInfo.times)
        markerTime = markerInfo.times(i);
        
        % Find the first trial that occurs after this marker
        futureTrialIndices = find(daqMarkers.times > markerTime);
        
        if ~isempty(futureTrialIndices)
            nextTrialIdx = futureTrialIndices(1);
            markerPeakAnalysis.markerToTrial{i} = nextTrialIdx;
            
            % Also store the marker index in the trial's marker list
            if isempty(markerPeakAnalysis.trialToMarker{nextTrialIdx})
                markerPeakAnalysis.trialToMarker{nextTrialIdx} = [];
            end
            markerPeakAnalysis.trialToMarker{nextTrialIdx}(end+1) = i;
        end
    end
    
    % Analyze each marker type
    for m = 1:length(uniqueMarkerTypes)
        markerType = uniqueMarkerTypes{m};
        safeMarkerType = genvarname(markerType);
        
        % Find all instances of this marker
        markerIndices = find(strcmp(markerInfo.strings, markerType));
        
        % Initialize analysis for this marker type
        markerPeakAnalysis.byType.(safeMarkerType) = struct();
        markerPeakAnalysis.byType.(safeMarkerType).markerType = markerType;
        markerPeakAnalysis.byType.(safeMarkerType).markerIndices = markerIndices;
        markerPeakAnalysis.byType.(safeMarkerType).markerTimes = markerInfo.times(markerIndices);
        
        % Find subsequent trials for each marker of this type
        subsequentTrials = [];
        for i = 1:length(markerIndices)
            markerIdx = markerIndices(i);
            if ~isempty(markerPeakAnalysis.markerToTrial{markerIdx})
                subsequentTrials(end+1) = markerPeakAnalysis.markerToTrial{markerIdx};
            end
        end
        
        markerPeakAnalysis.byType.(safeMarkerType).subsequentTrials = subsequentTrials;
        
        % Calculate statistics for peaks in subsequent trials
        if ~isempty(subsequentTrials)
            markerPeakAnalysis.byType.(safeMarkerType).peakFreq = powerAnalysis.peakFreq(subsequentTrials);
            markerPeakAnalysis.byType.(safeMarkerType).peakPower = powerAnalysis.peakPower(subsequentTrials);
            markerPeakAnalysis.byType.(safeMarkerType).meanPeakFreq = mean(powerAnalysis.peakFreq(subsequentTrials));
            markerPeakAnalysis.byType.(safeMarkerType).stdPeakFreq = std(powerAnalysis.peakFreq(subsequentTrials));
            markerPeakAnalysis.byType.(safeMarkerType).meanPeakPower = mean(powerAnalysis.peakPower(subsequentTrials));
            markerPeakAnalysis.byType.(safeMarkerType).stdPeakPower = std(powerAnalysis.peakPower(subsequentTrials));
        else
            markerPeakAnalysis.byType.(safeMarkerType).peakFreq = [];
            markerPeakAnalysis.byType.(safeMarkerType).peakPower = [];
            markerPeakAnalysis.byType.(safeMarkerType).meanPeakFreq = NaN;
            markerPeakAnalysis.byType.(safeMarkerType).stdPeakFreq = NaN;
            markerPeakAnalysis.byType.(safeMarkerType).meanPeakPower = NaN;
            markerPeakAnalysis.byType.(safeMarkerType).stdPeakPower = NaN;
        end
    end
end

function plotMarkerPeakRelationships(markerPeakAnalysis, powerAnalysis, tiChannel)
    % Plot relationships between markers and subsequent peak frequencies
    
    % Get all marker types
    markerTypes = fieldnames(markerPeakAnalysis.byType);
    
    % Create figure
    figure('Position', [100, 100, 1200, 800], 'Name', 'Marker-Peak Relationships');
    
    % Plot 1: Bar chart of mean peak frequencies by marker type
    subplot(2, 2, 1);
    meanFreqs = zeros(length(markerTypes), 1);
    stdFreqs = zeros(length(markerTypes), 1);
    nTrials = zeros(length(markerTypes), 1);
    
    for i = 1:length(markerTypes)
        meanFreqs(i) = markerPeakAnalysis.byType.(markerTypes{i}).meanPeakFreq;
        stdFreqs(i) = markerPeakAnalysis.byType.(markerTypes{i}).stdPeakFreq;
        nTrials(i) = length(markerPeakAnalysis.byType.(markerTypes{i}).subsequentTrials);
    end
    
    % Sort by mean frequency
    [sortedMeans, sortIdx] = sort(meanFreqs, 'descend');
    sortedStds = stdFreqs(sortIdx);
    sortedTypes = markerTypes(sortIdx);
    sortedCounts = nTrials(sortIdx);
    
    % Create bar chart with error bars
    barh(sortedMeans);
    hold on;
    errorbarh(1:length(sortedMeans), sortedMeans, sortedStds, '.');
    hold off;
    
    % Adjust y-ticks for marker names
    set(gca, 'YTick', 1:length(sortedTypes));
    set(gca, 'YTickLabel', sortedTypes);
    
    % Add trial counts to labels
    for i = 1:length(sortedTypes)
        text(max(sortedMeans)*0.02, i, sprintf('n=%d', sortedCounts(i)), 'FontSize', 8);
    end
    
    title('Mean Peak Frequency by Marker Type');
    xlabel('Frequency (Hz)');
    grid on;
    
    % Plot 2: Scatter plot of peak frequencies by marker type
    subplot(2, 2, 2);
    colors = lines(length(markerTypes));
    
    hold on;
    for i = 1:length(markerTypes)
        markerType = markerTypes{i};
        peakFreqs = markerPeakAnalysis.byType.(markerType).peakFreq;
        scatter(ones(size(peakFreqs))*i, peakFreqs, 50, colors(i,:), 'filled', 'MarkerFaceAlpha', 0.7);
    end
    hold off;
    
    % Adjust x-ticks for marker names
    set(gca, 'XTick', 1:length(markerTypes));
    set(gca, 'XTickLabel', markerTypes);
    xtickangle(45);
    
    title('Peak Frequencies Following Each Marker Type');
    ylabel('Frequency (Hz)');
    grid on;
    
    % Plot 3: Box plot of peak frequencies by marker type
    subplot(2, 2, 3:4);
    freqData = {};
    
    for i = 1:length(markerTypes)
        freqData{i} = markerPeakAnalysis.byType.(markerTypes{i}).peakFreq;
    end
    
    boxplot(cell2mat(freqData), 'Labels', markerTypes, 'Notch', 'on');
    title(sprintf('Distribution of Peak Frequencies (TI Channel %d) Following Each Marker Type', tiChannel));
    ylabel('Frequency (Hz)');
    grid on;
    
    % Overall title
    sgtitle('Marker-Peak Frequency Relationships', 'FontSize', 16);
end

function plotPeakFrequencyTimeframe(triggerTimes, powerAnalysis)
    % Plot peak frequencies over time with trials
    
    % Create figure
    figure('Position', [100, 100, 1200, 500], 'Name', 'Peak Frequencies Over Time');
    
    % Main plot
    scatter(triggerTimes, powerAnalysis.peakFreq, 100, powerAnalysis.peakPower, 'filled');
    colorbar;
    colormap(jet);
    
    title('Peak Frequencies Over Time');
    xlabel('Time (s)');
    ylabel('Frequency (Hz)');
    grid on;
    
    % Add trend line
    hold on;
    p = polyfit(triggerTimes, powerAnalysis.peakFreq, 1);
    trendline = polyval(p, triggerTimes);
    plot(triggerTimes, trendline, 'r--', 'LineWidth', 2);
    hold off;
    
    % Add annotation with trend info
    slope = p(1);
    if slope > 0
        trendText = sprintf('Trend: Increasing (%.3f Hz/s)', slope);
    elseif slope < 0
        trendText = sprintf('Trend: Decreasing (%.3f Hz/s)', abs(slope));
    else
        trendText = 'Trend: Stable';
    end
    
    annotation('textbox', [0.7, 0.8, 0.25, 0.1], 'String', trendText, ...
        'FitBoxToText', 'on', 'BackgroundColor', 'white', 'EdgeColor', 'k');
    
    % Create a second figure with a histogram of peak frequencies
    figure('Position', [100, 600, 600, 400], 'Name', 'Peak Frequency Distribution');
    histogram(powerAnalysis.peakFreq, 30);
    title('Distribution of Peak Frequencies');
    xlabel('Frequency (Hz)');
    ylabel('Count');
    grid on;
end

function plotSpecificMarkerAnalysis(markerPeakAnalysis, powerAnalysis, markerName)
    % Detailed analysis and visualization for a specific marker type
    
    % Check if this marker exists
    markerFields = fieldnames(markerPeakAnalysis.byType);
    markerIdx = find(strcmpi(markerFields, genvarname(markerName)));
    
    if isempty(markerIdx)
        warning('Marker type "%s" not found in the data.', markerName);
        return;
    end
    
    markerField = markerFields{markerIdx};
    markerData = markerPeakAnalysis.byType.(markerField);
    
    % Create figure
    figure('Position', [700, 100, 1000, 800], 'Name', ['Analysis of ', markerName, ' Markers']);
    
    % Plot 1: Timeline showing marker occurrences and subsequent trial peaks
    subplot(3, 1, 1);
    
    % Plot all peak frequencies as background
    scatter(1:length(powerAnalysis.peakFreq), powerAnalysis.peakFreq, 20, [0.8 0.8 0.8], 'filled');
    hold on;
    
    % Plot peaks following this marker type
    if ~isempty(markerData.subsequentTrials)
        scatter(markerData.subsequentTrials, powerAnalysis.peakFreq(markerData.subsequentTrials), 100, 'r', 'filled');
    end
    
    % Add marker positions as vertical lines
    for i = 1:length(markerData.markerTimes)
        % Find nearest trial for positioning
        [~, nearestTrial] = min(abs(markerData.markerTimes(i) - powerAnalysis.triggerTimes));
        line([nearestTrial, nearestTrial], ylim, 'Color', 'b', 'LineStyle', '--', 'LineWidth', 1);
    end
    
    title(['Peak Frequencies Following ', markerName, ' Markers']);
    xlabel('Trial Number');
    ylabel('Frequency (Hz)');
    legend('All Trials', ['Trials Following ', markerName], [markerName, ' Marker']);
    grid on;
    hold off;
    
    % Plot 2: Compare frequency distribution for this marker vs. all others
    subplot(3, 1, 2);
    
    % Get trials that follow this marker
    thisMarkerTrials = markerData.subsequentTrials;
    
    % Get all other trials
    allTrials = 1:length(powerAnalysis.peakFreq);
    otherTrials = setdiff(allTrials, thisMarkerTrials);
    
    % Create grouped data for box plot
    groupData = [powerAnalysis.peakFreq(thisMarkerTrials); powerAnalysis.peakFreq(otherTrials)];
    groupLabels = [repmat({['After ', markerName]}, length(thisMarkerTrials), 1); 
                  repmat({'After Other Markers'}, length(otherTrials), 1)];
    
    % Box plot
    boxplot(groupData, groupLabels, 'Notch', 'on');
    title(['Comparison of Peak Frequencies: ', markerName, ' vs. Other Markers']);
    ylabel('Frequency (Hz)');
    grid on;
    
    % Add statistical comparison
    if ~isempty(thisMarkerTrials) && ~isempty(otherTrials)
        [h, p] = ttest2(powerAnalysis.peakFreq(thisMarkerTrials), powerAnalysis.peakFreq(otherTrials));
        sigText = sprintf('t-test: p = %.4f %s', p, ternary(h, '(significant)', '(not significant)'));
        annotation('textbox', [0.7, 0.5, 0.25, 0.05], 'String', sigText, ...
            'FitBoxToText', 'on', 'BackgroundColor', 'white', 'EdgeColor', 'k');
    end
    
    % Plot 3: Time between marker and next trial vs. peak frequency
    subplot(3, 1, 3);
    
    if ~isempty(markerData.subsequentTrials)
        % Calculate time between marker and subsequent trial
        timeToTrial = zeros(length(markerData.markerIndices), 1);
        peakFreqs = zeros(length(markerData.markerIndices), 1);
        
        validCount = 0;
        for i = 1:length(markerData.markerIndices)
            markerIdx = markerData.markerIndices(i);
            if ~isempty(markerPeakAnalysis.markerToTrial{markerIdx})
                trialIdx = markerPeakAnalysis.markerToTrial{markerIdx};
                validCount = validCount + 1;
                
                % Time difference
                timeToTrial(validCount) = powerAnalysis.triggerTimes(trialIdx) - markerData.markerTimes(i);
                
                % Peak frequency
                peakFreqs(validCount) = powerAnalysis.peakFreq(trialIdx);
            end
        end
        
        % Trim arrays to valid count
        timeToTrial = timeToTrial(1:validCount);
        peakFreqs = peakFreqs(1:validCount);
        
        % Scatter plot
        scatter(timeToTrial, peakFreqs, 100, 'filled');
        
        % Add trend line
        hold on;
        p = polyfit(timeToTrial, peakFreqs, 1);
        trendX = linspace(min(timeToTrial), max(timeToTrial), 100);
        trendY = polyval(p, trendX);
        plot(trendX, trendY, 'r-', 'LineWidth', 2);
        hold off;
        
        title(['Relationship Between Delay After ', markerName, ' and Peak Frequency']);
        xlabel('Time Between Marker and Trial (s)');
        ylabel('Peak Frequency (Hz)');
        grid on;
        
        % Add correlation info
        [r, pval] = corrcoef(timeToTrial, peakFreqs);
        corrText = sprintf('Correlation: r = %.2f (p = %.4f)', r(1,2), pval(1,2));
        annotation('textbox', [0.7, 0.2, 0.25, 0.05], 'String', corrText, ...
            'FitBoxToText', 'on', 'BackgroundColor', 'white', 'EdgeColor', 'k');
    else
        text(0.5, 0.5, 'No trials found following this marker type', ...
            'HorizontalAlignment', 'center', 'FontSize', 14);
        axis off;
    end
    
    % Overall title
    sgtitle(['Detailed Analysis of ', markerName, ' Markers'], 'FontSize', 16);
end

function result = ternary(condition, trueVal, falseVal)
    % Simple ternary function
    if condition
        result = trueVal;
    else
        result = falseVal;
    end
end

function errorbarh(x, y, e, marker)
    % Horizontal error bars
    if nargin < 4
        marker = '.';
    end
    
    for i = 1:length(x)
        line([y(i)-e(i), y(i)+e(i)], [x(i), x(i)], 'Color', 'k');
        plot(y(i), x(i), marker, 'MarkerSize', 15);
    end
end
function allData = spindlePilot_separateChannels(allData, excludedChannelPatterns)
% spindlePilot_separateChannels separates EEG channels from auxiliary/marker channels
%
% This function separates channels based on patterns (e.g., AUX, Markers) from
% the main EEG data and stores them separately for different processing pipelines.
% Also removes unused channels (AUX_4).
%
% Usage:
%   allData = spindlePilot_separateChannels(allData, excludedChannelPatterns)
%
% Inputs:
%   allData - The main data structure
%   excludedChannelPatterns - Cell array of patterns to match (e.g., {'AUX', 'Markers'})
%
% Channel assignments:
%   AUX_1 = EMG, AUX_2 = Left EOG, AUX_3 = Right EOG, AUX_4 = Unused (removed)
%
% The function creates two fields:
%   .eeg_main - Main EEG channels for standard processing
%   .eeg_excluded - Excluded channels for separate processing (AUX_1, AUX_2, AUX_3, Markers)

if nargin < 2
    excludedChannelPatterns = {'AUX', 'Markers'};
end

subjects = fieldnames(allData);

for i = 1:length(subjects)
    subject = subjects{i};
    sessions = fieldnames(allData.(subject));
    
    for j = 1:length(sessions)
        session = sessions{j};
        
        if ~isfield(allData.(subject).(session), 'eeg')
            fprintf('No EEG data found for %s, %s. Skipping.\n', subject, session);
            continue;
        end
        
        fprintf('Separating channels for %s, %s...\n', subject, session);
        eeg_data = allData.(subject).(session).eeg;
        
        % First, remove unused channels (AUX_4)
        unusedChannels = {'AUX_4'};
        if any(ismember(eeg_data.label, unusedChannels))
            fprintf('  Removing unused channels: %s\n', strjoin(unusedChannels, ', '));
            cfg = [];
            cfg.channel = setdiff(eeg_data.label, unusedChannels);
            eeg_data = ft_selectdata(cfg, eeg_data);
        end
        
        % Define excluded channels (keep AUX_1=EMG, AUX_2=Left EOG, AUX_3=Right EOG)
        excludedChannels = {};
        for p = 1:length(excludedChannelPatterns)
            pattern = excludedChannelPatterns{p};
            matchingChannels = eeg_data.label(contains(eeg_data.label, pattern, 'IgnoreCase', true));
            excludedChannels = [excludedChannels; matchingChannels];
        end
        
        % Remove duplicates
        excludedChannels = unique(excludedChannels);
        
        % Get main EEG channels
        mainChannels = setdiff(eeg_data.label, excludedChannels);
        
        fprintf('  Main EEG channels: %d\n', length(mainChannels));
        fprintf('  Excluded channels: %d\n', length(excludedChannels));
        
        % Check presence of specific channels
        if any(ismember(excludedChannels, 'AUX_1'))
            fprintf('    - AUX_1 (EMG): Present\n');
        else
            fprintf('    - AUX_1 (EMG): Not found\n');
        end
        
        if any(ismember(excludedChannels, 'AUX_2'))
            fprintf('    - AUX_2 (Left EOG): Present\n');
        else
            fprintf('    - AUX_2 (Left EOG): Not found\n');
        end
        
        if any(ismember(excludedChannels, 'AUX_3'))
            fprintf('    - AUX_3 (Right EOG): Present\n');
        else
            fprintf('    - AUX_3 (Right EOG): Not found\n');
        end
        
        if any(contains(excludedChannels, 'Marker', 'IgnoreCase', true))
            fprintf('    - Markers: Present\n');
        else
            fprintf('    - Markers: Not found\n');
        end
        
        % Create main EEG data structure
        if ~isempty(mainChannels)
            cfg = [];
            cfg.channel = mainChannels;
            eeg_main = ft_selectdata(cfg, eeg_data);
            allData.(subject).(session).eeg_main = eeg_main;
        else
            warning('No main EEG channels found for %s, %s', subject, session);
            allData.(subject).(session).eeg_main = [];
        end
        
        % Create excluded channels data structure
        if ~isempty(excludedChannels)
            cfg = [];
            cfg.channel = excludedChannels;
            eeg_excluded = ft_selectdata(cfg, eeg_data);
            allData.(subject).(session).eeg_excluded = eeg_excluded;
        else
            allData.(subject).(session).eeg_excluded = [];
        end
        
        % Store the list of excluded channels for reference
        allData.(subject).(session).excludedChannelsList = excludedChannels;
        allData.(subject).(session).unusedChannelsRemoved = unusedChannels;
        
        fprintf('  Channel separation complete.\n');
    end
end

fprintf('Channel separation completed for all subjects and sessions.\n');
fprintf('AUX_4 (unused) channels have been removed from all datasets.\n');
end
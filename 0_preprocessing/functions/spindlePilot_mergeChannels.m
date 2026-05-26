function allData = spindlePilot_mergeChannels(allData)
% spindlePilot_mergeChannels merges excluded channels back with main EEG data
%
% This function combines the processed main EEG data with the excluded channels
% (AUX, Markers, etc.) to create a unified EEG structure for epoching.
%
% Usage:
%   allData = spindlePilot_mergeChannels(allData)

subjects = fieldnames(allData);

for i = 1:length(subjects)
    subject = subjects{i};
    sessions = fieldnames(allData.(subject));
    
    for j = 1:length(sessions)
        session = sessions{j};
        
        fprintf('Merging channels for %s, %s...\n', subject, session);
        
        % Check if we have both main and excluded data
        hasMainData = isfield(allData.(subject).(session), 'eeg_main') && ...
                      ~isempty(allData.(subject).(session).eeg_main);
        hasExcludedData = isfield(allData.(subject).(session), 'eeg_excluded') && ...
                          ~isempty(allData.(subject).(session).eeg_excluded);
        
        if ~hasMainData
            fprintf('  No main EEG data found for %s, %s. Skipping.\n', subject, session);
            continue;
        end
        
        eeg_main = allData.(subject).(session).eeg_main;
        
        if hasExcludedData
            eeg_excluded = allData.(subject).(session).eeg_excluded;
            
            % Verify that time vectors are compatible
            main_time = eeg_main.time{1};
            excluded_time = eeg_excluded.time{1};
            
            % Check if the time vectors are the same length and approximately aligned
            if length(main_time) ~= length(excluded_time)
                error('Time vectors have different lengths for %s, %s. Cannot merge channels.', subject, session);
            end
            
            time_diff = max(abs(main_time - excluded_time));
            if time_diff > 1e-6  % Allow for small numerical differences
                warning('Time vectors differ by up to %e seconds for %s, %s. Proceeding with main time vector.', ...
                        time_diff, subject, session);
            end
            
            % Combine channel labels
            combined_labels = [eeg_main.label; eeg_excluded.label];
            
            % Check for duplicate channel names
            [unique_labels, ~, idx] = unique(combined_labels, 'stable');
            if length(unique_labels) ~= length(combined_labels)
                warning('Duplicate channel names found for %s, %s. This may cause issues.', subject, session);
            end
            
            % Combine trial data
            combined_trial = [eeg_main.trial{1}; eeg_excluded.trial{1}];
            
            % Create merged data structure
            eeg_merged = eeg_main;  % Start with main data structure
            eeg_merged.label = combined_labels;
            eeg_merged.trial = {combined_trial};
            eeg_merged.time = {main_time};  % Use main time vector
            
            fprintf('  Merged %d main channels + %d excluded channels = %d total channels\n', ...
                    length(eeg_main.label), length(eeg_excluded.label), length(combined_labels));
            
        else
            % No excluded data to merge, just use main data
            eeg_merged = eeg_main;
            fprintf('  No excluded channels to merge. Using main EEG data only (%d channels)\n', ...
                    length(eeg_main.label));
        end
        
        % Store the merged data in the main 'eeg' field for epoching
        allData.(subject).(session).eeg = eeg_merged;
        
        % Keep separate copies for reference (optional)
        allData.(subject).(session).eeg_main_processed = eeg_main;
        if hasExcludedData
            allData.(subject).(session).eeg_excluded_processed = eeg_excluded;
        end
        
        % Store merge information
        allData.(subject).(session).channelsMerged = true;
        allData.(subject).(session).totalChannelsAfterMerge = length(eeg_merged.label);
        
        fprintf('  Channel merging complete. Final channel count: %d\n', length(eeg_merged.label));
    end
end

fprintf('Channel merging completed for all subjects and sessions.\n');
end
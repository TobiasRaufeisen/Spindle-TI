function allData = spindlePilot_alignTimestamps(allData)
% spindlePilot_alignTimestamps - Align timestamps across all data types in the dataset
%
% This function aligns EEG, TI (Temperature Imaging), and event marker timestamps
% across all subjects and sessions in the allData structure. It ensures a common
% time reference by shifting all timestamps to start from the earliest point.
%
% Usage:
%   allData = spindlePilot_alignTimestamps(allData)
%
% The function:
%   1) Creates proper timestamps for TI data based on sampling rate
%   2) Finds the earliest timestamp across all data types
%   3) Shifts all timestamps to be relative to this earliest point
%
% All subjects and sessions in the allData structure will be processed.

subjects = fieldnames(allData);
fprintf('Starting timestamp alignment for all data streams...\n');

for i = 1:length(subjects)
    subject = subjects{i};
    sessions = fieldnames(allData.(subject));

    for j = 1:length(sessions)
        session = sessions{j};
        fprintf('Aligning timestamps for %s, %s...\n', subject, session);

        % Check if all required fields exist
        if ~isfield(allData.(subject).(session), 'eeg') || ...
                ~isfield(allData.(subject).(session), 'TI') || ...
                ~isfield(allData.(subject).(session), 'eventMarker')
            fprintf('  Warning: Missing required data fields for %s, %s. Skipping.\n', subject, session);
            continue;
        end

        try
            fprintf('  Creating TI timestamps from metadata...\n');

            % Extract TI parameters
            firstTI = str2double(allData.(subject).(session).TI.info.first_timestamp);
            sizeTI = length(allData.(subject).(session).TI.time_series);
            sampleTimeDiff = (1/str2double(allData.(subject).(session).TI.info.nominal_srate));

            % Create timestamp vector
            allData.(subject).(session).TI.time_stamps = ...
                (firstTI:sampleTimeDiff:(firstTI - sampleTimeDiff + (sampleTimeDiff*sizeTI)));

            fprintf('  TI timestamps created: %.2f to %.2f seconds\n', ...
                allData.(subject).(session).TI.time_stamps(1), ...
                allData.(subject).(session).TI.time_stamps(end));

            % 2. Find minimum timestamps across all data types
            minTI = min(allData.(subject).(session).TI.time_stamps);

            % Handle continuous vs epoched EEG data
            if iscell(allData.(subject).(session).eeg.time)
                minEEG = min(allData.(subject).(session).eeg.time{1});
            else
                minEEG = min(allData.(subject).(session).eeg.time);
            end

            %firstEEG = allData.(subject).(session).eeg.hdr.FirstTimeStamp;
            %sizeEEG = length(allData.(subject).(session).eeg.trial{1});
            %sampleTimeDiff = (1/(allData.(subject).(session).eeg.hdr.Fs));
            %minEEG = min(allData.(subject).(session).eeg.time{1});

            % Create timestamp vector
            %allData.(subject).(session).eeg.time{1} = ...
            %    (firstEEG:sampleTimeDiff:(firstEEG - sampleTimeDiff + (sampleTimeDiff*sizeEEG)));

            % Also check eventMarker timestamps
            minMarker = min(allData.(subject).(session).eventMarker.time_stamps);

            % Find the overall minimum
            minAll = min([minTI, minEEG, minMarker]);
            fprintf('  Earliest timestamp: %.4f seconds\n', minAll);

            % 3. Adjust all timestamps to be relative to minAll

            % Adjust EEG timestamps
            if iscell(allData.(subject).(session).eeg.time)
                for t = 1:length(allData.(subject).(session).eeg.time)
                    allData.(subject).(session).eeg.time{t} = ...
                        allData.(subject).(session).eeg.time{t} - minAll;
                end
                fprintf('  Adjusted EEG timestamps: Now starting at %.4f seconds\n', ...
                    allData.(subject).(session).eeg.time{1}(1));
            else
                allData.(subject).(session).eeg.time = ...
                    allData.(subject).(session).eeg.time - minAll;
                fprintf('  Adjusted EEG timestamps: Now starting at %.4f seconds\n', ...
                    allData.(subject).(session).eeg.time(1));
            end

            % Adjust event marker timestamps
            allData.(subject).(session).eventMarker.time_stamps = ...
                allData.(subject).(session).eventMarker.time_stamps - minAll;
            fprintf('  Adjusted marker timestamps: Now starting at %.4f seconds\n', ...
                allData.(subject).(session).eventMarker.time_stamps(1));

            % Adjust TI timestamps
            allData.(subject).(session).TI.time_stamps = ...
                allData.(subject).(session).TI.time_stamps - minAll;
            fprintf('  Adjusted TI timestamps: Now starting at %.4f seconds\n', ...
                allData.(subject).(session).TI.time_stamps(1));

            % 4. Adjust epoched data if present
            if isfield(allData.(subject).(session), 'epochedData')
                fprintf('  Adjusting timestamps in epoched data...\n');
                conditions = fieldnames(allData.(subject).(session).epochedData);

                for c = 1:length(conditions)
                    cond = conditions{c};

                    if isfield(allData.(subject).(session).epochedData.(cond), 'time')
                        % Adjust time for each trial
                        for t = 1:length(allData.(subject).(session).epochedData.(cond).time)
                            allData.(subject).(session).epochedData.(cond).time{t} = ...
                                allData.(subject).(session).epochedData.(cond).time{t} - minAll;
                        end
                    end
                end
                fprintf('  Epoched data timestamps adjusted\n');
            end

            fprintf('  Successfully aligned all timestamps for %s, %s\n', subject, session);

        catch ME
            fprintf('  Error aligning timestamps for %s, %s: %s\n', ...
                subject, session, ME.message);
            fprintf('  Skipping this session...\n');
        end
    end
end

fprintf('Timestamp alignment complete for all subjects and sessions.\n');
end
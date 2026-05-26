function allData = spindlePilot_loadData(rootDir, subjects, sessions)
    allData = struct();

    for i = 1:length(subjects)
        subNum = subjects(i);
        subField = sprintf('sub%d', subNum);
        for j = 1:length(sessions)
            sesNum = sessions(j);
            sesField = sprintf('ses%d', sesNum);
            % Construct file path
            fileName = sprintf('sub-P%03d_ses-S%03d_task-Default_run-001_eeg.xdf', subNum, sesNum);
            subDir = sprintf('sub-P%03d', subNum);
            sesDir = sprintf('ses-S%03d', sesNum);
            filePath = fullfile(rootDir, subDir, sesDir, 'eeg', fileName);
            
            % Check if XDF file exists before loading
            if ~exist(filePath, 'file')
                error('spindlePilot:loadData:FileNotFound', ...
                      'XDF file not found: %s\nExpected at: %s', fileName, filePath);
            end

            % Load the xdf file
            data = load_xdf(filePath);

            % Identify stream indices based on stream names
            stream_info = cellfun(@(x) x.info.name, data, 'UniformOutput', false);
            eeg_stream_index = find(strcmp(stream_info, 'actiCHamp-20110416'), 1);
            eventMarker_stream_index = find(strcmp(stream_info, 'StimMarkers'), 1);
            TI_stream_index = find(strcmp(stream_info, 'MyDAQStream'), 1);

            % Validate that all required streams were found
            if isempty(eeg_stream_index)
                error('spindlePilot:loadData:EEGStreamNotFound', ...
                      'EEG stream "actiCHamp-20110416" not found in %s\nAvailable streams: %s', ...
                      filePath, strjoin(stream_info, ', '));
            end

            if isempty(eventMarker_stream_index)
                error('spindlePilot:loadData:MarkerStreamNotFound', ...
                      'Marker stream "StimMarkers" not found in %s\nAvailable streams: %s', ...
                      filePath, strjoin(stream_info, ', '));
            end

            if isempty(TI_stream_index)
                error('spindlePilot:loadData:TIStreamNotFound', ...
                      'TI stream "MyDAQStream" not found in %s\nAvailable streams: %s', ...
                      filePath, strjoin(stream_info, ', '));
            end
            
            % Load EEG data using xdf2fieldtrip and extract event marker data
            eeg_data = xdf2fieldtrip(filePath, 'streamindx', eeg_stream_index);
            eventMarker_data = data{eventMarker_stream_index};
            TI_data = data{TI_stream_index};
            
            % Remove prefix from EEG channel labels
            prefix_length = length('actiCHamp-20110416_');
            eeg_data.label = cellfun(@(x) x(prefix_length+1:end), eeg_data.label, 'UniformOutput', false);
            
            % Store loaded data into structure
            allData.(subField).(sesField).eeg = eeg_data;
            allData.(subField).(sesField).eventMarker = eventMarker_data;
            allData.(subField).(sesField).TI = TI_data;
        end
    end
end

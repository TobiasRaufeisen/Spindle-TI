classdef spindlePilot_EnhancedBrowser < handle
    % spindlePilot_EnhancedBrowser - Enhanced EEG browser for sleep data
    %
    % Features:
    % - Channel-specific event visualization with A1/A2 suffix mapping
    % - Sleep stage filtering (show only selected stages, skip others)  
    % - Experimental condition visualization with onset lines
    % - Interactive navigation and controls
    % - Hypnogram overview with current position indicator
    % - Multi-channel display with individual scaling
    %
    % Usage:
    %   browser = spindlePilot_EnhancedBrowser(eeg_data, spindles, slowwaves, sleep_stages, conditions_data, subject);
    %   browser.createGUI();
    
    properties
        % Data properties
        eeg_data
        spindles
        slowwaves
        sleep_stages
        conditions_data
        subject
        
        % Display properties
        fs
        current_time = 0
        window_size = 30
        selected_channels = {}
        channel_spacing = 100
        show_spindles = true
        show_slowwaves = true
        show_conditions = false
        amplitude_scale = 1.0
        
        % Sleep stage filtering
        available_stages = {}
        selected_stages = {}
        stage_filtering_enabled = false
        
        % GUI handles
        fig
        ax_main
        ax_conditions
        ax_hypno
        channel_listbox
        time_edit
        window_edit
        spacing_edit
        scale_edit
        spindle_checkbox
        slowwave_checkbox
        conditions_checkbox
        stage_filter_checkbox
        stage_listbox
        info_text
        
        % Colors and styling
        colors = struct(...
            'spindle', [1, 0.6, 0], ...      % Orange
            'slowwave', [0.2, 0.6, 1], ...   % Blue
            'N1', [0.9, 0.9, 0.5], ...       % Light yellow
            'N2', [0.7, 0.9, 0.7], ...       % Light green
            'N3', [0.5, 0.8, 0.5], ...       % Green
            'REM', [0.9, 0.7, 0.9], ...      % Light purple
            'W', [1, 1, 1], ...              % White
            'Wake', [0.95, 0.95, 0.95], ...  % Very light gray
            'A', [0.8, 0.8, 0.8], ...        % Gray for artifact
            'Movement', [0.9, 0.5, 0.5] ...  % Light red for movement
        )
        
        % Condition colors
        condition_colors = struct(...
            'HZ1', [0.8, 0.2, 0.2], ...      % Red (for 1HZ)
            'HZ5', [0.2, 0.8, 0.2], ...      % Green (for 5HZ)
            'OFF', [0.2, 0.2, 0.8], ...      % Blue
            'NOSTIM', [0.7, 0.7, 0.7], ...   % Gray
            'refract', [0.9, 0.9, 0.4], ...  % Yellow
            'ramping', [0.9, 0.5, 0.9] ...   % Magenta
        )
    end
    
    methods
        function obj = spindlePilot_EnhancedBrowser(eeg_data, spindles, slowwaves, sleep_stages, conditions_data, subject)
            % Constructor
            obj.eeg_data = eeg_data;
            obj.spindles = spindles;
            obj.slowwaves = slowwaves;
            obj.sleep_stages = sleep_stages;
            obj.conditions_data = conditions_data;
            obj.subject = subject;
            obj.fs = eeg_data.fsample;
            
            % Select channels that have events for better visualization
            obj.selected_channels = obj.selectChannelsWithEvents();
            
            % Determine available sleep stages
            if height(sleep_stages) > 0
                obj.available_stages = unique(sleep_stages.Stage);
                obj.selected_stages = obj.available_stages;
            end
            
            % Print initialization info
            fprintf('Enhanced EEG browser initialized for %s\n', subject);
            fprintf('Data: %.1f hours, %d channels\n', ...
                length(eeg_data.time{1})/obj.fs/3600, length(eeg_data.label));
            fprintf('Events: %d spindles, %d slow waves\n', height(spindles), height(slowwaves));
            fprintf('Sleep stages: %d epochs\n', height(sleep_stages));
            if ~isempty(obj.available_stages)
                fprintf('Available stages: %s\n', strjoin(obj.available_stages, ', '));
            end
            if ~isempty(conditions_data)
                condition_names = unique({conditions_data.name});
                fprintf('Experimental conditions: %s\n', strjoin(condition_names, ', '));
            end
            fprintf('Selected channels for display: %s\n', strjoin(obj.selected_channels, ', '));
            
            % Report channel mapping results
            if height(spindles) > 0 || height(slowwaves) > 0
                obj.reportChannelMapping();
            end
        end
        
        function selected_channels = selectChannelsWithEvents(obj)
            % Automatically select channels that have events (with channel mapping)
            all_channels = obj.eeg_data.label;
            event_channels = {};
            
            % Get channels from spindles
            if height(obj.spindles) > 0 && ismember('Channel', obj.spindles.Properties.VariableNames)
                spindle_channels = obj.extractChannelNames(obj.spindles.Channel);
                event_channels = [event_channels, spindle_channels];
            end
            
            % Get channels from slow waves  
            if height(obj.slowwaves) > 0 && ismember('Channel', obj.slowwaves.Properties.VariableNames)
                slowwave_channels = obj.extractChannelNames(obj.slowwaves.Channel);
                event_channels = [event_channels, slowwave_channels];
            end
            
            % Get unique event channels
            unique_event_channels = unique(event_channels);
            
            % Filter to only include channels that exist in EEG data
            valid_event_channels = {};
            for i = 1:length(unique_event_channels)
                if ismember(unique_event_channels{i}, all_channels)
                    valid_event_channels{end+1} = unique_event_channels{i};
                end
            end
            
            % Show ALL channels with events (no artificial limits)
            if ~isempty(valid_event_channels)
                selected_channels = valid_event_channels;
                fprintf('Auto-selected %d channels with events\n', length(selected_channels));
            else
                % Fall back to first 8 channels if no events found
                selected_channels = all_channels(1:min(8, length(all_channels)));
                fprintf('No event channels found, using first %d channels\n', length(selected_channels));
            end
        end
        
        function channel_names = extractChannelNames(obj, channel_column)
            % Helper function to extract individual channel names from the Channel column
            % Handles channel name mapping (removes A1/A2 suffixes)
            channel_names = {};
            
            for i = 1:length(channel_column)
                if iscell(channel_column)
                    if iscell(channel_column{i})
                        % Handle nested cell arrays
                        channels = channel_column{i};
                    else
                        % Handle simple cell array
                        channels = {channel_column{i}};
                    end
                else
                    % Handle string/char arrays
                    channel_str = channel_column(i);
                    if contains(channel_str, '+')
                        % Split multi-channel events (e.g., "C3+C4")
                        channels = strsplit(channel_str, '+');
                    else
                        channels = {channel_str};
                    end
                end
                
                % Add to list with channel name mapping
                for j = 1:length(channels)
                    ch_name = strtrim(channels{j});
                    if ~isempty(ch_name)
                        % Map channel names (remove A1/A2 suffixes)
                        mapped_name = obj.mapChannelName(ch_name);
                        if ~isempty(mapped_name) && ~ismember(mapped_name, channel_names)
                            channel_names{end+1} = mapped_name;
                        end
                    end
                end
            end
        end
        
        function mapped_name = mapChannelName(obj, original_name)
            % Map channel names from spindle data to EEG data format
            % Remove A1/A2 reference suffixes and map to actual EEG channel names
            
            % Remove A1/A2 suffixes
            mapped_name = regexprep(original_name, 'A[12]$', '');
            
            % Check if the mapped name exists in EEG channels
            if ismember(mapped_name, obj.eeg_data.label)
                % Direct match found
                return;
            end
            
            % If no direct match, return empty (channel not available in EEG data)
            mapped_name = '';
        end
        
        function eeg_channel = findEEGChannel(obj, event_channel)
            % Find corresponding EEG channel name for an event channel name
            % Handles the A1/A2 suffix mapping
            
            % Try direct mapping
            mapped_name = obj.mapChannelName(event_channel);
            if ~isempty(mapped_name)
                eeg_channel = mapped_name;
                return;
            end
            
            % If no mapping found, return empty
            eeg_channel = '';
        end
        
        function reportChannelMapping(obj)
            % Report channel name mapping results for debugging
            fprintf('\n--- Channel Mapping Report ---\n');
            
            % Check spindle channels
            if height(obj.spindles) > 0 && ismember('Channel', obj.spindles.Properties.VariableNames)
                spindle_event_channels = unique(obj.spindles.Channel);
                fprintf('Spindle channels in data: %d unique\n', length(spindle_event_channels));
                
                mapped_count = 0;
                for i = 1:min(5, length(spindle_event_channels))  % Show first 5 as examples
                    original = spindle_event_channels{i};
                    mapped = obj.findEEGChannel(original);
                    if ~isempty(mapped)
                        fprintf('  %s -> %s ✓\n', original, mapped);
                        mapped_count = mapped_count + 1;
                    else
                        fprintf('  %s -> (not found) ✗\n', original);
                    end
                end
                if length(spindle_event_channels) > 5
                    fprintf('  ... and %d more\n', length(spindle_event_channels) - 5);
                end
            end
            
            % Check slow wave channels
            if height(obj.slowwaves) > 0 && ismember('Channel', obj.slowwaves.Properties.VariableNames)
                slowwave_event_channels = unique(obj.slowwaves.Channel);
                fprintf('Slow wave channels in data: %d unique\n', length(slowwave_event_channels));
                
                for i = 1:min(3, length(slowwave_event_channels))  % Show first 3 as examples
                    original = slowwave_event_channels{i};
                    mapped = obj.findEEGChannel(original);
                    if ~isempty(mapped)
                        fprintf('  %s -> %s ✓\n', original, mapped);
                    else
                        fprintf('  %s -> (not found) ✗\n', original);
                    end
                end
                if length(slowwave_event_channels) > 3
                    fprintf('  ... and %d more\n', length(slowwave_event_channels) - 3);
                end
            end
            
            fprintf('------------------------------\n');
        end
        
        function createGUI(obj)
            % Create main GUI
            obj.fig = figure('Name', sprintf('SpindlePilot Enhanced Browser - %s', obj.subject), ...
                'Position', [50, 50, 1600, 900], ...
                'KeyPressFcn', @(src,evt) obj.keyPressCallback(evt), ...
                'WindowScrollWheelFcn', @(src,evt) obj.scrollCallback(evt));
            
            % Create layout panels
            control_panel = uipanel('Parent', obj.fig, 'Position', [0, 0, 0.25, 1], ...
                'Title', 'Controls', 'FontSize', 10, 'FontWeight', 'bold');
            display_panel = uipanel('Parent', obj.fig, 'Position', [0.25, 0, 0.75, 1], ...
                'Title', 'EEG Display');
            
            % Create axes based on whether conditions are available
            if ~isempty(obj.conditions_data)
                % Main EEG plot
                obj.ax_main = axes('Parent', display_panel, 'Position', [0.08, 0.45, 0.88, 0.5]);
                % Conditions timeline
                obj.ax_conditions = axes('Parent', display_panel, 'Position', [0.08, 0.35, 0.88, 0.08]);
                % Hypnogram
                obj.ax_hypno = axes('Parent', display_panel, 'Position', [0.08, 0.05, 0.88, 0.25]);
            else
                % Main EEG plot (larger)
                obj.ax_main = axes('Parent', display_panel, 'Position', [0.08, 0.35, 0.88, 0.6]);
                % Hypnogram
                obj.ax_hypno = axes('Parent', display_panel, 'Position', [0.08, 0.05, 0.88, 0.25]);
            end
            
            hold(obj.ax_main, 'on');
            xlabel(obj.ax_main, 'Time (s)');
            ylabel(obj.ax_main, 'Channels');
            
            if ~isempty(obj.conditions_data)
                hold(obj.ax_conditions, 'on');
                xlabel(obj.ax_conditions, 'Time (s)');
                ylabel(obj.ax_conditions, 'Conditions');
            end
            
            hold(obj.ax_hypno, 'on');
            xlabel(obj.ax_hypno, 'Time (s)');
            ylabel(obj.ax_hypno, 'Sleep Stage');
            
            % Create controls
            obj.createControls(control_panel);
            
            % Add instructions
            if ~isempty(obj.conditions_data)
                instr_text = 'Keys: ←→ navigate (5s), Shift+←→ (30s), ↑↓ zoom, Space: next spindle, S: toggle stage filter, C: toggle conditions';
            else
                instr_text = 'Keys: ←→ navigate (5s), Shift+←→ (30s), ↑↓ zoom, Space: next spindle, S: toggle stage filter';
            end
            
            annotation(obj.fig, 'textbox', [0.25, 0.95, 0.75, 0.04], ...
                'String', instr_text, ...
                'HorizontalAlignment', 'center', 'EdgeColor', 'none', 'FontSize', 9);
            
            % Initial display
            obj.updateDisplay();
        end
        
        function createControls(obj, parent)
            % Create control panel
            y_pos = 0.95;
            dy = 0.035;
            
            % Navigation controls
            uicontrol('Parent', parent, 'Style', 'text', ...
                'String', 'Navigation:', 'Units', 'normalized', ...
                'Position', [0.05, y_pos, 0.9, 0.025], 'FontWeight', 'bold');
            y_pos = y_pos - dy;
            
            % Navigation buttons
            btn_positions = [0.05, 0.27, 0.49, 0.71; y_pos, y_pos, y_pos, y_pos; 0.2, 0.2, 0.2, 0.2; 0.025, 0.025, 0.025, 0.025];
            btn_labels = {'<<30s', '<5s', '5s>', '30s>>'};
            btn_callbacks = {@(~,~) obj.navigate(-30), @(~,~) obj.navigate(-5), @(~,~) obj.navigate(5), @(~,~) obj.navigate(30)};
            
            for i = 1:4
                uicontrol('Parent', parent, 'Style', 'pushbutton', ...
                    'String', btn_labels{i}, 'Units', 'normalized', ...
                    'Position', btn_positions(:,i)', 'Callback', btn_callbacks{i}, 'FontSize', 8);
            end
            y_pos = y_pos - dy;
            
            % Time control
            uicontrol('Parent', parent, 'Style', 'text', ...
                'String', 'Current Time (s):', 'Units', 'normalized', ...
                'Position', [0.05, y_pos, 0.9, 0.025]);
            y_pos = y_pos - 0.025;
            
            obj.time_edit = uicontrol('Parent', parent, 'Style', 'edit', ...
                'String', num2str(obj.current_time), 'Units', 'normalized', ...
                'Position', [0.05, y_pos, 0.9, 0.025], ...
                'Callback', @(src,evt) obj.timeEditCallback());
            y_pos = y_pos - dy;
            
            % Window size
            uicontrol('Parent', parent, 'Style', 'text', ...
                'String', 'Window Size (s):', 'Units', 'normalized', ...
                'Position', [0.05, y_pos, 0.9, 0.025]);
            y_pos = y_pos - 0.025;
            
            obj.window_edit = uicontrol('Parent', parent, 'Style', 'edit', ...
                'String', num2str(obj.window_size), 'Units', 'normalized', ...
                'Position', [0.05, y_pos, 0.9, 0.025], ...
                'Callback', @(src,evt) obj.windowSizeCallback());
            y_pos = y_pos - dy;
            
            % Channel selection with event indicators
            uicontrol('Parent', parent, 'Style', 'text', ...
                'String', 'Channels:', 'Units', 'normalized', ...
                'Position', [0.05, y_pos, 0.9, 0.025], 'FontWeight', 'bold');
            y_pos = y_pos - 0.025;
            
            % Create channel list with event indicators
            channel_list_with_events = obj.createChannelListWithEvents();
            obj.channel_listbox = uicontrol('Parent', parent, 'Style', 'listbox', ...
                'String', channel_list_with_events, 'Units', 'normalized', ...
                'Position', [0.05, y_pos-0.12, 0.9, 0.12], 'Max', length(obj.eeg_data.label), ...
                'Value', obj.getSelectedChannelIndices(), ...
                'Callback', @(src,evt) obj.channelSelectionCallback());
            y_pos = y_pos - 0.15;
            
            % Display settings
            uicontrol('Parent', parent, 'Style', 'text', ...
                'String', 'Display Settings:', 'Units', 'normalized', ...
                'Position', [0.05, y_pos, 0.9, 0.025], 'FontWeight', 'bold');
            y_pos = y_pos - dy;
            
            % Amplitude scale
            uicontrol('Parent', parent, 'Style', 'text', ...
                'String', 'Amplitude Scale:', 'Units', 'normalized', ...
                'Position', [0.05, y_pos, 0.9, 0.025]);
            y_pos = y_pos - 0.025;
            
            obj.scale_edit = uicontrol('Parent', parent, 'Style', 'edit', ...
                'String', num2str(obj.amplitude_scale), 'Units', 'normalized', ...
                'Position', [0.05, y_pos, 0.9, 0.025], ...
                'Callback', @(src,evt) obj.scaleCallback());
            y_pos = y_pos - dy;
            
            % Channel spacing
            uicontrol('Parent', parent, 'Style', 'text', ...
                'String', 'Channel Spacing (μV):', 'Units', 'normalized', ...
                'Position', [0.05, y_pos, 0.9, 0.025]);
            y_pos = y_pos - 0.025;
            
            obj.spacing_edit = uicontrol('Parent', parent, 'Style', 'edit', ...
                'String', num2str(obj.channel_spacing), 'Units', 'normalized', ...
                'Position', [0.05, y_pos, 0.9, 0.025], ...
                'Callback', @(src,evt) obj.spacingCallback());
            y_pos = y_pos - dy;
            
            % Event and condition display toggles
            uicontrol('Parent', parent, 'Style', 'text', ...
                'String', 'Display Options:', 'Units', 'normalized', ...
                'Position', [0.05, y_pos, 0.9, 0.025], 'FontWeight', 'bold');
            y_pos = y_pos - dy;
            
            obj.spindle_checkbox = uicontrol('Parent', parent, 'Style', 'checkbox', ...
                'String', 'Spindles', 'Units', 'normalized', ...
                'Position', [0.05, y_pos, 0.9, 0.025], 'Value', obj.show_spindles, ...
                'Callback', @(src,evt) obj.toggleSpindles());
            y_pos = y_pos - 0.03;
            
            obj.slowwave_checkbox = uicontrol('Parent', parent, 'Style', 'checkbox', ...
                'String', 'Slow Waves', 'Units', 'normalized', ...
                'Position', [0.05, y_pos, 0.9, 0.025], 'Value', obj.show_slowwaves, ...
                'Callback', @(src,evt) obj.toggleSlowwaves());
            y_pos = y_pos - 0.03;
            
            % Conditions checkbox (only if conditions available)
            if ~isempty(obj.conditions_data)
                obj.conditions_checkbox = uicontrol('Parent', parent, 'Style', 'checkbox', ...
                    'String', 'Experimental Conditions', 'Units', 'normalized', ...
                    'Position', [0.05, y_pos, 0.9, 0.025], 'Value', obj.show_conditions, ...
                    'Callback', @(src,evt) obj.toggleConditions());
                y_pos = y_pos - 0.03;
            end
            
            y_pos = y_pos - 0.01;
            
            % Sleep stage filtering
            uicontrol('Parent', parent, 'Style', 'text', ...
                'String', 'Sleep Stage Filter:', 'Units', 'normalized', ...
                'Position', [0.05, y_pos, 0.9, 0.025], 'FontWeight', 'bold');
            y_pos = y_pos - dy;
            
            obj.stage_filter_checkbox = uicontrol('Parent', parent, 'Style', 'checkbox', ...
                'String', 'Enable Stage Filtering', 'Units', 'normalized', ...
                'Position', [0.05, y_pos, 0.9, 0.025], 'Value', obj.stage_filtering_enabled, ...
                'Callback', @(src,evt) obj.toggleStageFiltering());
            y_pos = y_pos - 0.03;
            
            % Stage selection listbox
            if ~isempty(obj.available_stages)
                obj.stage_listbox = uicontrol('Parent', parent, 'Style', 'listbox', ...
                    'String', obj.available_stages, 'Units', 'normalized', ...
                    'Position', [0.05, y_pos-0.1, 0.9, 0.1], 'Max', length(obj.available_stages), ...
                    'Value', 1:length(obj.available_stages), ...
                    'Enable', spindlePilot_iif(obj.stage_filtering_enabled, 'on', 'off'), ...
                    'Callback', @(src,evt) obj.stageSelectionCallback());
                y_pos = y_pos - 0.12;
            end
            
            % Event navigation
            uicontrol('Parent', parent, 'Style', 'pushbutton', ...
                'String', 'Next Spindle', 'Units', 'normalized', ...
                'Position', [0.05, y_pos, 0.43, 0.025], ...
                'Callback', @(src,evt) obj.jumpToNextEvent('spindle'));
            
            uicontrol('Parent', parent, 'Style', 'pushbutton', ...
                'String', 'Next Slow Wave', 'Units', 'normalized', ...
                'Position', [0.52, y_pos, 0.43, 0.025], ...
                'Callback', @(src,evt) obj.jumpToNextEvent('slowwave'));
            y_pos = y_pos - dy;
            
            % Info display
            obj.info_text = uicontrol('Parent', parent, 'Style', 'text', ...
                'String', 'Ready...', 'Units', 'normalized', ...
                'Position', [0.05, 0.02, 0.9, y_pos-0.02], ...
                'HorizontalAlignment', 'left', ...
                'FontSize', 8);
        end
        
        function channel_list = createChannelListWithEvents(obj)
            % Create channel list showing which channels have events
            % Uses mapped channel names for proper matching
            channel_list = {};
            
            % Get channels with events (using mapped names)
            spindle_channels = {};
            slowwave_channels = {};
            
            if height(obj.spindles) > 0 && ismember('Channel', obj.spindles.Properties.VariableNames)
                spindle_channels = obj.extractChannelNames(obj.spindles.Channel);
            end
            
            if height(obj.slowwaves) > 0 && ismember('Channel', obj.slowwaves.Properties.VariableNames)
                slowwave_channels = obj.extractChannelNames(obj.slowwaves.Channel);
            end
            
            % Create list with indicators for EEG channels
            for i = 1:length(obj.eeg_data.label)
                ch_name = obj.eeg_data.label{i};
                indicators = '';
                
                % Use mapped channel names for comparison
                if ismember(ch_name, spindle_channels)
                    indicators = [indicators, 'S'];
                end
                if ismember(ch_name, slowwave_channels)
                    indicators = [indicators, 'W'];
                end
                
                if ~isempty(indicators)
                    channel_list{i} = sprintf('%s [%s]', ch_name, indicators);
                else
                    channel_list{i} = ch_name;
                end
            end
        end
        
        function indices = getSelectedChannelIndices(obj)
            % Get indices of currently selected channels
            indices = [];
            for i = 1:length(obj.selected_channels)
                idx = find(strcmp(obj.eeg_data.label, obj.selected_channels{i}));
                if ~isempty(idx)
                    indices = [indices, idx];
                end
            end
        end
        
        function updateDisplay(obj)
            % Main display update function
            obj.clearPlots();
            
            % Get valid time indices based on stage filtering
            valid_indices = obj.getValidTimeIndices();
            
            if obj.stage_filtering_enabled && ~any(valid_indices)
                obj.plotNoData();
                return;
            end
            
            obj.plotEEG(valid_indices);
            obj.plotChannelSpecificEvents();
            
            if obj.show_conditions && ~isempty(obj.conditions_data)
                obj.plotConditions();
            end
            
            obj.plotHypnogram();
            obj.updateEventCount();
            obj.linkAxes();
        end
        
        function valid_indices = getValidTimeIndices(obj)
            % Get valid time indices based on sleep stage filtering
            if ~obj.stage_filtering_enabled || isempty(obj.sleep_stages)
                valid_indices = true(size(obj.eeg_data.time{1}));
                return;
            end
            
            valid_indices = false(size(obj.eeg_data.time{1}));
            eeg_start_time = obj.eeg_data.time{1}(1);
            
            for i = 1:height(obj.sleep_stages)
                stage = obj.sleep_stages.Stage{i};
                
                if ismember(stage, obj.selected_stages)
                    if isdatetime(obj.sleep_stages.Timestamp)
                        stage_time = seconds(obj.sleep_stages.Timestamp(i) - obj.sleep_stages.Timestamp(1)) + eeg_start_time;
                    else
                        stage_time = obj.sleep_stages.Timestamp(i);
                    end
                    
                    epoch_start = stage_time;
                    epoch_end = stage_time + 30;
                    
                    time_mask = obj.eeg_data.time{1} >= epoch_start & obj.eeg_data.time{1} < epoch_end;
                    valid_indices = valid_indices | time_mask;
                end
            end
        end
        
        function clearPlots(obj)
            % Clear all plot elements
            cla(obj.ax_main);
            if ~isempty(obj.ax_conditions)
                cla(obj.ax_conditions);
            end
            cla(obj.ax_hypno);
            
            hold(obj.ax_main, 'on');
            if ~isempty(obj.ax_conditions)
                hold(obj.ax_conditions, 'on');
            end
            hold(obj.ax_hypno, 'on');
        end
        
        function plotNoData(obj)
            axes(obj.ax_main);
            text(0.5, 0.5, 'No data available for selected sleep stages in this time window', ...
                'Units', 'normalized', 'HorizontalAlignment', 'center', ...
                'FontSize', 14, 'Color', 'red');
            set(obj.info_text, 'String', 'No valid data in current window with stage filter active');
        end
        
        function plotEEG(obj, valid_indices)
            axes(obj.ax_main);
            
            t_start = obj.current_time - obj.window_size/2;
            t_end = obj.current_time + obj.window_size/2;
            
            time_vec = obj.eeg_data.time{1};
            sample_mask = time_vec >= t_start & time_vec <= t_end;
            
            if obj.stage_filtering_enabled
                sample_mask = sample_mask & valid_indices;
            end
            
            if ~any(sample_mask)
                obj.plotNoData();
                return;
            end
            
            plot_time = time_vec(sample_mask);
            plot_data = obj.eeg_data.trial{1}(:, sample_mask);
            
            n_channels = length(obj.selected_channels);
            
            for i = 1:n_channels
                ch_name = obj.selected_channels{i};
                ch_idx = find(strcmp(obj.eeg_data.label, ch_name));
                
                if ~isempty(ch_idx)
                    y_offset = (n_channels - i) * obj.channel_spacing;
                    
                    plot(obj.ax_main, plot_time, plot_data(ch_idx, :) * obj.amplitude_scale + y_offset, ...
                        'Color', 'k', 'LineWidth', 0.7);
                    
                    text(obj.ax_main, t_start + 0.01*obj.window_size, y_offset, ch_name, ...
                        'FontSize', 10, 'FontWeight', 'bold', 'Color', 'blue');
                end
            end
            
            xlim(obj.ax_main, [t_start, t_end]);
            ylim(obj.ax_main, [-obj.channel_spacing, n_channels * obj.channel_spacing]);
            
            y_lim = ylim(obj.ax_main);
            line(obj.ax_main, [obj.current_time, obj.current_time], ...
                y_lim, 'Color', 'r', 'LineWidth', 2, 'LineStyle', '--');
            
            grid(obj.ax_main, 'on');
            xlabel(obj.ax_main, 'Time (s)');
            title(obj.ax_main, sprintf('EEG Data - %s (%.1f - %.1f s)', ...
                obj.subject, t_start, t_end));
        end
        
        function plotChannelSpecificEvents(obj)
            axes(obj.ax_main);
            
            t_start = obj.current_time - obj.window_size/2;
            t_end = obj.current_time + obj.window_size/2;
            n_channels = length(obj.selected_channels);
            
            % Plot events
            if obj.show_spindles && height(obj.spindles) > 0
                obj.plotChannelEvents(obj.spindles, 'spindle', t_start, t_end, n_channels);
            end
            
            if obj.show_slowwaves && height(obj.slowwaves) > 0
                obj.plotChannelEvents(obj.slowwaves, 'slowwave', t_start, t_end, n_channels);
            end
            
            % Plot condition onset lines in main EEG plot
            if obj.show_conditions && ~isempty(obj.conditions_data)
                obj.plotConditionOnsetLines(t_start, t_end);
            end
        end
        
        function plotChannelEvents(obj, events, event_type, t_start, t_end, n_channels)
            if strcmp(event_type, 'spindle')
                time_col = 'Peak';
                color = obj.colors.spindle;
                marker = 'v';
            else
                time_col = 'NegPeak';
                color = obj.colors.slowwave;
                marker = '^';
            end
            
            if ismember(time_col, events.Properties.VariableNames)
                event_times = events.(time_col);
                in_window = event_times >= t_start & event_times <= t_end;
                window_events = events(in_window, :);
                
                for i = 1:height(window_events)
                    % Get event channel(s) - handle both single channels and multi-channel events
                    if iscell(window_events.Channel)
                        if iscell(window_events.Channel{i})
                            % Handle nested cell arrays
                            event_channels = window_events.Channel{i};
                        else
                            % Handle simple cell array
                            event_channels = {window_events.Channel{i}};
                        end
                    else
                        % Handle string/char arrays
                        event_channel_str = window_events.Channel(i);
                        if contains(event_channel_str, '+')
                            % Split multi-channel events (e.g., "C3+C4")
                            event_channels = strsplit(event_channel_str, '+');
                        else
                            event_channels = {event_channel_str};
                        end
                    end
                    
                    % Map event channels to EEG channels and show events for ALL matching channels
                    for ch = event_channels
                        original_ch_name = strtrim(ch{1});
                        
                        % Map channel name (remove A1/A2 suffixes)
                        eeg_ch_name = obj.findEEGChannel(original_ch_name);
                        
                        if ~isempty(eeg_ch_name)
                            % Find if this EEG channel is in our selected channels
                            ch_display_idx = find(strcmp(obj.selected_channels, eeg_ch_name));
                            
                            if ~isempty(ch_display_idx)
                                y_offset = (n_channels - ch_display_idx) * obj.channel_spacing;
                                event_time = window_events.(time_col)(i);
                                
                                % Place markers ABOVE the data line
                                marker_y = y_offset + obj.channel_spacing*0.2;
                                plot(obj.ax_main, event_time, marker_y, marker, ...
                                    'MarkerSize', 8, 'MarkerFaceColor', color, ...
                                    'MarkerEdgeColor', color*0.6, 'LineWidth', 1);
                                
                                % Duration lines below the data
                                if ismember('Start', window_events.Properties.VariableNames) && ...
                                   ismember('End', window_events.Properties.VariableNames)
                                    start_time = window_events.Start(i);
                                    end_time = window_events.End(i);
                                    % Duration line below the channel
                                    duration_y = y_offset - obj.channel_spacing*0.15;
                                    plot(obj.ax_main, [start_time, end_time], ...
                                        [duration_y, duration_y], ...
                                        'Color', color, 'LineWidth', 1.5);
                                end
                                
                                % Text annotations positioned above the marker
                                if strcmp(event_type, 'spindle') && ismember('Frequency', window_events.Properties.VariableNames)
                                    text(obj.ax_main, event_time + 0.3, marker_y + obj.channel_spacing*0.1, ...
                                        sprintf('%.1fHz', window_events.Frequency(i)), ...
                                        'FontSize', 7, 'Color', color*0.7, 'FontWeight', 'bold');
                                elseif strcmp(event_type, 'slowwave') && ismember('PTP', window_events.Properties.VariableNames)
                                    text(obj.ax_main, event_time + 0.3, marker_y + obj.channel_spacing*0.1, ...
                                        sprintf('%.0fμV', abs(window_events.PTP(i))), ...
                                        'FontSize', 7, 'Color', color*0.7, 'FontWeight', 'bold');
                                end
                            end
                        end
                    end
                end
            end
        end
        
        function plotConditionOnsetLines(obj, t_start, t_end)
            % Plot thin vertical lines for condition onsets/offsets in main EEG plot
            y_lim = ylim(obj.ax_main);
            
            for i = 1:length(obj.conditions_data)
                condition = obj.conditions_data(i);
                
                % Plot start line if in window
                if condition.start_time >= t_start && condition.start_time <= t_end
                    color = obj.getConditionColor(condition.name);
                    line(obj.ax_main, [condition.start_time, condition.start_time], y_lim, ...
                        'Color', color, 'LineWidth', 1, 'LineStyle', '-');
                    
                    % Add small text label at the top
                    text(obj.ax_main, condition.start_time + 0.1, y_lim(2) - obj.channel_spacing*0.1, ...
                        condition.name, 'FontSize', 6, 'Color', color, 'Rotation', 90);
                end
                
                % Plot end line if in window (different from start)
                if condition.end_time >= t_start && condition.end_time <= t_end && ...
                   condition.end_time ~= condition.start_time
                    color = obj.getConditionColor(condition.name);
                    line(obj.ax_main, [condition.end_time, condition.end_time], y_lim, ...
                        'Color', color*0.6, 'LineWidth', 1, 'LineStyle', '--');
                end
            end
        end
        
        function plotConditions(obj)
            if isempty(obj.ax_conditions) || isempty(obj.conditions_data)
                return;
            end
            
            axes(obj.ax_conditions);
            
            t_start = obj.current_time - obj.window_size/2;
            t_end = obj.current_time + obj.window_size/2;
            
            y_positions = containers.Map();
            condition_names = unique({obj.conditions_data.name});
            for i = 1:length(condition_names)
                y_positions(condition_names{i}) = i;
            end
            
            for i = 1:length(obj.conditions_data)
                condition = obj.conditions_data(i);
                
                if condition.end_time >= t_start && condition.start_time <= t_end
                    y_pos = y_positions(condition.name);
                    color = obj.getConditionColor(condition.name);
                    
                    start_x = max(condition.start_time, t_start);
                    end_x = min(condition.end_time, t_end);
                    
                    rectangle(obj.ax_conditions, 'Position', [start_x, y_pos-0.3, end_x-start_x, 0.6], ...
                        'FaceColor', color, 'EdgeColor', 'k', 'LineWidth', 0.5);
                    
                    if (end_x - start_x) > 2
                        text(obj.ax_conditions, (start_x + end_x)/2, y_pos, condition.name, ...
                            'HorizontalAlignment', 'center', 'FontSize', 8, 'FontWeight', 'bold');
                    end
                end
            end
            
            xlim(obj.ax_conditions, [t_start, t_end]);
            ylim(obj.ax_conditions, [0.5, length(condition_names) + 0.5]);
            set(obj.ax_conditions, 'YTick', 1:length(condition_names), 'YTickLabel', condition_names);
            ylabel(obj.ax_conditions, 'Conditions');
            grid(obj.ax_conditions, 'on');
            
            line(obj.ax_conditions, [obj.current_time, obj.current_time], ylim(obj.ax_conditions), ...
                'Color', 'r', 'LineWidth', 2, 'LineStyle', '--');
        end
        
        function color = getConditionColor(obj, condition_name)
            if contains(condition_name, 'refract')
                color = obj.condition_colors.refract;
            elseif contains(condition_name, 'ramping')
                color = obj.condition_colors.ramping;
            elseif contains(condition_name, '1HZ')
                color = obj.condition_colors.HZ1;
            elseif contains(condition_name, '5HZ')
                color = obj.condition_colors.HZ5;
            elseif contains(condition_name, 'OFF')
                color = obj.condition_colors.OFF;
            elseif contains(condition_name, 'NOSTIM')
                color = obj.condition_colors.NOSTIM;
            else
                color = [0.5, 0.5, 0.5];
            end
        end
        
        function plotHypnogram(obj)
            axes(obj.ax_hypno);
            
            if height(obj.sleep_stages) == 0
                text(obj.ax_hypno, 0.5, 0.5, 'No sleep stage data available', ...
                    'Units', 'normalized', 'HorizontalAlignment', 'center');
                return;
            end
            
            stage_map = containers.Map({'W', 'Wake', 'N1', 'N2', 'N3', 'REM', 'A', 'Movement'}, ...
                                     {0, 0, 1, 2, 3, -1, 4, 5});
            eeg_start_time = obj.eeg_data.time{1}(1);
            
            for i = 1:height(obj.sleep_stages)
                stage = obj.sleep_stages.Stage{i};
                
                if isdatetime(obj.sleep_stages.Timestamp)
                    stage_time = seconds(obj.sleep_stages.Timestamp(i) - obj.sleep_stages.Timestamp(1)) + eeg_start_time;
                else
                    stage_time = obj.sleep_stages.Timestamp(i);
                end
                
                if i < height(obj.sleep_stages)
                    if isdatetime(obj.sleep_stages.Timestamp)
                        next_time = seconds(obj.sleep_stages.Timestamp(i+1) - obj.sleep_stages.Timestamp(1)) + eeg_start_time;
                    else
                        next_time = obj.sleep_stages.Timestamp(i+1);
                    end
                    duration = next_time - stage_time;
                else
                    duration = 30;
                end
                
                if isKey(stage_map, stage)
                    stage_val = stage_map(stage);
                else
                    stage_val = 0;
                end
                
                if isfield(obj.colors, stage)
                    color = obj.colors.(stage);
                else
                    color = [0.7, 0.7, 0.7];
                end
                
                if obj.stage_filtering_enabled && ~ismember(stage, obj.selected_stages)
                    color = color * 0.3;
                end
                
                rectangle(obj.ax_hypno, 'Position', [stage_time, stage_val-0.4, duration, 0.8], ...
                    'FaceColor', color, 'EdgeColor', 'k', 'LineWidth', 0.5);
            end
            
            y_lim = [-1.5, 5.5];
            line(obj.ax_hypno, [obj.current_time, obj.current_time], y_lim, ...
                'Color', 'r', 'LineWidth', 2, 'LineStyle', '--');
            
            t_start = obj.current_time - obj.window_size/2;
            t_end = obj.current_time + obj.window_size/2;
            patch(obj.ax_hypno, [t_start, t_end, t_end, t_start], ...
                [y_lim(1), y_lim(1), y_lim(2), y_lim(2)], ...
                'r', 'FaceAlpha', 0.1, 'EdgeColor', 'none');
            
            ylim(obj.ax_hypno, y_lim);
            set(obj.ax_hypno, 'YTick', [-1, 0, 1, 2, 3, 4, 5], ...
                'YTickLabel', {'REM', 'Wake', 'N1', 'N2', 'N3', 'A', 'Move'});
            xlabel(obj.ax_hypno, 'Time (s)');
            ylabel(obj.ax_hypno, 'Sleep Stage');
            grid(obj.ax_hypno, 'on');
        end
        
        function updateEventCount(obj)
            t_start = obj.current_time - obj.window_size/2;
            t_end = obj.current_time + obj.window_size/2;
            
            n_spindles = 0;
            n_slowwaves = 0;
            
            if obj.show_spindles && height(obj.spindles) > 0 && ismember('Peak', obj.spindles.Properties.VariableNames)
                spindle_times = obj.spindles.Peak;
                n_spindles = sum(spindle_times >= t_start & spindle_times <= t_end);
            end
            
            if obj.show_slowwaves && height(obj.slowwaves) > 0 && ismember('NegPeak', obj.slowwaves.Properties.VariableNames)
                slowwave_times = obj.slowwaves.NegPeak;
                n_slowwaves = sum(slowwave_times >= t_start & slowwave_times <= t_end);
            end
            
            current_stage = obj.getCurrentSleepStage();
            current_condition = obj.getCurrentCondition();
            
            info_parts = {
                sprintf('Time: %.1f s', obj.current_time),
                sprintf('Window: %.1f s', obj.window_size),
                sprintf('Channels: %d', length(obj.selected_channels)),
                sprintf('Spindles: %d', n_spindles),
                sprintf('Slow waves: %d', n_slowwaves),
                sprintf('Stage: %s', current_stage)
            };
            
            if ~isempty(current_condition)
                info_parts{end+1} = sprintf('Condition: %s', current_condition);
            end
            
            if obj.stage_filtering_enabled
                info_parts{end+1} = sprintf('Filter: %s', strjoin(obj.selected_stages, ','));
            end
            
            info_str = strjoin(info_parts, '\n');
            set(obj.info_text, 'String', info_str);
        end
        
        function linkAxes(obj)
            if ~isempty(obj.ax_conditions)
                linkaxes([obj.ax_main, obj.ax_conditions, obj.ax_hypno], 'x');
            else
                linkaxes([obj.ax_main, obj.ax_hypno], 'x');
            end
        end
        
        function stage = getCurrentSleepStage(obj)
            if height(obj.sleep_stages) == 0
                stage = 'Unknown';
                return;
            end
            
            eeg_start_time = obj.eeg_data.time{1}(1);
            
            if isdatetime(obj.sleep_stages.Timestamp)
                stage_times = seconds(obj.sleep_stages.Timestamp - obj.sleep_stages.Timestamp(1)) + eeg_start_time;
            else
                stage_times = obj.sleep_stages.Timestamp;
            end
            
            stage_idx = find(stage_times <= obj.current_time, 1, 'last');
            
            if isempty(stage_idx)
                stage = 'Unknown';
            else
                stage = obj.sleep_stages.Stage{stage_idx};
            end
        end
        
        function condition = getCurrentCondition(obj)
            condition = '';
            if isempty(obj.conditions_data)
                return;
            end
            
            for i = 1:length(obj.conditions_data)
                cond = obj.conditions_data(i);
                if obj.current_time >= cond.start_time && obj.current_time <= cond.end_time
                    condition = cond.name;
                    break;
                end
            end
        end
        
        %% Callback functions
        function channelSelectionCallback(obj)
            selected = get(obj.channel_listbox, 'Value');
            obj.selected_channels = obj.eeg_data.label(selected);
            obj.updateDisplay();
        end
        
        function timeEditCallback(obj)
            new_time = str2double(get(obj.time_edit, 'String'));
            if ~isnan(new_time) && new_time >= 0
                max_time = obj.eeg_data.time{1}(end);
                obj.current_time = min(new_time, max_time);
                obj.updateDisplay();
            end
            set(obj.time_edit, 'String', num2str(obj.current_time));
        end
        
        function windowSizeCallback(obj)
            new_size = str2double(get(obj.window_edit, 'String'));
            if ~isnan(new_size) && new_size > 0
                obj.window_size = new_size;
                obj.updateDisplay();
            end
            set(obj.window_edit, 'String', num2str(obj.window_size));
        end
        
        function spacingCallback(obj)
            new_spacing = str2double(get(obj.spacing_edit, 'String'));
            if ~isnan(new_spacing) && new_spacing > 0
                obj.channel_spacing = new_spacing;
                obj.updateDisplay();
            end
            set(obj.spacing_edit, 'String', num2str(obj.channel_spacing));
        end
        
        function scaleCallback(obj)
            new_scale = str2double(get(obj.scale_edit, 'String'));
            if ~isnan(new_scale) && new_scale > 0
                obj.amplitude_scale = new_scale;
                obj.updateDisplay();
            end
            set(obj.scale_edit, 'String', num2str(obj.amplitude_scale));
        end
        
        function toggleSpindles(obj)
            obj.show_spindles = get(obj.spindle_checkbox, 'Value');
            obj.updateDisplay();
        end
        
        function toggleSlowwaves(obj)
            obj.show_slowwaves = get(obj.slowwave_checkbox, 'Value');
            obj.updateDisplay();
        end
        
        function toggleConditions(obj)
            if ~isempty(obj.conditions_checkbox)
                obj.show_conditions = get(obj.conditions_checkbox, 'Value');
                obj.updateDisplay();
            end
        end
        
        function toggleStageFiltering(obj)
            obj.stage_filtering_enabled = get(obj.stage_filter_checkbox, 'Value');
            
            if ~isempty(obj.stage_listbox)
                if obj.stage_filtering_enabled
                    set(obj.stage_listbox, 'Enable', 'on');
                else
                    set(obj.stage_listbox, 'Enable', 'off');
                end
            end
            
            obj.updateDisplay();
        end
        
        function stageSelectionCallback(obj)
            if ~isempty(obj.stage_listbox)
                selected_indices = get(obj.stage_listbox, 'Value');
                obj.selected_stages = obj.available_stages(selected_indices);
                if obj.stage_filtering_enabled
                    obj.updateDisplay();
                end
            end
        end
        
        function navigate(obj, delta_sec)
            max_time = obj.eeg_data.time{1}(end);
            obj.current_time = max(0, min(obj.current_time + delta_sec, max_time));
            set(obj.time_edit, 'String', num2str(obj.current_time));
            obj.updateDisplay();
        end
        
        function jumpToNextEvent(obj, event_type)
            if strcmp(event_type, 'spindle') && height(obj.spindles) > 0
                if ismember('Peak', obj.spindles.Properties.VariableNames)
                    event_times = obj.spindles.Peak;
                else
                    return;
                end
            elseif strcmp(event_type, 'slowwave') && height(obj.slowwaves) > 0
                if ismember('NegPeak', obj.slowwaves.Properties.VariableNames)
                    event_times = obj.slowwaves.NegPeak;
                else
                    return;
                end
            else
                return;
            end
            
            future_events = event_times(event_times > obj.current_time);
            if ~isempty(future_events)
                obj.current_time = future_events(1);
            else
                obj.current_time = event_times(1);
            end
            
            set(obj.time_edit, 'String', num2str(obj.current_time));
            obj.updateDisplay();
        end
        
        function keyPressCallback(obj, evt)
            switch evt.Key
                case 'leftarrow'
                    if ismember('shift', evt.Modifier)
                        obj.navigate(-30);
                    else
                        obj.navigate(-5);
                    end
                case 'rightarrow'
                    if ismember('shift', evt.Modifier)
                        obj.navigate(30);
                    else
                        obj.navigate(5);
                    end
                case 'uparrow'
                    obj.window_size = min(obj.window_size * 1.5, 300);
                    set(obj.window_edit, 'String', num2str(obj.window_size));
                    obj.updateDisplay();
                case 'downarrow'
                    obj.window_size = max(obj.window_size / 1.5, 5);
                    set(obj.window_edit, 'String', num2str(obj.window_size));
                    obj.updateDisplay();
                case 'space'
                    obj.jumpToNextEvent('spindle');
                case 's'
                    obj.stage_filtering_enabled = ~obj.stage_filtering_enabled;
                    set(obj.stage_filter_checkbox, 'Value', obj.stage_filtering_enabled);
                    obj.toggleStageFiltering();
                case 'c'
                    if ~isempty(obj.conditions_checkbox)
                        obj.show_conditions = ~obj.show_conditions;
                        set(obj.conditions_checkbox, 'Value', obj.show_conditions);
                        obj.updateDisplay();
                    end
            end
        end
        
        function scrollCallback(obj, evt)
            zoom_factor = 1.2;
            if evt.VerticalScrollCount > 0
                obj.window_size = min(obj.window_size * zoom_factor, 300);
            else
                obj.window_size = max(obj.window_size / zoom_factor, 1);
            end
            set(obj.window_edit, 'String', num2str(obj.window_size));
            obj.updateDisplay();
        end
    end
end

function result = spindlePilot_iif(condition, true_value, false_value)
    if condition
        result = true_value;
    else
        result = false_value;
    end
end
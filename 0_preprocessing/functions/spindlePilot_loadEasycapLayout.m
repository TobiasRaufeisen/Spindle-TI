function elec = spindlePilot_loadEasycapLayout(layout_file)
% spindlePilot_loadEasycapLayout loads EasyCap electrode layouts from .mat files
%
% This function specifically handles EasyCap .mat files and converts them
% to FieldTrip-compatible electrode structures with 3D positions.
%
% Usage:
%   elec = spindlePilot_loadEasycapLayout(layout_file)
%
% Input:
%   layout_file - Path to the EasyCap .mat file (e.g., 'EasycapM22.mat')
%
% Output:
%   elec - FieldTrip electrode structure with 3D positions for interpolation

fprintf('Loading EasyCap layout from: %s\n', layout_file);

try
    % Load the .mat file
    layout_data = load(layout_file);
    
    % Display available fields to help identify the electrode structure
    field_names = fieldnames(layout_data);
    fprintf('Available fields in .mat file: %s\n', strjoin(field_names, ', '));
    
    % Try to automatically identify the electrode structure
    elec_struct = [];
    elec_field = '';
    
    % Common field names for electrode structures
    possible_fields = {'elec', 'electrode', 'electrodes', 'cap', 'layout', 'pos', 'positions'};
    
    for p = 1:length(possible_fields)
        for f = 1:length(field_names)
            if contains(lower(field_names{f}), possible_fields{p})
                elec_field = field_names{f};
                elec_struct = layout_data.(elec_field);
                fprintf('Found potential electrode structure in field: %s\n', elec_field);
                break;
            end
        end
        if ~isempty(elec_struct), break; end
    end
    
    % If automatic detection failed, try the first structure field
    if isempty(elec_struct)
        for f = 1:length(field_names)
            if isstruct(layout_data.(field_names{f}))
                elec_field = field_names{f};
                elec_struct = layout_data.(elec_field);
                fprintf('Using structure field: %s\n', elec_field);
                break;
            end
        end
    end
    
    if isempty(elec_struct)
        error('Could not find electrode structure in the .mat file');
    end
    
    % Display the structure to understand its format
    fprintf('Electrode structure fields: %s\n', strjoin(fieldnames(elec_struct), ', '));
    
    % Try to create a FieldTrip-compatible electrode structure
    elec_ft = struct();
    
    % Look for channel labels
    label_fields = {'label', 'labels', 'channelLabels', 'channels', 'names'};
    for lf = 1:length(label_fields)
        if isfield(elec_struct, label_fields{lf})
            elec_ft.label = elec_struct.(label_fields{lf});
            fprintf('Found channel labels in field: %s (%d channels)\n', ...
                    label_fields{lf}, length(elec_ft.label));
            break;
        end
    end
    
    % Look for electrode positions
    pos_fields = {'pos', 'position', 'positions', 'chanpos', 'elecpos', 'xyz', 'coordinates'};
    for pf = 1:length(pos_fields)
        if isfield(elec_struct, pos_fields{pf})
            positions = elec_struct.(pos_fields{pf});
            if size(positions, 2) >= 2  % At least 2D positions
                elec_ft.chanpos = positions;
                elec_ft.elecpos = positions;
                fprintf('Found electrode positions in field: %s (%dx%d matrix)\n', ...
                        pos_fields{pf}, size(positions, 1), size(positions, 2));
                break;
            end
        end
    end
    
    % Ensure we have both labels and positions
    if ~isfield(elec_ft, 'label') || ~isfield(elec_ft, 'chanpos')
        error('Could not find both channel labels and positions in the electrode structure');
    end
    
    % Ensure labels are cell array of strings
    if ~iscell(elec_ft.label)
        if ischar(elec_ft.label)
            elec_ft.label = cellstr(elec_ft.label);
        else
            error('Channel labels must be strings or cell array of strings');
        end
    end
    
    % Ensure positions have at least 3 dimensions (add z=0 if needed)
    if size(elec_ft.chanpos, 2) == 2
        fprintf('Converting 2D positions to 3D (adding z=0)\n');
        elec_ft.chanpos = [elec_ft.chanpos, zeros(size(elec_ft.chanpos, 1), 1)];
        elec_ft.elecpos = elec_ft.chanpos;
    end
    
    % Ensure label and position counts match
    if length(elec_ft.label) ~= size(elec_ft.chanpos, 1)
        error('Number of channel labels (%d) does not match number of positions (%d)', ...
              length(elec_ft.label), size(elec_ft.chanpos, 1));
    end
    
    % Add units if not present
    if ~isfield(elec_ft, 'unit')
        elec_ft.unit = 'mm';  % Assume millimeters
    end

    % Return the 3D electrode structure directly (do NOT convert to 2D layout)
    % This preserves the 3D coordinates needed for proper spherical spline interpolation
    elec = elec_ft;

    % Verify we have 3D positions
    if size(elec.chanpos, 2) ~= 3
        error('Electrode structure must have 3D positions (X, Y, Z coordinates)');
    end

    % Check if all Z coordinates are zero (would cause coplanar electrode problem)
    if all(elec.chanpos(:,3) == 0)
        warning('All Z coordinates are zero - electrodes are coplanar. This may cause interpolation issues.');
    end

    fprintf('Successfully loaded FieldTrip electrode structure with %d electrodes (3D positions)\n', length(elec.label));
    
catch ME
    fprintf('Error loading EasyCap layout: %s\n', ME.message);
    
    rethrow(ME);
end
end
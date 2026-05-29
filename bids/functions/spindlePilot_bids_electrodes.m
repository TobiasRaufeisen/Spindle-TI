function electrodesTable = spindlePilot_bids_electrodes(eegLabels)
% SPINDLEPILOT_BIDS_ELECTRODES  Build a BIDS _electrodes.tsv from the EasyCap M1 layout.
%
%   electrodesTable = spindlePilot_bids_electrodes(EEGLABELS)
%
%   Reads the same EasyCap M1 layout used by the preprocessing pipeline
%   (loadEasycapLayout / easycapM1.mat shipped with FieldTrip) and emits
%   one row per requested EEG label with columns name, x, y, z, type,
%   material, size.
%
%   The shipped layout is 2D; z is set to 0. This is recorded honestly in
%   coordsystem.json (EEGCoordinateSystem = "Other", template positions).
%
%   Non-EEG channels (EMG, EOG, AUX) are NOT included; _electrodes.tsv is
%   only for scalp EEG electrodes.
%
% Author: Tobias Raufeisen

    arguments
        eegLabels cell
    end

    layoutFile = 'easycapM1.mat';
    layoutPath = which(layoutFile);
    if isempty(layoutPath)
        error('spindlePilot_bids_electrodes:LayoutNotFound', ...
              ['Could not locate %s on the MATLAB path. Make sure FieldTrip ', ...
               'has been initialised via spindlePilot_startup.'], layoutFile);
    end

    S = load(layoutPath);
    if isfield(S, 'lay')
        lay = S.lay;
    else
        fn = fieldnames(S);
        lay = S.(fn{1});
    end
    if ~isfield(lay,'label') || ~isfield(lay,'pos')
        error('spindlePilot_bids_electrodes:BadLayout', ...
              'Layout file %s does not contain expected fields label and pos.', layoutPath);
    end

    layoutLabels = lay.label;
    layoutPos    = lay.pos;

    n = numel(eegLabels);
    x = nan(n,1); y = nan(n,1); z = zeros(n,1);
    type     = repmat({'cup'},     n, 1);
    material = repmat({'Ag/AgCl'}, n, 1);
    sizeMm   = repmat({'n/a'},     n, 1);

    for i = 1:n
        idx = find(strcmpi(layoutLabels, eegLabels{i}), 1);
        if isempty(idx)
            warning('spindlePilot_bids_electrodes:LabelMissing', ...
                    'Channel %s not found in EasyCap M1 layout.', eegLabels{i});
            continue;
        end
        x(i) = layoutPos(idx,1);
        y(i) = layoutPos(idx,2);
    end

    electrodesTable = table(eegLabels(:), x, y, z, type, material, sizeMm, ...
        'VariableNames', {'name','x','y','z','type','material','size'});
end

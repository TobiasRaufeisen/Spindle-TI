function [allData, analysisData, edfData] = spindlePilot_finalizeAndSave(allData, saveDir)
% Rename AUX channels in allData, then build & save:
% • complete: .mat with everything (AUX relabeled)
% • analysis: .mat with eeg_main (no Marker) + epochedData
% • EDF: .edf, 256Hz, mastoid suffix (preserving the digit), no Marker
% Returns updated allData, plus analysisData and edfData structs.

%% 1) Rename AUX channels in allData (ALL EEG data structures)
subs = fieldnames(allData);
for si = 1:numel(subs)
    s = subs{si};
    sess = fieldnames(allData.(s));
    for qi = 1:numel(sess)
        q = sess{qi};
        
        % Rename in main eeg structure
        if isfield(allData.(s).(q),'eeg')
            D = allData.(s).(q).eeg;
            D.label = cellfun(@auxRelabel, D.label, 'uni', false);
            allData.(s).(q).eeg = D;
        end
        
        % Rename in eeg_main structure
        if isfield(allData.(s).(q),'eeg_main')
            D = allData.(s).(q).eeg_main;
            D.label = cellfun(@auxRelabel, D.label, 'uni', false);
            allData.(s).(q).eeg_main = D;
        end
        
        % Rename in epochedData structures
        if isfield(allData.(s).(q),'epochedData')
            epochFields = fieldnames(allData.(s).(q).epochedData);
            for ef = 1:numel(epochFields)
                fld = epochFields{ef};
                if isfield(allData.(s).(q).epochedData.(fld), 'label')
                    allData.(s).(q).epochedData.(fld).label = ...
                        cellfun(@auxRelabel, allData.(s).(q).epochedData.(fld).label, 'uni', false);
                end
            end
        end
        
        % Rename in epochedData_withArtifacts structures
        if isfield(allData.(s).(q),'epochedData_withArtifacts')
            epochFields = fieldnames(allData.(s).(q).epochedData_withArtifacts);
            for ef = 1:numel(epochFields)
                fld = epochFields{ef};
                if isfield(allData.(s).(q).epochedData_withArtifacts.(fld), 'label')
                    allData.(s).(q).epochedData_withArtifacts.(fld).label = ...
                        cellfun(@auxRelabel, allData.(s).(q).epochedData_withArtifacts.(fld).label, 'uni', false);
                end
            end
        end
        
        % Rename in rejectedChannelsList
        if isfield(allData.(s).(q),'rejectedChannelsList')
            allData.(s).(q).rejectedChannelsList = ...
                cellfun(@auxRelabel, allData.(s).(q).rejectedChannelsList, 'uni', false);
        end
    end
end

%% 2) Ensure save-dirs exist
completeDir = fullfile(saveDir,'complete');
analysisDir = fullfile(saveDir,'analysis');
edfDir = fullfile(saveDir,'EDF');
if ~exist(completeDir,'dir'), mkdir(completeDir); end
if ~exist(analysisDir,'dir'), mkdir(analysisDir); end
if ~exist(edfDir,'dir'), mkdir(edfDir); end

%% 3) Loop & build outputs
analysisData = struct();
edfData = struct();

for si = 1:numel(subs)
    s = subs{si};
    sessions = fieldnames(allData.(s));
    for qi = 1:numel(sessions)
        q = sessions{qi};
        
        % A) SAVE COMPLETE - entire subject/session data structure with hierarchy
        allData_saved = struct();
        allData_saved.(s).(q) = allData.(s).(q); % Maintain full hierarchy
        fnC = sprintf('%s_%s_COMPLETE.mat', s, q);
        allData = allData_saved;
        save(fullfile(completeDir,fnC), 'allData_saved', '-v7.3');
        
        % B) ANALYSIS - eeg (no Marker) + epochedData (no Marker) with full structure
        % Process eeg (remove Marker channel - handle different possible names)
        markerChannels = findMarkerChannels(allData.(s).(q).eeg.label);
        cfgA = [];
        cfgA.channel = setdiff(allData.(s).(q).eeg.label, markerChannels);
        eegData = ft_selectdata(cfgA, allData.(s).(q).eeg);
        fprintf('  Analysis: Removed %d marker channel(s) from continuous EEG (%d channels remaining)\n', ...
                length(markerChannels), length(eegData.label));
        
        % Create analysis structure maintaining subject/session hierarchy
        analysisData.(s).(q) = struct();
        analysisData.(s).(q).eeg = eegData;  % processed eeg without Marker
        
        % Process epochedData (remove Marker channel from all conditions)
        if isfield(allData.(s).(q), 'epochedData')
            analysisData.(s).(q).epochedData = struct();
            epochFields = fieldnames(allData.(s).(q).epochedData);
            for ef = 1:numel(epochFields)
                fld = epochFields{ef};
                epochMarkerChannels = findMarkerChannels(allData.(s).(q).epochedData.(fld).label);
                cfgEpoch = [];
                cfgEpoch.channel = setdiff(allData.(s).(q).epochedData.(fld).label, epochMarkerChannels);
                analysisData.(s).(q).epochedData.(fld) = ft_selectdata(cfgEpoch, allData.(s).(q).epochedData.(fld));
            end
            fprintf('  Analysis: Removed marker channel(s) from %d epoched conditions\n', length(epochFields));
        end

        % Process epochedData_rejectedTrials (remove Marker channel from all conditions)
        if isfield(allData.(s).(q), 'epochedData_rejectedTrials')
            analysisData.(s).(q).epochedData_rejectedTrials = struct();
            rejectedFields = fieldnames(allData.(s).(q).epochedData_rejectedTrials);
            for ef = 1:numel(rejectedFields)
                fld = rejectedFields{ef};
                rejectedMarkerChannels = findMarkerChannels(allData.(s).(q).epochedData_rejectedTrials.(fld).label);
                cfgRejected = [];
                cfgRejected.channel = setdiff(allData.(s).(q).epochedData_rejectedTrials.(fld).label, rejectedMarkerChannels);
                analysisData.(s).(q).epochedData_rejectedTrials.(fld) = ft_selectdata(cfgRejected, allData.(s).(q).epochedData_rejectedTrials.(fld));
            end
            fprintf('  Analysis: Removed marker channel(s) from %d rejected trial conditions\n', length(rejectedFields));
        end
        
        % Save individual analysis file with full hierarchy
        analysisData_saved = struct();
        analysisData_saved.(s).(q) = analysisData.(s).(q);
        fnA = sprintf('%s_%s_ANALYSIS.mat', s, q);
        analysisData = analysisData_saved;
        save(fullfile(analysisDir,fnA), 'analysisData_saved', '-v7.3');
        
        % C) EDF - resampled to 256Hz, no Marker, with mastoid suffixes
        cfgR = [];
        cfgR.resamplefs = 256;
        cfgR.detrend = 'no';
        dE = ft_resampledata(cfgR, allData.(s).(q).eeg);
        
        % Remove marker channels (handle different possible names)
        edfMarkerChannels = findMarkerChannels(dE.label);
        cfgE = [];
        cfgE.channel = setdiff(dE.label, edfMarkerChannels);
        dE = ft_selectdata(cfgE, dE);
        fprintf('  EDF: Removed %d marker channel(s), resampled to 256Hz (%d channels remaining)\n', ...
                length(edfMarkerChannels), length(dE.label));
        
        % Apply mastoid suffix but skip renamed AUX channels (they already have suffixes)
        dE.label = cellfun(@mastoidSuffix, dE.label, 'uni', false);
        dE.label = matlab.lang.makeUniqueStrings(dE.label);
        hdr = ft_fetch_header(dE);
        edfName = sprintf('%s_%s.edf', s, q);
        ft_write_data(fullfile(edfDir,edfName), ...
            dE.trial{1}, ...
            'header', hdr, ...
            'dataformat', 'edf');
        edfData.(s).(q) = dE;
    end
end
end

%% helper: find marker channels (handles different naming conventions)
function markerChannels = findMarkerChannels(channelLabels)
% Find channels that are likely marker/trigger channels
markerChannels = {};
possibleMarkerNames = {'Marker', 'MARKER', 'marker', 'Trigger', 'TRIGGER', 'trigger', 'STI', 'Status'};

for i = 1:length(channelLabels)
    ch = channelLabels{i};
    % Check exact matches
    if ismember(ch, possibleMarkerNames)
        markerChannels{end+1} = ch;
    % Check partial matches (case-insensitive)
    elseif contains(lower(ch), 'marker') || contains(lower(ch), 'trigger') || contains(lower(ch), 'sti')
        markerChannels{end+1} = ch;
    end
end
end

%% helper: rename AUX globally
function nl = auxRelabel(lbl)
switch lbl
    case 'AUX_1', nl = 'EMG1EMG2';
    case 'AUX_2', nl = 'LOCA2';
    case 'AUX_3', nl = 'ROCA2';
    otherwise nl = lbl;
end
end

%% helper: append A1/A2 for EDF, preserving the numeric suffix
% BUT skip renamed AUX channels (they already have appropriate suffixes)
function nl = mastoidSuffix(lbl)
% Skip renamed AUX channels - they already have their final names
if ismember(lbl, {'EMG1EMG2', 'LOCA2', 'ROCA2'})
    nl = lbl;
    return;
end

% Apply mastoid suffix to regular EEG channels
tok = regexp(lbl,'^(.+?)(\d+)$','tokens');
if ~isempty(tok)
    base = tok{1}{1};
    num = tok{1}{2}; % keep as string
    nval = str2double(num);
    if mod(nval,2)==0 % even → reference to left mastoid = A1
        suffix = 'A1';
    else % odd → reference to right mastoid = A2
        suffix = 'A2';
    end
    nl = [base num suffix];
else
    nl = lbl;
end
end
function allData = spindlePilot_rereferenceMainData(allData, refChannel)
% Applies re-referencing to main EEG data in allData.
% refChannel can be:
%   - 'all' or 'average'    → average-reference
%   - string or cell array  → list of channels to use as reference (e.g. {'TP9','TP10'})

if nargin<2
    refChannel = 'all';
end

subjects = fieldnames(allData);
for i = 1:numel(subjects)
    subj = subjects{i};
    sessions = fieldnames(allData.(subj));
    for j = 1:numel(sessions)
        sess = sessions{j};
        if ~isfield(allData.(subj).(sess),'eeg_main') || isempty(allData.(subj).(sess).eeg_main)
            continue
        end

        data = allData.(subj).(sess).eeg_main;

        % Determine reference list
        if ischar(refChannel) && any(strcmpi(refChannel,{'all','average'}))
            refList = 'all';
        else
            % allow string or cell input
            if ischar(refChannel), refList = {refChannel};
            else             refList = refChannel;
            end
            % ensure they exist
            missing = setdiff(refList, data.label);
            if ~isempty(missing)
                error('Reference channel(s) not found: %s', strjoin(missing,','));
            end
        end

        % Re-reference
        cfg = [];
        cfg.reref       = 'yes';
        cfg.refchannel  = refList;
        cfg.keepchannel = 'yes';
        eeg_reref = ft_preprocessing(cfg, data);
        allData.(subj).(sess).eeg_main = eeg_reref;

        % record what you did
        allData.(subj).(sess).referenceChannel = refChannel;
    end
end
end

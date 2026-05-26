function allData = spindlePilot_interpolateChannels(allData, layout_file)
% Interpolate rejected channels in allData.*.*.eeg_main
% using EasyCap layout in layout_file and local neighbours.

% ---------- 1) Load electrode positions once ----------
elecBase = spindlePilot_loadEasycapLayout(layout_file);  % your loader

subs = fieldnames(allData);

% ---------- 2) Loop over subjects / sessions ----------
for si = 1:numel(subs)
    s = subs{si};
    sess = fieldnames(allData.(s));

    for qi = 1:numel(sess)
        q = sess{qi};

        % ----- basic checks -----
        if ~isfield(allData.(s).(q),'eeg_main') || isempty(allData.(s).(q).eeg_main)
            fprintf('[%s %s] No eeg_main found, skipping.\n', s, q);
            continue
        end

        if ~isfield(allData.(s).(q),'rejectedChannelsList')
            fprintf('[%s %s] No rejectedChannelsList field, skipping.\n', s, q);
            continue
        end

        badChans = allData.(s).(q).rejectedChannelsList;
        if isempty(badChans)
            fprintf('[%s %s] rejectedChannelsList is empty, nothing to interpolate.\n', s, q);
            continue
        end

        data = allData.(s).(q).eeg_main;
        dataLabels = data.label(:);

        % ---------- 3) Session-specific electrode struct ----------
        % Need electrode positions for BOTH existing and rejected channels
        elec = elecBase;
        neededLabels = union(dataLabels, badChans(:));
        keep = ismember(elec.label, neededLabels);
        elec.label   = elec.label(keep);
        elec.chanpos = elec.chanpos(keep,:);
        if isfield(elec,'elecpos')
            elec.elecpos = elec.elecpos(keep,:);
        end

        if numel(elec.label) ~= size(elec.chanpos,1)
            fprintf('[%s %s] Label/position mismatch in electrode struct, skipping.\n', s, q);
            continue
        end

        % ---------- 4) Auto neighbour distance from actual subset ----------
        D = squareform(pdist(elec.chanpos));   % pairwise distances
        D(D==0) = NaN;
        nn = nanmin(D,[],2);                   % nearest-neighbour distance per channel
        neighdist = 2 * nanmedian(nn);       % conservative radius

        cfgN = [];
        cfgN.elec          = elec;
        cfgN.method        = 'distance';
        cfgN.neighbourdist = neighdist;
        neighbours = ft_prepare_neighbours(cfgN);

        % Determine which channels have neighbours at all
        hasNeigh = ~cellfun(@isempty,{neighbours.neighblabel});
        neighLabels = {neighbours(hasNeigh).label};

        % Drop bad channels that have no neighbours (cannot interpolate them)
        badChansInterp = badChans(ismember(badChans, neighLabels));
        if isempty(badChansInterp)
            badChanNames = allData.(s).(q).rejectedChannels.labels;
            warning('spindlePilot:interpolateChannels:NoNeighbors', ...
                    '[%s %s] Rejected channels have no neighbours, cannot interpolate. Channels: %s', ...
                    s, q, strjoin(badChanNames, ', '));

            % Store interpolation warning in metadata
            if ~isfield(allData.(s).(q), 'interpolation_warnings')
                allData.(s).(q).interpolation_warnings = {};
            end
            allData.(s).(q).interpolation_warnings{end+1} = ...
                sprintf('Could not interpolate channels (no neighbors): %s', strjoin(badChanNames, ', '));

            continue
        end

        fprintf('[%s %s] Interpolating %d channels (neighdist=%.3f, %d/%d channels have neighbours): %s\n', ...
            s, q, numel(badChansInterp), neighdist, ...
            sum(hasNeigh), numel(neighbours), strjoin(badChansInterp', ', '));

        % ---------- 5) Interpolate ----------
        cfg = [];
        cfg.method         = 'nearest';
        cfg.elec           = elec;
        cfg.neighbours     = neighbours;
        cfg.missingchannel = badChansInterp;   % may be absent from data.label
        cfg.keepchannel    = 'yes';
        data_final = ft_channelrepair(cfg, data);

        allData.(s).(q).eeg_main = data_final;
    end
end

fprintf('Interpolation pass completed.\n');
end

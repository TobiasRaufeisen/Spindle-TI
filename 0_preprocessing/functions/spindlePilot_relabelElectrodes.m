function allData = spindlePilot_relabelElectrodes(allData)
%RELABELELECTRODES Replace old EEG channel names with new ones in allData.
%
%   allData = RELABELELECTRODES(allData) walks through every subject,
%   session and sub-structure in the supplied ALLDATA struct.  Wherever a
%   field named “label” exists, it swaps the old electrode names for their
%   corrected counterparts.

% ----- mapping (old → new) ------------------------------------------------
old = {'Fp1','Fz','F3','F7','FT9','FC5','FC1','C3','T7','TP9','CP5','CP1',...
       'Pz','P3','P7','O1','Oz','O2','P4','P8','TP10','CP6','CP2','Cz',...
       'C4','T8','FT10','FC6','FC2','F4','F8','Fp2', ...
       'AUX_1','AUX_2','AUX_3','AUX_4','Markers'};

new = {'Fp1','Fp2','F7','F3','Fz','F4','F8','FC5','FC1','FC2','FC6','T7', ...
       'C3','Cz','C4','T8','TP9','CP5','CP1','CP2','CP6','TP10', ...
       'P7','P3','Pz','P4','P8','POz','O1','O2','XX','XXX', ...
       'AUX_1','AUX_2','AUX_3','AUX_4','Markers'};

% ----- iterate subjects → sessions → sub-fields ---------------------------
subs = fieldnames(allData);
for s = 1:numel(subs)
    sess = fieldnames(allData.(subs{s}));
    for i = 1:numel(sess)
        seg  = allData.(subs{s}).(sess{i});
        fn   = fieldnames(seg);
        for k = 1:numel(fn)
            blk = seg.(fn{k});
            if isfield(blk,'label')
                [~,ix]    = ismember(blk.label,old);
                keep      = ix>0;
                blk.label(keep) = new(ix(keep));
                seg.(fn{k})     = blk;
            end
        end
        allData.(subs{s}).(sess{i}) = seg;
    end
end
end

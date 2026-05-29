function channelsTable = spindlePilot_bids_channels(labels, samplingFrequency)
% SPINDLEPILOT_BIDS_CHANNELS  Build a BIDS _channels.tsv table.
%
%   channelsTable = spindlePilot_bids_channels(LABELS, SAMPLINGFREQUENCY)
%
%   Inputs
%     labels             Cell array of channel labels in file order, after
%                        spindlePilot_relabelElectrodes has been applied.
%                        Should NOT contain the dropped channels (AUX_4, Markers,
%                        and the two non-standard EasyCap positions 'XX'/'XXX').
%     samplingFrequency  Scalar Hz (same for every channel in BrainVision).
%
%   Output
%     channelsTable      MATLAB table with the BIDS-required columns:
%                        name, type, units, sampling_frequency, low_cutoff,
%                        high_cutoff, notch, status, status_description.
%
%   Conventions
%     - The 30 scalp EEG channels are assigned type 'EEG'.
%     - AUX_1 is the submental EMG (type 'EMG'); AUX_2 / AUX_3 are the left /
%       right EOG (type 'EOG'), each referenced to the contralateral mastoid.
%     - Units are microvolts for all signals.
%     - low_cutoff / high_cutoff are reported as 'n/a' because the raw data
%       are unfiltered (the hardware low-pass is for anti-aliasing only).
%
% Author: Tobias Raufeisen

    arguments
        labels             cell
        samplingFrequency  (1,1) double
    end

    eegLabels = { ...
        'Fp1','Fp2','F7','F3','Fz','F4','F8','FC5','FC1','FC2','FC6','T7', ...
        'C3','Cz','C4','T8','TP9','CP5','CP1','CP2','CP6','TP10', ...
        'P7','P3','Pz','P4','P8','POz','O1','O2'};

    n = numel(labels);
    type   = repmat({'MISC'}, n, 1);
    units  = repmat({'uV'},   n, 1);

    for i = 1:n
        lbl = labels{i};
        if any(strcmp(lbl, eegLabels))
            type{i} = 'EEG';
        elseif strcmp(lbl, 'AUX_1')
            type{i} = 'EMG';
        elseif strcmp(lbl, 'AUX_2') || strcmp(lbl, 'AUX_3')
            type{i} = 'EOG';
        end
    end

    fs        = repmat(samplingFrequency, n, 1);
    lowCut    = repmat({'n/a'}, n, 1);
    highCut   = repmat({'n/a'}, n, 1);
    notch     = repmat({'n/a'}, n, 1);
    status    = repmat({'good'}, n, 1);
    statusDesc = repmat({'n/a'}, n, 1);

    channelsTable = table(labels(:), type, units, fs, lowCut, highCut, notch, status, statusDesc, ...
        'VariableNames', {'name','type','units','sampling_frequency', ...
                          'low_cutoff','high_cutoff','notch','status','status_description'});
end

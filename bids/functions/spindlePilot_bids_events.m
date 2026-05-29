function eventsTable = spindlePilot_bids_events(eventMarker, eegStartTime, trialDurationS)
% SPINDLEPILOT_BIDS_EVENTS  Build a BIDS _events.tsv table from an LSL StimMarkers stream.
%
%   eventsTable = spindlePilot_bids_events(EVENTMARKER, EEGSTARTTIME, TRIALDURATIONS)
%
%   Inputs
%     eventMarker     Struct as returned by load_xdf for the StimMarkers stream,
%                     with fields time_stamps (1 x N double) and time_series
%                     (1 x N cell of char arrays).
%     eegStartTime    Earliest EEG sample's original LSL timestamp (scalar).
%                     Used to express marker onsets relative to the EEG file
%                     start (BIDS requires onset relative to the recording start).
%     trialDurationS  Nominal trial duration in seconds (8 for this protocol).
%
%   Output
%     eventsTable     MATLAB table with columns onset, duration, trial_type,
%                     stim_phase, block, trial, value. Sorted by onset.
%
%   Marker grammar (see 0_preprocessing/functions/spindlePilot_createEpochsAllData.m):
%     STIM_START / STIM_STOP                      -> boundary markers
%     <COND>_<BBB>_<TTT>                          -> regular trial
%     <COND>_refract_<BBB>_<TTT>                  -> refractory window
%     <COND>_rampingUp_<BBB>_<TTT>                -> 5 s up-ramp
%     <COND>_rampingDown_<BBB>_<TTT>              -> 5 s down-ramp
%   where COND is one of OFF, 1HZ, 5HZ.
%
% Author: Tobias Raufeisen

    arguments
        eventMarker     struct
        eegStartTime    (1,1) double
        trialDurationS  (1,1) double = 8
    end

    if ~isfield(eventMarker, 'time_stamps') || ~isfield(eventMarker, 'time_series')
        error('spindlePilot_bids_events:BadInput', ...
              'eventMarker must contain time_stamps and time_series fields.');
    end

    ts     = double(eventMarker.time_stamps(:));
    labels = eventMarker.time_series(:);
    if isempty(ts)
        eventsTable = emptyTable();
        return;
    end

    onsets       = ts - eegStartTime;
    nEv          = numel(labels);
    durations    = nan(nEv,1);
    trialType    = repmat({'n/a'}, nEv, 1);
    stimPhase    = repmat({'n/a'}, nEv, 1);
    block        = zeros(nEv,1);
    trial        = zeros(nEv,1);
    value        = labels;

    rampDurationS = 5;

    for i = 1:nEv
        mk = strtrim(labels{i});
        value{i} = mk;

        if strcmp(mk,'STIM_START') || strcmp(mk,'STIM_STOP')
            trialType{i} = 'BOUNDARY';
            stimPhase{i} = 'boundary';
            durations(i) = 0;
            continue;
        end

        parts = strsplit(mk, '_');
        cond  = parts{1};
        if ~ismember(cond, {'OFF','1HZ','5HZ'})
            continue;
        end
        trialType{i} = cond;

        switch numel(parts)
            case 3
                stimPhase{i} = 'regular';
                durations(i) = trialDurationS;
                block(i)     = str2double(parts{2});
                trial(i)     = str2double(parts{3});
            case 4
                tag = parts{2};
                switch tag
                    case 'rampingUp'
                        stimPhase{i} = 'rampingUp';
                        durations(i) = rampDurationS;
                    case 'rampingDown'
                        stimPhase{i} = 'rampingDown';
                        durations(i) = rampDurationS;
                    case 'refract'
                        stimPhase{i} = 'refract';
                        durations(i) = trialDurationS;
                    otherwise
                        stimPhase{i} = tag;
                        durations(i) = trialDurationS;
                end
                block(i) = str2double(parts{3});
                trial(i) = str2double(parts{4});
        end
    end

    eventsTable = table(onsets, durations, trialType, stimPhase, block, trial, value, ...
        'VariableNames', {'onset','duration','trial_type','stim_phase','block','trial','value'});
    eventsTable = sortrows(eventsTable, 'onset');
end

function t = emptyTable()
    t = table(double.empty(0,1), double.empty(0,1), cell(0,1), cell(0,1), ...
              double.empty(0,1), double.empty(0,1), cell(0,1), ...
              'VariableNames', {'onset','duration','trial_type','stim_phase','block','trial','value'});
end

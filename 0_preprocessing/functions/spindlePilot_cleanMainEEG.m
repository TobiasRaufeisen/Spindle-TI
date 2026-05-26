function [allData, report] = spindlePilot_cleanMainEEG(allData, opts)
% Multi-step artifact detection and filtering for main EEG
% Steps:
%   1) Downsample to 500 Hz with automatic anti-aliasing filter (FieldTrip)
%   2) Create detection copy with notch filter at line frequency
%   3) Artifact detection based on slope of noisiest channel
%      - Only within windows defined by:
%        [1s before ramping marker] -> [ramping marker to next marker] -> [1s after next marker]
%   4) Interpolate artifacts on original data, then apply Butterworth filters
%      - 0.3 Hz highpass (2nd order)
%      - 30 Hz lowpass (4th order)
%      - 50 Hz notch filter
%
% Output:
%   allData.(sub).(sess).eeg_main  cleaned data
%   report.(sub).(sess)            artifact logs and params

if nargin < 2, opts = struct; end

p = withDefaults(opts, struct( ...
  'resample_fs', 500, ...          % Target sampling frequency
  'notch_freq', 50, ...            % Line frequency for detection copy
  'notch_bw', [47.5 52.5], ...     % Notch bandwidth
  'notch_order', 4, ...            % Notch filter order
  'pad_ms', 200, ...               % Padding around artifacts (ms)
  'max_interp_ms', 2000, ...       % Max artifact length to interpolate (ms)
  'slope_threshold_mad', 15, ...   % MAD multiplier for slope threshold
  'slope_smooth_win', 11, ...      % Moving median window for slope smoothing (samples)
  'hp_freq', 0.3, ...              % Highpass cutoff (Hz)
  'hp_order', 2, ...               % Highpass filter order
  'lp_freq', 30, ...               % Lowpass cutoff (Hz)
  'lp_order', 4, ...               % Lowpass filter order
  'final_notch_freq', 50, ...      % Final notch frequency
  'final_notch_Q', 10, ...         % Final notch Q factor
  'ramp_margin_s', 1 ...           % Margin (seconds) before ramp marker and after next marker
));

subs = fieldnames(allData);
report = struct;

for isub = 1:numel(subs)
  sub = subs{isub};
  sessNames = fieldnames(allData.(sub));

  for isess = 1:numel(sessNames)
    sess = sessNames{isess};
    tag  = sprintf('%s|%s', sub, sess);

    if ~isfield(allData.(sub).(sess),'eeg_main') || isempty(allData.(sub).(sess).eeg_main)
      logMsg('skip (no eeg_main)', tag); continue
    end

    dataRaw = allData.(sub).(sess).eeg_main;
    assert(numel(dataRaw.trial)==1, 'Expect single-trial continuous data');

    fs0 = dataRaw.fsample;

    % ===== STEP 1: DOWNSAMPLE TO 500 Hz =====
    logMsg(sprintf('downsample to %d Hz (with anti-aliasing)', p.resample_fs), tag);
    cfg = [];
    cfg.resamplefs = p.resample_fs;
    cfg.demean     = 'yes';
    cfg.detrend    = 'no';
    dataDS = ft_resampledata(cfg, dataRaw);

    fs   = dataDS.fsample;
    Xraw = dataDS.trial{1};
    [nChan, nSamp] = size(Xraw);

    % ===== STEP 2: CREATE DETECTION COPY WITH NOTCH FILTER =====
    logMsg(sprintf('create detection copy with %d Hz notch', p.notch_freq), tag);
    cfg = [];
    cfg.bsfilter        = 'yes';
    cfg.bsfreq          = p.notch_bw;
    cfg.bsfiltord       = p.notch_order;
    cfg.bsfilttype      = 'but';
    cfg.bsfiltdir       = 'twopass';
    dataDet = ft_preprocessing(cfg, dataDS);

    Xdet = dataDet.trial{1};
    t    = dataDet.time{1};

    % ===== STEP 3: ARTIFACT DETECTION BASED ON SLOPE =====
    % Only within windows defined by ramping markers and their following markers
    logMsg('artifact detection based on slope (ramping+next marker windows only)', tag);

    % Find slope-noisiest channel
    dxAll    = diff(Xdet, 1, 2);
    slopeVar = var(abs(dxAll), 0, 2);
    [~, ord] = sort(slopeVar, 'descend');
    detIdx   = ord(1);
    logMsg(sprintf('detection channel (slope-noisiest): %s', dataDS.label{detIdx}), tag);

    % Parameters
    padS   = round(p.pad_ms/1000 * fs);
    maxLen = round(p.max_interp_ms/1000 * fs);
    kMAD   = p.slope_threshold_mad;
    win    = p.slope_smooth_win;
    rampMarginS = p.ramp_margin_s;

    % ===== EXTRACT WINDOWS FROM RAMPING MARKERS AND THEIR FOLLOWING MARKERS =====
    rampMask = false(1, nSamp);  % mask for regions to check for artifacts
    nRampEvents = 0;

    if isfield(allData.(sub).(sess), 'eventMarker') && ...
       ~isempty(allData.(sub).(sess).eventMarker)

        EV   = allData.(sub).(sess).eventMarker;
        EVts = EV.time_series(:);   % cellstr
        EVtt = EV.time_stamps(:)';  % row vector

        % Sort events by time to ensure "next marker" is temporal
        [EVttSorted, sortIdx] = sort(EVtt);
        EVtsSorted = EVts(sortIdx);

        % Find ramping events (rampingUp or rampingDown)
        pat = 'ramping';
        isRamp = ~cellfun('isempty', regexpi(EVtsSorted, pat));
        rampIdx = find(isRamp);
        nRampEvents = numel(rampIdx);

        logMsg(sprintf('found %d ramping events', nRampEvents), tag);

        for k = 1:nRampEvents
            thisIdx   = rampIdx(k);
            rampTime  = EVttSorted(thisIdx);

            % Determine time of the following marker (if any)
            if thisIdx < numel(EVttSorted)
                nextTime = EVttSorted(thisIdx + 1);
            else
                % If there is no following marker, fall back to rampTime + margin
                nextTime = rampTime + rampMarginS;
            end

            % Define the window:
            %   [1 s before ramping marker] -> [ramping marker to next marker] -> [1 s after next marker]
            winStartTime = rampTime  - rampMarginS;
            winEndTime   = nextTime  + rampMarginS;

            % Clamp to data time range
            winStartTime = max(winStartTime, t(1));
            winEndTime   = min(winEndTime,   t(end));

            % Convert to sample indices in downsampled data
            [~, winStart] = min(abs(t - winStartTime));
            [~, winEnd]   = min(abs(t - winEndTime));

            winStart = max(1, winStart);
            winEnd   = min(nSamp, winEnd);

            rampMask(winStart:winEnd) = true;
        end

        totalRampTime = sum(rampMask) / fs;
        logMsg(sprintf(['total artifact-search window time: %.2f s (%.1f%% of data) ' ...
                       'based on ramping+next-marker windows'], ...
               totalRampTime, 100 * sum(rampMask) / nSamp), tag);
    else
        logMsg('WARNING: no eventMarker found, skipping slope-based artifact detection', tag);
    end

    % Smoothed slope on detection channel
    x      = Xdet(detIdx, :);
    dx     = abs(diff(x));
    dx_s   = movmedian(dx, win);

    % Compute median/MAD on the full signal; only the rejection step is windowed
    mDx    = median(dx_s);
    madDx  = mad(dx_s, 1);
    thr    = mDx + kMAD * madDx;

    % Mark bad samples everywhere, then gate them to ramping/next-marker windows only
    badRaw = [dx_s > thr, false];  % align length
    bad    = badRaw & rampMask;    % restrict rejection to defined windows

    if padS > 0
      bad = conv(double(bad), ones(1, 2*padS+1), 'same') > 0;
      bad = bad & rampMask;  % keep padding within defined windows
    end

    % Contiguous segments
    d  = diff([0 bad 0]);
    s0 = find(d == 1);
    s1 = find(d == -1) - 1;

    % ===== STEP 4: INTERPOLATE ARTIFACTS AND APPLY BUTTERWORTH FILTERS =====
    logMsg('interpolating artifacts on original data', tag);
    Xc = Xraw;
    segments = struct('startSample', {}, 'endSample', {}, 'startTime', {}, 'endTime', {});

    for k = 1:numel(s0)
      a0 = s0(k); a1 = s1(k);
      len = a1 - a0 + 1;
      if len > maxLen || a0 <= 1 || a1 >= nSamp
        continue
      end
      seg = a0:a1;
      L = a0 - 1;
      R = a1 + 1;
      for ch = 1:nChan
        Xc(ch, seg) = interp1([L R], [Xc(ch, L) Xc(ch, R)], seg, 'linear');
      end
      segments(end+1).startSample = a0; %#ok<AGROW>
      segments(end).endSample     = a1;
      segments(end).startTime     = t(a0);
      segments(end).endTime       = t(a1);
    end

    dataInterp          = dataDS;
    dataInterp.trial{1} = Xc;

    totBad        = sum(bad) / fs;
    nDetected     = numel(s0);
    nInterpolated = numel(segments);
    logMsg(sprintf('detected %d segments (%d interpolated), total bad time %.2f s', ...
           nDetected, nInterpolated, totBad), tag);

    % Apply Butterworth filters
    logMsg(sprintf('applying Butterworth filters: HP %.1f Hz (order %d), LP %.0f Hz (order %d)', ...
           p.hp_freq, p.hp_order, p.lp_freq, p.lp_order), tag);

    % Design filters
    [b_hp, a_hp] = butter(p.hp_order, p.hp_freq/(fs/2), 'high');
    [b_lp, a_lp] = butter(p.lp_order, p.lp_freq/(fs/2), 'low');

    % 50 Hz notch filter
    % Inline 2nd-order IIR notch (matches MATLAB's iirnotch)
    wo = p.final_notch_freq / (fs/2);
    bw = wo / p.final_notch_Q;
    w0_rad = wo * pi;
    bw_rad = bw * pi;
    beta   = tan(bw_rad / 2);
    G      = 1 / (1 + beta);
    b_notch = G * [1, -2*cos(w0_rad), 1];
    a_notch = [1, -2*G*cos(w0_rad), (2*G - 1)];

    dataFinal = dataInterp;
    for tr = 1:numel(dataFinal.trial)
      X = double(dataFinal.trial{tr});
      for ch = 1:size(X, 1)
        X(ch, :) = filtfilt(b_hp, a_hp, X(ch, :));           % HP
        X(ch, :) = filtfilt(b_lp, a_lp, X(ch, :));           % LP
        X(ch, :) = filtfilt(b_notch, a_notch, X(ch, :));     % Notch
      end
      dataFinal.trial{tr} = X;
    end

    logMsg(sprintf('final filtering done: HP %.1f Hz, LP %.0f Hz, %d Hz notch', ...
           p.hp_freq, p.lp_freq, p.final_notch_freq), tag);

    % Save report
    rep = struct;
    rep.fs_original     = fs0;
    rep.fs_resampled    = fs;
    rep.artifacts       = segments;
    rep.n_detected      = nDetected;
    rep.n_interpolated  = nInterpolated;
    rep.total_bad_s     = totBad;
    rep.slope_median    = mDx;
    rep.slope_mad       = madDx;
    rep.slope_threshold = thr;
    rep.detection_ch    = dataDS.label{detIdx};
    rep.n_ramp_events   = nRampEvents;
    rep.ramp_window_s   = sum(rampMask) / fs;
    rep.params          = p;

    % Attach artifact information
    nInterpolated = numel(segments);
    if nInterpolated > 0
      artfctdef = zeros(nInterpolated, 2);
      for k = 1:nInterpolated
        artfctdef(k, :) = [segments(k).startSample, segments(k).endSample];
      end
      dataFinal.cfg.artfctdef = struct;
      dataFinal.cfg.artfctdef.general = struct('artifact', artfctdef);
    end

    % Save
    allData.(sub).(sess).eeg_main = dataFinal;
    report.(sub).(sess) = rep;

    logMsg('done', tag);
  end
end
end

% ================= helpers =================
function out = withDefaults(in, def)
out = def;
if nargin<1 || isempty(in), return; end
f = fieldnames(in);
for i=1:numel(f), out.(f{i}) = in.(f{i}); end
end

function s = ts(), s = datestr(now,'yyyy-mm-dd HH:MM:SS'); end
function logMsg(msg, tag), fprintf('[%s] %s :: %s\n', ts(), tag, msg); end

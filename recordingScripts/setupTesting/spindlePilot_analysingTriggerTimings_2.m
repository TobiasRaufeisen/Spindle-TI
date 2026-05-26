%% 1. Load Data, Correct EEG Timestamps, and Align Streams
data = load_xdf('D:\data\SpindlePilot\sub-P999\ses-S020\eeg\sub-P999_ses-S020_task-Default_run-001_eeg.xdf');

% 191: DAQ output trigger start
% 127 TI output trigger start
% 63: DAQ and TI output trigger stop

daq      = data{4};                               % NI-DAQ stream handle
nSamples = size(daq.time_series, 2);              % columns = samples

t0 = str2double(daq.info.first_timestamp);        %   both are *strings*
t1 = str2double(daq.info.last_timestamp);         %   → convert to double

fs_eff      = (nSamples-1) / (t1 - t0);           % effective sample-rate
fprintf('DAQ effective rate : %.3f Hz (nominal 50 000 Hz)\n', fs_eff);

daq.time_stamps = t0 + (0:nSamples-1) / fs_eff;   % **replace** by new vector

% keep the updated stream
data{4} = daq;

t0_global = min( cellfun(@(s)s.time_stamps(1), data) );
for s = 1:numel(data)
    data{s}.time_stamps = data{s}.time_stamps - t0_global;
end

%% --- grab the marker channel & matching time-vector ---------------------
markerChan = double(data{4}.time_series(2 ,:));  % 2nd channel = marker stream
t          = data{4}.time_stamps;                % same length as markerChan

% --- detect ONSETS (first sample of each burst) ------------------------
is191      = markerChan == 191;
is127      = markerChan == 127;

idx191     = find([false diff(is191)] == 1);     % onset indices for 191
idx127     = find([false diff(is127)] == 1);     % onset indices for 127

t191       = t(idx191);                          % onset times (sec)
t127       = t(idx127);

% --- compute delays -----------------------------------------------------
n191               = numel(t191);
delayNext127       = nan(n191,1);
delayPrev127       = nan(n191,1);

for k = 1:n191
    nxt = find(t127 > t191(k), 1, 'first');      % first 127 *after* this 191
    prv = find(t127 < t191(k), 1, 'last');       % last 127 *before* this 191
    
    if ~isempty(nxt)
        delayNext127(k) =  t127(nxt) - t191(k);  % (sec)
    end
    if ~isempty(prv)
        delayPrev127(k) =  t191(k) - t127(prv);  % (sec)
    end
end

% --- grab the LSL markers (already in seconds) ----------
LSL_start_markers = data{2}.time_stamps;

% --- compute delays -----------------------------------------------------
n191               = numel(t191);
delayNext127       = nan(n191,1);
delayPrev127       = nan(n191,1);
delayFromPrevLSL   = nan(n191,1);

for k = 1:n191
    % ----- 127 ↔ 191 gaps -----
    nxt = find(t127 > t191(k), 1, 'first');      % first 127 *after* this 191
    prv = find(t127 < t191(k), 1, 'last');       % last 127 *before* this 191
    if ~isempty(nxt),  delayNext127(k) = t127(nxt) - t191(k); end
    if ~isempty(prv),  delayPrev127(k) = t191(k) - t127(prv); end

    % ----- 191 ↔ last DEFAULT_START gap -----
    lsl = find(LSL_start_markers < t191(k), 1, 'last');  % most-recent START
    if ~isempty(lsl)
        delayFromPrevLSL(k) = t191(k) - LSL_start_markers(lsl);
    end
end

% --- build summary table & drop edge-cases ------------------------------
tbl = table( (1:n191).', delayNext127, delayPrev127, delayFromPrevLSL, ...
             'VariableNames', {'Marker191_Number',        ...
                               'Delay_to_next_127',       ...
                               'Delay_from_prev_127',     ...
                               'Delay_from_prev_LSL'});

tbl = tbl(~any(isnan(tbl{:,:}),2), :);   % keep only fully-defined rows

%%  Analysis
tbl.Delay_to_next_127_ms     = tbl.Delay_to_next_127     * 1e3;
tbl.Delay_from_prev_127_ms   = tbl.Delay_from_prev_127   * 1e3;
tbl.Delay_from_prev_LSL_ms   = tbl.Delay_from_prev_LSL   * 1e3;

%  -------- descriptive stats -------------------------------------------
mu_next   = mean(tbl.Delay_to_next_127_ms);
sd_next   =  std(tbl.Delay_to_next_127_ms);

mu_LSL    = mean(tbl.Delay_from_prev_LSL_ms);
sd_LSL    =  std(tbl.Delay_from_prev_LSL_ms);

fprintf('\nDescriptives (n = %d)\n',height(tbl));
fprintf(' 191 → next 127 :  %.3f ± %.3f ms (mean ± SD)\n',mu_next,sd_next);
fprintf(' prev LSL → 191 :  %.3f ± %.3f ms\n',mu_LSL ,sd_LSL );

%  -------- histograms ---------------------------------------------------
figure('Name','Delay histograms (ms)','Color','w');

subplot(1,2,1)
histogram(tbl.Delay_to_next_127_ms,'BinMethod','auto');
xlabel('Delay to NEXT 127  (ms)');
ylabel('Count');
title(sprintf('191 → 127 | μ=%.2f  σ=%.2f',mu_next,sd_next));

subplot(1,2,2)
histogram(tbl.Delay_from_prev_LSL_ms,'BinMethod','auto');
xlabel('Delay from PREV LSL  (ms)');
ylabel('Count');
title(sprintf('LSL → 191 | μ=%.2f  σ=%.2f',mu_LSL,sd_LSL));

%  -------- regression over time ----------------------------------------
validRows   = ~any(isnan(tbl{:,2:4}/1e3),2);   % same logic as before
t191_clean  = t191(validRows);                 % x-axis (s)

figure('Name','Delay development over time','Color','w');

% (a) 191 → 127
subplot(2,1,1)
scatter(t191_clean, tbl.Delay_to_next_127_ms, 14, 'filled'); hold on
p1 = polyfit(t191_clean, tbl.Delay_to_next_127_ms, 1);
plot(t191_clean, polyval(p1,t191_clean),'LineWidth',1.5);
slope1 = p1(1);                                % ms per second
xlabel('191-marker onset time  (s)');
ylabel('Delay to NEXT 127  (ms)');
title(sprintf('Trend 191→127   slope = %.4f ms/s',slope1));
grid on

% (b) LSL → 191
subplot(2,1,2)
scatter(t191_clean, tbl.Delay_from_prev_LSL_ms, 14, 'filled'); hold on
p2 = polyfit(t191_clean, tbl.Delay_from_prev_LSL_ms, 1);
plot(t191_clean, polyval(p2,t191_clean),'LineWidth',1.5);
slope2 = p2(1);
xlabel('191-marker onset time  (s)');
ylabel('Delay from PREV LSL  (ms)');
title(sprintf('Trend LSL→191   slope = %.4f ms/s',slope2));
grid on

%  -------- correlation between 127-delays -------------------------------
[dR, pCorr] = corr(tbl.Delay_to_next_127_ms, ...
                   tbl.Delay_from_prev_127_ms, ...
                   'rows','complete');

figure('Name','Correlation between 127-delays','Color','w');
scatter(tbl.Delay_from_prev_127_ms, tbl.Delay_to_next_127_ms, ...
        18,'filled'); grid on; hold on
lsline
xlabel('Delay FROM previous 127  (ms)');
ylabel('Delay TO next 127  (ms)');
title(sprintf('Correlation r = %.3f  (p = %.3g)', dR, pCorr));

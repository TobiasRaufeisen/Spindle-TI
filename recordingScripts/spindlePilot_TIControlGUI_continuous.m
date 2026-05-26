ConditionStimController('SpindleControlStream', 'D:\matlab\projects\SpindlePilot\conditions')

function ConditionStimController(streamID, condFolder)
% ConditionStimController – step-through stim controller driven by
% participant CSV files (conditions_###.csv).
%
% OFF-block marker / pulse rules (2025-05-16 final)
% ─────────────────────────────────────────────────────────────────
% • First OFF after a non-OFF
%       OFF_rampingDown_<sfx>   (marker + pulse)
%       OFF_<sfx>               (marker + pulse)
%       OFF_refract_<sfx>       (marker, NO pulse)
% • Subsequent consecutive OFFs
%       OFF_<sfx>               (marker, NO pulse)
%       OFF_refract_<sfx>       (marker, NO pulse)
% • End of OFF block
%       OFF_rampingUp_<lastSfx> (marker + pulse)
%
% • All non-OFF conditions: <COND>_<sfx>  &  <COND>_refract_<sfx>
%   (both marker + pulse).
% • <sfx> is <row>_<occurrence> (three-digit zero-pad).

% ---------- defaults ----------------------------------------------------
if nargin < 1, streamID = 'StimControlMarkers'; end
if nargin < 2 || isempty(condFolder)
    condFolder = fullfile( ...
        'C:','Users','tr00662','OneDrive - University of Surrey', ...
        'Desktop','Uni files, grants, papers','spindlePilot','conditions');
end

% ---------- 1.  LSL ------------------------------------------------------
lib    = lsl_loadlib();
outlet = lsl_outlet(lsl_streaminfo(lib,'StimMarkers','Markers',1,0, ...
                                   'cf_string',streamID));

% ---------- 2.  NI-DAQ ---------------------------------------------------
daqOK = true;
try
    daqSession = daq.createSession('ni');
    daqSession.addDigitalChannel('Dev1','port1/line0:1','OutputOnly');
catch ME
    warning('NIDAQ unavailable: %s – continuing without DAQ.',ME.message);
    daqOK = false;
end

% ---------- 3.  GUI (unchanged) -----------------------------------------
f = figure('Name','Condition-stim Controller','MenuBar','none', ...
           'ToolBar','none','Resize','off','NumberTitle','off', ...
           'Position',[500 300 500 430], ...
           'CloseRequestFcn',@(~,~)closeGUI);

uicontrol(f,'Style','text','String','Subject #', ...
          'Position',[30 375 70 20],'HorizontalAlignment','left');
subjEdit = uicontrol(f,'Style','edit','String','', ...
          'Position',[110 375 60 25],'BackgroundColor','w');
uicontrol(f,'Style','pushbutton','String','LOAD', ...
          'Position',[190 375 80 25],'Callback',@loadConditions);

fileLabel = uicontrol(f,'Style','text','String','No file loaded', ...
          'Position',[30 345 440 20],'HorizontalAlignment','left');

uicontrol(f,'Style','text','String','STIM DURATION (s)', ...
          'Position',[30 305 130 20],'HorizontalAlignment','left');
stimEdit = uicontrol(f,'Style','edit','String','10', ...
          'Position',[180 305 60 25],'BackgroundColor','w');

uicontrol(f,'Style','text','String','RAMP DURATION (s)', ...
          'Position',[30 275 130 20],'HorizontalAlignment','left');
rampEdit = uicontrol(f,'Style','edit','String','5', ...
          'Position',[180 275 60 25],'BackgroundColor','w');

uicontrol(f,'Style','text','String','PAUSE DURATION (s)', ...
          'Position',[30 245 130 20],'HorizontalAlignment','left');
pauseEdit = uicontrol(f,'Style','edit','String','5', ...
          'Position',[180 245 60 25],'BackgroundColor','w');

startBtn = uicontrol(f,'Style','pushbutton','String','START', ...
          'Position',[30 195 150 45],'FontSize',11,'Callback',@startRun);
stopBtn  = uicontrol(f,'Style','pushbutton','String','STOP', ...
          'Position',[190 195 150 45],'FontSize',11,'Callback',@stopRun, ...
          'Enable','off');
uicontrol(f,'Style','pushbutton','String','SEND MANUAL TRIGGER', ...
          'Position',[350 195 120 45],'FontSize',9, ...
          'Callback',@manualPulse);

currentLabel = uicontrol(f,'Style','text','String','', ...
          'Position',[30 140 440 20],'FontWeight','bold', ...
          'HorizontalAlignment','left');
timerLabel   = uicontrol(f,'Style','text','String','Timer: --', ...
          'Position',[30 110 440 20],'HorizontalAlignment','left');

% ---------- 4.  Runtime vars --------------------------------------------
condList        = {};  rowLookup = [];
subjectStr      = '';  condIndex = 0;

prevCondWasOff  = false; prevOffSuffix = '';
stopFlag        = false;

logFid          = -1;
condOccurrences = struct();

% ---------- helper: is the log file open? -------------------------------
    function tf = logIsOpen()
        tf = logFid > 2 && ~isempty(fopen(logFid));
    end

% ---------- 5.  Callbacks -----------------------------------------------
    function loadConditions(~,~)
        idNum = str2double(subjEdit.String);
        if isnan(idNum) || idNum < 0
            errordlg('Enter a valid numeric subject ID.','Input Error'); return;
        end
        subjectStr = sprintf('%03d',idNum);
        fname = fullfile(condFolder,sprintf('conditions_%s.CSV',subjectStr));
        if ~isfile(fname)
            errordlg(['File not found: ' fname],'Load Error'); return;
        end

        T = readtable(fname,'PreserveVariableNames',true,'TextType','string');

        condList  = {}; rowLookup = [];
        for r = 1:height(T)
            for c = 2:width(T)
                entry = strtrim(T{r,c});
                if entry ~= ""
                    condList{end+1,1} = upper(entry); %#ok<AGROW>
                    rowLookup(end+1,1) = r;           %#ok<AGROW>
                end
            end
        end
        condIndex = 1; prevCondWasOff=false; prevOffSuffix='';
        condOccurrences = struct();

        fileLabel.String   = ['Loaded: ' fname];
        currentLabel.String= 'Ready (press START)';
        disp(['Loaded ' num2str(numel(condList)) ' condition entries.']);
    end

    function startRun(~,~)
        if isempty(condList)
            errordlg('Load a condition file first.','No Conditions'); return; end
        stimDur  = validateNumeric(stimEdit ,'stim duration');  if isempty(stimDur),  return; end
        rampDur  = validateNumeric(rampEdit ,'ramp duration');  if isempty(rampDur),  return; end
        pauseDur = validateNumeric(pauseEdit,'pause duration'); if isempty(pauseDur), return; end

        condOccurrences = struct();
        try
            logName = fullfile(condFolder, ...
                sprintf('stimlog_%s_%s.txt',subjectStr,datestr(now,'yyyymmdd_HHMMSS')));
            logFid  = fopen(logName,'w');
            fprintf(logFid,'%% time\t\ttype\tcode\n');
        catch, logFid = -1; end

        startBtn.Enable='off'; stopBtn.Enable='on'; subjEdit.Enable='off';
        stopFlag = false;

        sendMarker('STIM_START','START');
        currentLabel.String='Initial wait (10 s before first condition)';
        runPhase(10,'','');

        condIndex = 1;
        while ~stopFlag && condIndex <= numel(condList)
            runCurrentCondition();
            condIndex = condIndex + 1;
        end

        sendMarker('STIM_STOP','');
        currentLabel.String='Stopped.'; timerLabel.String='Timer: --';
        startBtn.Enable='on'; stopBtn.Enable='off'; subjEdit.Enable='on';

        if logIsOpen(), fclose(logFid); end
    end

    function stopRun(~,~), stopFlag = true; end

    function manualPulse(~,~)
        if ~daqOK, warndlg('DAQ not available.','DAQ'); return; end
        pulse('MANUAL'); logEntry('DAQ','MANUAL');
    end

% ----------------------- phase helpers ----------------------------------
    function runCurrentCondition()
        stimDur  = validateNumeric(stimEdit ,'stim duration');  if isempty(stimDur),  stopFlag=true; return; end
        rampDur  = validateNumeric(rampEdit ,'ramp duration');  if isempty(rampDur),  stopFlag=true; return; end
        pauseDur = validateNumeric(pauseEdit,'pause duration'); if isempty(pauseDur), stopFlag=true; return; end

        cond = char(condList{condIndex});
        row  = rowLookup(condIndex);

        % occurrence counter per row
        rowField = sprintf('row%d',row);
        if ~isfield(condOccurrences,rowField)
            condOccurrences.(rowField) = containers.Map('KeyType','char','ValueType','double');
        end
        rowMap = condOccurrences.(rowField);
        if ~isKey(rowMap,cond)
            rowMap(cond) = 1; else, rowMap(cond) = rowMap(cond)+1; end
        occurrence = rowMap(cond);
        condOccurrences.(rowField) = rowMap;

        suffix = sprintf('%03d_%03d',row,occurrence);
        nextIsOff = condIndex < numel(condList) && strcmpi(condList{condIndex+1},'OFF');

        % ramp-up if leaving an OFF block
        if prevCondWasOff && ~strcmpi(cond,'OFF')
            runPhase(rampDur,['OFF_rampingUp_' prevOffSuffix],'OFF_rampingUp');
        end

        % ---------------- OFF condition ---------------------------------
        if strcmpi(cond,'OFF')
            % ramp-down only for first OFF
            if ~prevCondWasOff
                runPhase(rampDur,['OFF_rampingDown_' suffix],'OFF_rampingDown');
            end

            % OFF stimulation marker (pulse only for first OFF)
            stimPulse = ''; if ~prevCondWasOff, stimPulse = 'OFF_cond'; end
            runPhase(stimDur,['OFF_' suffix], stimPulse);

            % OFF_refract marker – NO pulse ever
            runPhase(pauseDur,['OFF_refract_' suffix], '');

            % remember suffix of last OFF (for ramp-up)
            if ~nextIsOff, prevOffSuffix = suffix; end
            prevCondWasOff = true;
            return
        end

        % ---------------- non-OFF condition -----------------------------
        runPhase(stimDur , [cond '_'        suffix], cond);   % marker + pulse
        runPhase(pauseDur,[cond '_refract_' suffix],'PAUSE');
        prevCondWasOff = false;
    end

    function runPhase(dur,marker,daqTag)
        if stopFlag, return; end
        if ~isempty(marker)
            sendMarker(marker,daqTag);
            currentLabel.String = ['Now running: ' marker];
        else
            currentLabel.String = 'Pause …';
        end
        t0 = tic;
        while toc(t0) < dur
            if stopFlag, return; end
            timerLabel.String = ['Timer: ' num2str(ceil(dur - toc(t0))) ' s'];
            drawnow; pause(0.25);
        end
    end

% -------------------------- utilities -----------------------------------
    function n = validateNumeric(ctl,label)
        n = str2double(ctl.String);
        if isnan(n) || n <= 0
            errordlg(['Enter positive ' label ' (s).'],'Input Error'); n = [];
        end
    end

    function sendMarker(marker,daqTag)
        outlet.push_sample({marker});
        disp(['Marker: ' marker]);
        logEntry('LSL',marker);
        if daqOK && ~isempty(daqTag), pulse(daqTag); end
    end

    function pulse(tag)
        try
            daqSession.outputSingleScan([1 0]); pause(0.001);
            daqSession.outputSingleScan([0 0]);
            disp(['DAQ pulse fired (' tag ')']);
            logEntry('DAQ',tag);
        catch err
            warning('DAQ error: %s',err.message);
        end
    end

    function logEntry(type,code)
        if logIsOpen()
            fprintf(logFid,'%s\t%s\t%s\n', ...
                datestr(now,'yyyy-mm-dd HH:MM:SS.FFF'), type, code);
            if exist('fflush','builtin') || exist('fflush','file'), fflush(logFid); end
        end
    end

    function closeGUI
        stopFlag = true;
        if logIsOpen(), fclose(logFid); end
        if daqOK, try, daqSession.release(); catch, end, end
        delete(f);
    end
end

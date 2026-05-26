StimulationController({'HF_CONTROL','SPINDLE_6HZ','SPINDLE_13HZ','OFF'}, 'StimControlMarkers')

function StimulationController(conditions, streamID)
% StimulationController – GUI for sending LSL markers & NI-DAQ pulses
%
%   • Four-marker sequence
%         BASELINE_START          (no DAQ)
%         <COND>_START            (optional DAQ pulse)
%         <COND>_POST_START       (optional DAQ pulse)
%         <COND>_POST_END         (optional DAQ pulse)
%   • Manual END marker (no DAQ pulse)
%   • Three DAQ-option check-boxes:
%         START  •  POST-START  •  POST-END
%   • No STOP / FINISH logic, no END-DAQ trigger
%
%   Example:
%     StimulationController({'HF_CONTROL','SPINDLE_6HZ','SPINDLE_13HZ','OFF'}, ...
%                           'StimControlMarkers')

%% -------- 0  Inputs -----------------------------------------------------
if nargin < 1 || isempty(conditions)
    conditions = {'HF_CONTROL','SPINDLE_7HZ','SPINDLE_14HZ','130Hz'};
end
if nargin < 2 || isempty(streamID)
    streamID = char(java.util.UUID.randomUUID);
end
nCond = numel(conditions);

%% -------- 1  LSL --------------------------------------------------------
lib  = lsl_loadlib();
info = lsl_streaminfo(lib,'StimMarkers','Markers',1,0,'cf_string',streamID);
outlet = lsl_outlet(info);

%% -------- 2  NI-DAQ (optional) -----------------------------------------
daqOK = true;
try
    daqSession = daq.createSession('ni');
    daqSession.addDigitalChannel('Dev1','port1/line0:1','OutputOnly');
catch ME
    warning('NIDAQ unavailable: %s – continuing without DAQ.',ME.message);
    daqOK = false;
end

%% -------- 3  State vars -------------------------------------------------
currCond     = '';
seqStage     = 0;            % 0 idle • 1 baseline • 2 stim • 3 post • 4 done
seqDur       = [2 3 25];     % default seconds
seqElapsed   = 0;
seqTimer     = [];           % single timer handle

%% -------- 4  GUI --------------------------------------------------------
f = figure('Name','TI Stimulation Controller', ...
           'MenuBar','none','ToolBar','none','NumberTitle','off', ...
           'Resize','on','Position',[350 200 720 650], ...
           'CloseRequestFcn',@(~,~)closeGUI);

% 4-A  Condition buttons
uicontrol(f,'Style','text','String','Select Condition:', ...
          'Units','normalized','Position',[0.05 0.92 0.9 0.04], ...
          'FontSize',12,'HorizontalAlignment','center');

bg = uibuttongroup(f,'Units','normalized', ...
                   'Position',[0.05 0.85 0.9 0.06], ...
                   'BorderType','none','SelectionChangedFcn',@condChosen);
btnW = min(0.18,0.9/nCond);
for i = 1:nCond
    uicontrol(bg,'Style','radiobutton','String',conditions{i}, ...
        'Units','normalized', ...
        'Position',[0.05+(i-1)*(btnW+0.01) 0.1 btnW 0.8],'FontSize',10);
end

% 4-B  DAQ options (three boxes)
daqPanel = uipanel(f,'Title','DAQ pulses','Units','normalized', ...
                   'Position',[0.05 0.75 0.9 0.08]);
daqStartBox     = makeChk(daqPanel,0.05,'START DAQ Trigger',       1,0.25);
daqPostStartBox = makeChk(daqPanel,0.35,'POST-START DAQ Trigger',  1,0.25);
daqPostEndBox   = makeChk(daqPanel,0.65,'POST-END DAQ Trigger',    1,0.25);

% 4-C  Duration edits
durP = uipanel(f,'Title','Durations (s)','Units','normalized', ...
               'Position',[0.05 0.62 0.9 0.11]);
baseEdit = makeEdit(durP,'Baseline', 0.05,'2');
stimEdit = makeEdit(durP,'Stim',     0.38,'3');
postEdit = makeEdit(durP,'Post',     0.68,'25');

% 4-D  Action buttons
btnP = uipanel(f,'Title','Actions','Units','normalized', ...
               'Position',[0.05 0.46 0.9 0.15]);
uicontrol(btnP,'Style','pushbutton','String','Send START Marker', ...
    'Units','normalized','Position',[0.03 0.55 0.28 0.35], ...
    'FontSize',10,'Callback',@startSequence);
uicontrol(btnP,'Style','pushbutton','String','Send END Marker', ...
    'Units','normalized','Position',[0.35 0.55 0.28 0.35], ...
    'FontSize',10,'Callback',@sendEnd);
uicontrol(btnP,'Style','pushbutton','String','Send Manual DAQ Pulse', ...
    'Units','normalized','Position',[0.03 0.10 0.28 0.35], ...
    'FontSize',10,'Callback',@manualPulse);

% 4-E  Live timer
dispP = uipanel(f,'Title','Sequence Timer','Units','normalized', ...
                'Position',[0.05 0.08 0.9 0.34]);
uicontrol(dispP,'Style','text','String','Countdown (↓)', ...
          'Units','normalized','Position',[0.15 0.8 0.35 0.15], ...
          'FontSize',10,'FontWeight','bold','HorizontalAlignment','center');
uicontrol(dispP,'Style','text','String','Count Up (↑)', ...
          'Units','normalized','Position',[0.55 0.8 0.35 0.15], ...
          'FontSize',10,'FontWeight','bold','HorizontalAlignment','center');

uicontrol(dispP,'Style','text','String','SEQ', ...
          'Units','normalized','Position',[0.02 0.45 0.1 0.2], ...
          'FontSize',10,'FontWeight','bold','HorizontalAlignment','left');
cdText = uicontrol(dispP,'Style','text','String','--:--', ...
          'Units','normalized','Position',[0.15 0.45 0.35 0.2], ...
          'FontSize',18,'FontWeight','bold','HorizontalAlignment','center');
cuText = uicontrol(dispP,'Style','text','String','--:--', ...
          'Units','normalized','Position',[0.55 0.45 0.35 0.2], ...
          'FontSize',18,'ForegroundColor','b','HorizontalAlignment','center');

%% -------- 5  Callbacks --------------------------------------------------
    function condChosen(~,e)
        currCond = e.NewValue.String;
        disp(['Condition selected: ' currCond]);
    end

    % --- BEGIN SEQUENCE --------------------------------------------------
    function startSequence(~,~)
        if isempty(currCond)
            errordlg('Select a condition first!','Error'); return; end

        % stop any existing timer cleanly
        killSeqTimer();

        seqStage   = 1;  seqElapsed = 0;
        seqDur(1)  = readEdit(baseEdit,2);
        seqDur(2)  = readEdit(stimEdit,3);
        seqDur(3)  = readEdit(postEdit,25);

        outlet.push_sample({'BASELINE_START'});
        disp('Marker: BASELINE_START');

        updateDisp(seqDur(1),0);

        seqTimer = timer('ExecutionMode','fixedRate','Period',1, ...
                         'TimerFcn',@tickSeq);
        start(seqTimer);
    end

    % --- MANUAL END ------------------------------------------------------
    function sendEnd(~,~)
        if isempty(currCond)
            errordlg('Select a condition first!','Error'); return; end
        killSeqTimer();

        m = [currCond '_END'];
        outlet.push_sample({m});  disp(['Marker: ' m]);
        % no DAQ pulse for END any more
    end

    % --- MANUAL DAQ PULSE ------------------------------------------------
    function manualPulse(~,~)
        if ~daqOK
            warndlg('DAQ not available','DAQ'); return;
        end
        pulse('MANUAL');
    end

    % --- SEQUENCE TICK ---------------------------------------------------
    function tickSeq(~,~)
        seqElapsed = seqElapsed + 1;
        remain = seqDur(seqStage) - seqElapsed;
        updateDisp(max(remain,0),seqElapsed);

        if remain <= 0
            switch seqStage
                case 1      % baseline → stim
                    markerAndPulse([currCond '_START'],daqStartBox,'START');
                    seqStage = 2; seqElapsed = 0;
                case 2      % stim → post-start
                    markerAndPulse([currCond '_POST_START'], ...
                                   daqPostStartBox,'POST_START');
                    seqStage = 3; seqElapsed = 0;
                case 3      % post → post-end, finish
                    markerAndPulse([currCond '_POST_END'], ...
                                   daqPostEndBox,'POST_END');
                    killSeqTimer();
            end
        end
    end

%% -------- 6  Utility ----------------------------------------------------
    function markerAndPulse(marker,box,label)
        outlet.push_sample({marker});
        disp(['Marker: ' marker]);
        if daqOK && box.Value
            pulse(label);
        end
    end

    function pulse(tag)
        try
            daqSession.outputSingleScan([1 0]); pause(0.01);
            daqSession.outputSingleScan([0 0]);
            disp(['DAQ pulse fired (' tag ')']);
        catch err
            warning('DAQ error: %s',err.message);
        end
    end

    function killSeqTimer()
        if ~isempty(seqTimer)
            try, stop(seqTimer); delete(seqTimer); end
            seqTimer = [];
        end
        seqStage = 0;  cdText.String='--:--'; cuText.String='--:--';
    end

    function v = readEdit(h,dflt)
        v = str2double(h.String);
        if isnan(v) || v<=0, v=dflt; h.String=num2str(dflt); end
    end

    function updateDisp(down,up)
        cdText.String = sprintf('%02d:%02d',floor(down/60),mod(down,60));
        cuText.String = sprintf('%02d:%02d',floor(up/60),mod(up,60));
    end

    function h = makeChk(parent,x,txt,def,wid)
        if nargin<5, wid=0.25; end
        h = uicontrol(parent,'Style','checkbox','String',txt,'Value',def, ...
              'Units','normalized','Position',[x 0.15 wid 0.7],'FontSize',10);
    end

    function h = makeEdit(parent,label,x,str0)
        uicontrol(parent,'Style','text','String',[label ':'], ...
             'Units','normalized','Position',[x 0.55 0.15 0.35], ...
             'HorizontalAlignment','left','FontSize',10);
        h = uicontrol(parent,'Style','edit','String',str0, ...
             'Units','normalized','Position',[x+0.17 0.6 0.12 0.3], ...
             'FontSize',10);
    end

%% -------- 7  Clean exit -------------------------------------------------
    function closeGUI
        killSeqTimer();
        if daqOK
            try, daqSession.release(); catch, end
        end
        delete(f);
    end
end

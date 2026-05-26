%%% COUNTERBALANCED ORDER GENERATOR  (one CSV file per participant)
%  – “conditions”  : every condition repeated condRepetitions times
%  – “conditionsTI”: OFF collapsed to a single instance per row
%                    ► row length = ((nCond-1)*condRepetitions)+1
% -------------------------------------------------------------------------
% PARAMETERS ---------------------------------------------------------------
nCond            = 3;          % number of distinct conditions
nPart            = 50;         % participants → number of CSV files
nRep             = 25;         % rows per CSV (blocks per participant)
condRepetitions  = 5;          % consecutive repeats of the same condition
seed             = 173494;     % RNG seed

condNames = {                  % leave {} for auto C1, C2, …
    '1HZ', ...
    '5HZ', ...
    'OFF' ...
};

% Where to save ↓↓↓
outDir    = 'D:\matlab\projects\SpindlePilot\conditions';
outDirTI  = 'D:\matlab\projects\SpindlePilot\conditionsTI';
% -------------------------------------------------------------------------

%% ---------------- set-up -------------------------------------------------
if ~exist(outDir,   'dir'); mkdir(outDir);   end
if ~exist(outDirTI, 'dir'); mkdir(outDirTI); end

assert(condRepetitions==fix(condRepetitions)&&condRepetitions>0, ...
       'condRepetitions must be a positive integer.');

if numel(condNames) ~= nCond
    error('condNames must contain exactly nCond entries.');
end
condNames = string(condNames);

nPosFull   = nCond * condRepetitions;              % 15 columns in “conditions”
nPosSlim   = (nCond-1)*condRepetitions + 1;        % 11 columns in “conditionsTI”
hdrFull    = "Condition" + (1:nPosFull);           % Condition1 … Condition15
hdrSlim    = "Condition" + (1:nPosSlim);           % Condition1 … Condition11
padWidth   = max(3, floor(log10(nPart)) + 1);      % filename zero-padding
codeOFF    = find(condNames == "OFF", 1);          % numeric index of OFF

%% ---------------- generate orders ---------------------------------------
ordersAll = counterbalancedOrders( ...
    nCond, nPart, nRep, condRepetitions, seed);    % [nPart × 15*50]

%% ---------------- export -------------------------------------------------
for p = 1:nPart
    %% --- reshape & translate to text ------------------------------------
    seqMat = reshape(ordersAll(p, :), nPosFull, nRep).'; % 50 × 15
    seqTxt = condNames(seqMat);

    %% --- TABLE: “conditions”  (full length) -----------------------------
    T = table((1:nRep).', 'VariableNames', {'Number'});
    for c = 1:nPosFull;  T.(hdrFull(c)) = seqTxt(:, c);  end

    %% --- TABLE: “conditionsTI” (OFF collapsed) --------------------------
    slimTxt = strings(nRep, nPosSlim);                   % 50 × 11
    for r = 1:nRep
        fullRow = seqMat(r, :);            % numeric codes, length 15
        outPtr  = 1;                       % next write position
        wasOff  = false;

        for k = 1:nPosFull
            cond = fullRow(k);
            if cond == codeOFF
                if ~wasOff                      % write the *first* OFF only
                    slimTxt(r, outPtr) = condNames(cond);
                    outPtr = outPtr + 1;
                    wasOff = true;
                end
            else                                % non-OFF condition
                slimTxt(r, outPtr) = condNames(cond);
                outPtr = outPtr + 1;
                wasOff = false;
            end

            if outPtr > nPosSlim               % row filled – stop early
                break;
            end
        end
    end

    Tslim = table((1:nRep).', 'VariableNames', {'Number'});
    for c = 1:nPosSlim;  Tslim.(hdrSlim(c)) = slimTxt(:, c);  end

    %% --- write both CSVs -------------------------------------------------
    fname = sprintf('conditions_%0*d.csv', padWidth, p);
    writetable(T,     fullfile(outDir,   fname), 'WriteVariableNames', true);
    writetable(Tslim, fullfile(outDirTI, fname), 'WriteVariableNames', true);

    fprintf('Saved  %s\n        %s (thin-OFF)\n', ...
            fullfile(outDir, fname), fullfile(outDirTI, fname));
end

%% --------------- helper -------------------------------------------------
function orders = counterbalancedOrders( ...
        nCond, nPart, nRep, condRepetitions, seed)
    % Balanced, randomised orders with guaranteed
    % non-identical successive rows per participant.

    if nargin<5 || isempty(seed); rng('shuffle'); else; rng(seed); end

    % --- Latin / Williams square ----------------------------------------
    L = zeros(nCond, nCond);
    if mod(nCond,2)==0                              % Williams (even nCond)
        for r = 0:nCond-1
            for c = 0:nCond-1
                L(r+1,c+1) = mod(r + ( (-1)^c * floor(c/2) ), nCond) + 1;
            end
        end
    else                                            % standard Latin square
        for r = 0:nCond-1;  L(r+1,:) = mod(r + (0:nCond-1), nCond) + 1; end
    end

    base = L(mod(0:nPart-1, nCond)+1, :);           % assign rows to participants
    blkLen = nCond*condRepetitions;
    orders = zeros(nPart, blkLen*nRep);

    for p = 1:nPart
        prev = [];
        for rep = 1:nRep
            order = base(p, randperm(nCond));
            while rep>1 && isequal(order, prev); order = base(p, randperm(nCond)); end
            prev = order;

            orders(p, (rep-1)*blkLen + (1:blkLen)) = repelem(order, condRepetitions);
        end
    end
    orders = orders(randperm(nPart), :);            % shuffle participants
end

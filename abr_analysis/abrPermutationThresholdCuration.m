function [curation, state] = abrPermutationThresholdCuration(rowVals, thresh_hat, permResult, mdls, options)
% abrPermutationThresholdCuration  Interactive/manual curation of thresholds from abrPermutationThreshold.
%
%   [curation, state] = abrPermutationThresholdCuration(rowVals, thresh_hat, permResult, mdls)
%   [curation, state] = abrPermutationThresholdCuration(rowVals, thresh_hat, permResult, mdls, options)
%
% Purpose
%   Interactive UI to manually review and curate per-column thresholds produced by
%   abrPermutationThreshold, with:
%     (i)  Jump-to-column dialog
%     (ii) Automatic flagging of suspicious columns
%     (iii) Waveform summary (mean±SEM) from original S, if provided
%
% Important rendering note
%   This version avoids creating overlay axes (which break in tiledlayout).
%   It uses yyaxis on the existing detection axis for -log10(p) instead.
%
% Inputs
%   rowVals     [nRows x 1] double. Typically stimulus level (dB SPL) but can be any ordered axis.
%   thresh_hat  [1 x nCols] double. Automatic thresholds.
%   permResult  [nRows x nCols] struct. Expected fields:
%               - pVal (scalar)
%               - isSig (logical)
%               - strength (scalar, optional)
%               - nTrials (scalar, optional)
%   mdls        [1 x nCols] cell. Optional per-column model info:
%               - mdls{k}.threshCI [1x2] (optional)
%               - mdls{k}.model (optional; GLM/cfit/isotonic struct)
%               - mdls{k}.type, .criterion, .fitTarget (optional)
%
% Options (struct; defaults)
%   options.startCol        (1,1) double = 1
%   options.colLabels       (1,nCols) string = "Col 1", ...
%   options.nearestLevel    (1,1) logical = false   % pin manual threshold up to nearest rowVals
%   options.outCSV          (1,1) string = ""       % if nonempty, write CSV on save/export
%   options.outMAT          (1,1) string = ""       % if nonempty, save session MAT on save/export
%   options.alphaLine       (1,1) double = 0.05     % reference line for p-values (display)
%   options.showStrength    (1,1) logical = true
%   options.showModel       (1,1) logical = true
%   options.titlePrefix     (1,1) string = "ABR Threshold Curation"
%
%   options.S               cell [nRows x nCols] = {}.
%       Original waveform data. Each S{r,c} must be [nSamples x nTrials].
%   options.t               double [nSamples x 1] = [].
%       Optional time axis for waveform plot. If empty, uses sample index.
%   options.waveYUnits      (1,1) string = "a.u."
%   options.waveShowSEM     (1,1) logical = true
%   options.waveRowPolicy   (1,1) string = "nearThreshold"
%       "nearThreshold" | "maxStrength" | "highestLevel"
%
%   options.flag.alpha      (1,1) double = options.alphaLine
%   options.flag.wideCIFrac (1,1) double = 0.35
%   options.flag.nonMonoTol (1,1) double = 0
%   options.flag.minTrials  (1,1) double = 0
%   options.flag.requireSomeSig (1,1) logical = false
%
% Outputs
%   curation struct:
%     .rowVals, .thresh_auto, .thresh_manual, .thresh_final
%     .accepted_auto, .excluded, .noResponse, .notes
%     .flags (cell of string arrays), .timestamp, .mdls
%
%   state struct:
%     .k current column, .fig, .lastSaved, .rowSel per column
%
% Hotkeys
%   ← / →      prev/next column
%   J          jump to column
%   F          next flagged column
%   A          accept auto
%   R          reject auto
%   C          click set manual
%   T          type manual
%   P          toggle pin-to-nearest-level
%   I          mark no response (Inf)
%   X          exclude (NaN)
%   N          note
%   S          save
%   ↑ / ↓      change waveform row (if options.S provided)
%   Q / Esc    quit
%
% DJS 2025

arguments
    rowVals (:,1) double
    thresh_hat (1,:) double
    permResult (:,:) struct
    mdls cell = {}

    options.startCol (1,1) double {mustBeInteger,mustBePositive} = 1
    options.colLabels (1,:) string = string.empty
    options.nearestLevel (1,1) logical = false
    options.outCSV (1,1) string = ""
    options.outMAT (1,1) string = ""
    options.alphaLine (1,1) double {mustBeGreaterThanOrEqual(options.alphaLine,0),mustBeLessThanOrEqual(options.alphaLine,1)} = 0.05
    options.showStrength (1,1) logical = true
    options.showModel (1,1) logical = true
    options.titlePrefix (1,1) string = "ABR Threshold Curation"

    options.S cell = {}
    options.t double = []
    options.waveYUnits (1,1) string = "a.u."
    options.waveShowSEM (1,1) logical = true
    options.waveRowPolicy (1,1) string {mustBeMember(options.waveRowPolicy,["nearThreshold","maxStrength","highestLevel"])} = "nearThreshold"

    options.flag struct = struct()
end

% ---- flags defaults ----
if ~isfield(options.flag,"alpha"), options.flag.alpha = options.alphaLine; end
if ~isfield(options.flag,"wideCIFrac"), options.flag.wideCIFrac = 0.35; end
if ~isfield(options.flag,"nonMonoTol"), options.flag.nonMonoTol = 0; end
if ~isfield(options.flag,"minTrials"), options.flag.minTrials = 0; end
if ~isfield(options.flag,"requireSomeSig"), options.flag.requireSomeSig = false; end

% -------------------- validate shapes --------------------
nCols = numel(thresh_hat);
nRows = numel(rowVals);

assert(size(permResult,2) == nCols, "permResult must have nCols columns matching thresh_hat.");
assert(size(permResult,1) == nRows, "permResult must have nRows rows matching rowVals.");

if isempty(mdls)
    mdls = cell(1,nCols);
elseif numel(mdls) ~= nCols
    error("mdls must be 1 x nCols cell (or empty).");
end

if isempty(options.colLabels)
    options.colLabels = "Col " + string(1:nCols);
else
    assert(numel(options.colLabels) == nCols, "options.colLabels must be length nCols.");
end

hasS = ~isempty(options.S);
if hasS
    assert(iscell(options.S) && isequal(size(options.S), [nRows nCols]), "options.S must be cell [nRows x nCols].");
end

% -------------------- output struct init --------------------
curation = struct();
curation.rowVals = rowVals(:);
curation.thresh_auto = reshape(thresh_hat, 1, []);
curation.thresh_manual = nan(1, nCols);
curation.thresh_final = curation.thresh_auto;
curation.accepted_auto = true(1, nCols);
curation.excluded = false(1, nCols);
curation.noResponse = false(1, nCols);
curation.notes = strings(1, nCols);
curation.flags = cell(1, nCols);
curation.timestamp = datetime("now");
curation.mdls = mdls;

curation.flags = computeFlags();

state = struct();
state.k = min(max(options.startCol,1), nCols);
state.lastSaved = NaT;
state.rowSel = nan(1, nCols);
for k = 1:nCols
    state.rowSel(k) = defaultWaveRow(k);
end

% -------------------- UI layout --------------------
fig = figure( ...
    "Name", options.titlePrefix, ...
    "Color", "w", ...
    "NumberTitle","off", ...
    "KeyPressFcn", @onKey, ...
    "CloseRequestFcn", @onClose);

state.fig = fig;

tl = tiledlayout(fig, 2, 2, "TileSpacing","compact", "Padding","compact");
axDetect = nexttile(tl, 1);
axStrength = nexttile(tl, 3);
axWave = nexttile(tl, [2 1]);

uicontrol(fig, "Style","text", "Units","normalized", "Position",[0.01 0.965 0.54 0.03], ...
    "String","Keys: ←/→  J jump  F next-flag  A accept  R reject  C click  T type  P pin  I Inf  X NaN  N note  S save  ↑/↓ row  Q quit", ...
    "BackgroundColor","w", "HorizontalAlignment","left");

btnPrev = uicontrol(fig, "Style","pushbutton", "Units","normalized", "Position",[0.62 0.962 0.06 0.035], ...
    "String","Prev", "Callback", @(~,~) gotoCol(state.k-1));
btnNext = uicontrol(fig, "Style","pushbutton", "Units","normalized", "Position",[0.69 0.962 0.06 0.035], ...
    "String","Next", "Callback", @(~,~) gotoCol(state.k+1));
btnJump = uicontrol(fig, "Style","pushbutton", "Units","normalized", "Position",[0.76 0.962 0.06 0.035], ...
    "String","Jump", "Callback", @(~,~) doJump());
btnSave = uicontrol(fig, "Style","pushbutton", "Units","normalized", "Position",[0.83 0.962 0.06 0.035], ...
    "String","Save", "Callback", @(~,~) doSave());
btnQuit = uicontrol(fig, "Style","pushbutton", "Units","normalized", "Position",[0.90 0.962 0.06 0.035], ...
    "String","Quit", "Callback", @(~,~) doQuit());

txtStatus = uicontrol(fig, "Style","text", "Units","normalized", "Position",[0.56 0.965 0.06 0.03], ...
    "String","", "BackgroundColor","w", "HorizontalAlignment","left");

if hasS
    rowStrings = compose("%g", rowVals);
    popupRow = uicontrol(fig, "Style","popupmenu", "Units","normalized", ...
        "Position",[0.90 0.01 0.09 0.04], "String", rowStrings, ...
        "Callback", @(src,~) onRowPopup(src));
    uicontrol(fig, "Style","text", "Units","normalized", ...
        "Position",[0.80 0.01 0.09 0.04], "String","Wave row", ...
        "BackgroundColor","w", "HorizontalAlignment","right");
else
    popupRow = [];
end

refreshAll();
uiwait(fig);

% ===================== nested functions =====================

    function refreshAll()
        refreshPlots();
        refreshWavePanel();
        refreshStatus();
        refreshButtons();
    end

    function refreshPlots()
        k = state.k;
        [p, sig, strength, nTr] = colMeasures(k);

        thrA = curation.thresh_auto(k);
        thrM = curation.thresh_manual(k);
        thrF = curation.thresh_final(k);
        thrCI = getCI(k);

        % ---------- Detection panel (yyaxis; no overlay axes) ----------
        cla(axDetect);
        grid(axDetect,"on");

        % Left axis: detected yes/no
        yyaxis(axDetect,"left");
        plot(axDetect, rowVals, double(sig), "ko", "MarkerFaceColor","k");
        ylim(axDetect, [-0.15 1.15]);
        yticks(axDetect, [0 1]);
        yticklabels(axDetect, ["no","yes"]);
        ylabel(axDetect, sprintf("Detected (p<%.3g)", options.flag.alpha));
        xlabel(axDetect, "rowVals");

        % Right axis: -log10(p)
        yyaxis(axDetect,"right");
        pClip = p;
        pClip(~isfinite(pClip)) = nan;
        pClip = min(max(pClip, 1e-12), 1);
        plot(axDetect, rowVals, -log10(pClip), "b.-");
        ylabel(axDetect, "-log10(p)");
        if isfinite(options.alphaLine) && options.alphaLine > 0 && options.alphaLine < 1
            yline(axDetect, -log10(max(options.alphaLine,1e-12)), "b--", "p=alpha");
        end

        % Draw threshold lines on top (switch back to left to keep ylims sane)
        yyaxis(axDetect,"left");
        drawThresholdLines(axDetect, thrA, thrM, thrF, thrCI);

        fl = curation.flags{k};
        flagStr = "";
        if ~isempty(fl), flagStr = "  ⚑ " + strjoin(fl, ", "); end

        mdlType = "";
        if ~isempty(mdls{k}) && isstruct(mdls{k}) && isfield(mdls{k},"type")
            mdlType = " (" + string(mdls{k}.type) + ")";
        end

        title(axDetect, sprintf("%s — %s%s%s", options.titlePrefix, options.colLabels(k), mdlType, flagStr), "Interpreter","none");

        % ---------- Strength panel ----------
        cla(axStrength);
        grid(axStrength,"on");
        xlabel(axStrength, "rowVals");
        ylabel(axStrength, "strength");

        if options.showStrength && any(isfinite(strength))
            plot(axStrength, rowVals, strength, "ko", "MarkerFaceColor","k");
        else
            text(axStrength, 0.5, 0.5, "No strength available", "Units","normalized", ...
                "HorizontalAlignment","center", "Color",[0.4 0.4 0.4]);
        end

        drawThresholdLines(axStrength, thrA, thrM, thrF, thrCI);

        if options.showModel
            overlayModel(axStrength, k);
        end

        if any(isfinite(nTr))
            yl = ylim(axStrength);
            yText = yl(1) + 0.05*(yl(2)-yl(1));
            for r = 1:nRows
                if isfinite(nTr(r))
                    text(axStrength, rowVals(r), yText, sprintf("%d", nTr(r)), ...
                        "HorizontalAlignment","center", "Color",[0.5 0.5 0.5], "FontSize",8);
                end
            end
        end
    end

    function refreshWavePanel()
        cla(axWave);
        grid(axWave,"on");
        k = state.k;

        fl = curation.flags{k};
        note = curation.notes(k);

        if ~hasS
            text(axWave, 0.5, 0.6, "No waveform data (options.S not provided).", "Units","normalized", ...
                "HorizontalAlignment","center", "Color",[0.4 0.4 0.4]);
            text(axWave, 0.5, 0.45, "Call with options.S = S to enable waveform panel.", ...
                "Units","normalized", "HorizontalAlignment","center", "Color",[0.4 0.4 0.4]);
            axis(axWave,"off");
            return
        end

        rSel = state.rowSel(k);
        if ~isfinite(rSel) || rSel < 1 || rSel > nRows
            rSel = defaultWaveRow(k);
            state.rowSel(k) = rSel;
        end

        A = options.S{rSel, k};  % [nSamples x nTrials]
        if isempty(A) || ~isnumeric(A)
            text(axWave, 0.5, 0.6, sprintf("No waveform in S{%d,%d}.", rSel, k), "Units","normalized", ...
                "HorizontalAlignment","center", "Color",[0.4 0.4 0.4]);
            axis(axWave,"off");
            return
        end

        [nSamp, nTr] = size(A);
        mu = mean(A, 2, "omitnan");
        sem = std(A, 0, 2, "omitnan") ./ max(1, sqrt(nTr));

        if isempty(options.t)
            x = (1:nSamp).';
            xlab = "sample";
        else
            x = options.t(:);
            if numel(x) ~= nSamp
                x = (1:nSamp).';
                xlab = "sample";
            else
                xlab = "time";
            end
        end

        hold(axWave,"on");
        if options.waveShowSEM && all(isfinite(sem))
            patch(axWave, [x; flipud(x)], [mu-sem; flipud(mu+sem)], [0.7 0.7 0.7], ...
                "FaceAlpha",0.25, "EdgeColor","none");
        end
        plot(axWave, x, mu, "k-", "LineWidth", 1.5);
        hold(axWave,"off");

        xlabel(axWave, xlab);
        ylabel(axWave, options.waveYUnits);

        [p, sig, strength, ~] = colMeasures(k);
        txt1 = sprintf("%s | row=%g (idx %d) | nTrials=%d | p=%.3g | sig=%d", ...
            options.colLabels(k), rowVals(rSel), rSel, nTr, p(rSel), sig(rSel));
        if isfinite(strength(rSel))
            txt1 = txt1 + sprintf(" | strength=%.3g", strength(rSel));
        end
        title(axWave, txt1, "Interpreter","none");

        y0 = 0.02;
        if ~isempty(fl)
            text(axWave, 0.01, y0, "FLAGS: " + strjoin(fl,", "), "Units","normalized", ...
                "HorizontalAlignment","left", "VerticalAlignment","bottom", "Color",[0.6 0 0], "FontWeight","bold");
            y0 = y0 + 0.06;
        end
        if strlength(note) > 0
            text(axWave, 0.01, y0, "NOTE: " + note, "Units","normalized", ...
                "HorizontalAlignment","left", "VerticalAlignment","bottom", "Color",[0 0 0]);
        end
    end

    function refreshStatus()
        k = state.k;
        parts = [
            "k=" + k + "/" + nCols
            "auto=" + fmtVal(curation.thresh_auto(k))
            "manual=" + fmtVal(curation.thresh_manual(k))
            "final=" + fmtVal(curation.thresh_final(k))
            "pin=" + string(options.nearestLevel)
        ];
        txtStatus.String = strjoin(parts, " | ");
    end

    function refreshButtons()
        k = state.k;
        btnPrev.Enable = onoff(k>1);
        btnNext.Enable = onoff(k<nCols);
    end

    function gotoCol(kNew)
        kNew = min(max(round(kNew), 1), nCols);
        state.k = kNew;
        if ~isfinite(state.rowSel(kNew))
            state.rowSel(kNew) = defaultWaveRow(kNew);
        end
        if hasS && ~isempty(popupRow)
            popupRow.Value = state.rowSel(kNew);
        end
        refreshAll();
    end

    function doJump()
        k = state.k;
        prompt = sprintf("Jump to column:\n- Enter an index 1..%d\n- Or type part of a label", nCols);
        answ = inputdlg(prompt, "Jump to column", 1, {char(options.colLabels(k))});
        if isempty(answ), return; end
        s = strtrim(answ{1});
        if isempty(s), return; end

        v = str2double(s);
        if isfinite(v)
            gotoCol(v);
            return
        end

        labels = lower(string(options.colLabels));
        hit = find(contains(labels, lower(string(s))), 1, "first");
        if isempty(hit)
            warndlg("No label match found.", "Jump");
        else
            gotoCol(hit);
        end
    end

    function doNextFlagged()
        k0 = state.k;
        if all(cellfun(@isempty, curation.flags))
            warndlg("No flagged columns.", "Flags");
            return
        end
        for step = 1:nCols
            k = mod(k0-1 + step, nCols) + 1;
            if ~isempty(curation.flags{k})
                gotoCol(k);
                return
            end
        end
    end

    function onRowPopup(src)
        k = state.k;
        state.rowSel(k) = src.Value;
        refreshWavePanel();
    end

    function onKey(~, evt)
        switch lower(evt.Key)
            case "rightarrow", gotoCol(state.k+1);
            case "leftarrow",  gotoCol(state.k-1);
            case "j",          doJump();
            case "f",          doNextFlagged();

            case "a",          doAcceptAuto();
            case "r",          doRejectAuto();
            case "c",          doClickSet();
            case "t",          doTypeSet();
            case "p"
                options.nearestLevel = ~options.nearestLevel;
                repinCurrentIfNeeded();
                refreshAll();
            case "i",          doNoResponse();
            case "x",          doExclude();
            case "n",          doNote();
            case "s",          doSave();

            case "uparrow"
                if hasS
                    state.rowSel(state.k) = max(1, state.rowSel(state.k)-1);
                    if ~isempty(popupRow), popupRow.Value = state.rowSel(state.k); end
                    refreshWavePanel();
                end
            case "downarrow"
                if hasS
                    state.rowSel(state.k) = min(nRows, state.rowSel(state.k)+1);
                    if ~isempty(popupRow), popupRow.Value = state.rowSel(state.k); end
                    refreshWavePanel();
                end

            case {"q","escape"}
                doQuit();
        end
    end

    function doAcceptAuto()
        k = state.k;
        curation.accepted_auto(k) = true;
        curation.thresh_manual(k) = nan;
        curation.excluded(k) = false;
        curation.noResponse(k) = false;
        curation.thresh_final(k) = curation.thresh_auto(k);
        curation.flags = computeFlags();
        refreshAll();
    end

    function doRejectAuto()
        k = state.k;
        curation.accepted_auto(k) = false;
        if isfinite(curation.thresh_manual(k))
            curation.thresh_final(k) = curation.thresh_manual(k);
        else
            curation.thresh_final(k) = curation.thresh_auto(k);
        end
        curation.flags = computeFlags();
        refreshAll();
    end

    function doClickSet()
        k = state.k;
        figure(fig);
        [xClick, ~] = ginput(1);
        if isempty(xClick) || ~isfinite(xClick), return; end
        setManualThreshold(k, xClick);
    end

    function doTypeSet()
        k = state.k;
        answ = inputdlg("Manual threshold value:", "Set threshold", 1, {char(fmtVal(curation.thresh_final(k)))});
        if isempty(answ), return; end
        v = str2double(answ{1});
        if ~isfinite(v), return; end
        setManualThreshold(k, v);
    end

    function setManualThreshold(k, v)
        if options.nearestLevel
            idx = find(rowVals >= v, 1, "first");
            if ~isempty(idx), v = rowVals(idx); end
        end
        curation.thresh_manual(k) = v;
        curation.thresh_final(k) = v;
        curation.accepted_auto(k) = false;
        curation.excluded(k) = false;
        curation.noResponse(k) = false;
        curation.flags = computeFlags();
        refreshAll();
    end

    function repinCurrentIfNeeded()
        k = state.k;
        if ~options.nearestLevel || ~isfinite(curation.thresh_manual(k)), return; end
        v = curation.thresh_manual(k);
        idx = find(rowVals >= v, 1, "first");
        if ~isempty(idx)
            curation.thresh_manual(k) = rowVals(idx);
            curation.thresh_final(k) = rowVals(idx);
        end
    end

    function doNoResponse()
        k = state.k;
        curation.noResponse(k) = true;
        curation.excluded(k) = false;
        curation.accepted_auto(k) = false;
        curation.thresh_manual(k) = nan;
        curation.thresh_final(k) = inf;
        curation.flags = computeFlags();
        refreshAll();
    end

    function doExclude()
        k = state.k;
        curation.excluded(k) = true;
        curation.noResponse(k) = false;
        curation.accepted_auto(k) = false;
        curation.thresh_manual(k) = nan;
        curation.thresh_final(k) = nan;
        curation.flags = computeFlags();
        refreshAll();
    end

    function doNote()
        k = state.k;
        answ = inputdlg("Note for this column:", "Edit note", 1, {char(curation.notes(k))});
        if isempty(answ), return; end
        curation.notes(k) = string(answ{1});
        refreshWavePanel();
    end

    function doSave()
        if strlength(options.outCSV) > 0
            T = curationToTable(curation, options.colLabels);
            try, writetable(T, options.outCSV);
            catch ME, warning(ME.identifier,"CSV export failed: %s", ME.message);
            end
        end

        if strlength(options.outMAT) > 0
            try
                curation.timestamp = datetime("now");
                state.lastSaved = datetime("now");
                save(options.outMAT, "curation", "state", "permResult", "mdls", "rowVals", "thresh_hat", "options");
            catch ME
                warning(ME.identifier,"MAT save failed: %s", ME.message);
            end
        else
            state.lastSaved = datetime("now");
        end
        refreshStatus();
    end

    function doQuit()
        if ishandle(fig)
            uiresume(fig);
            delete(fig);
        end
    end

    function onClose(~,~)
        doQuit();
    end

    function [p, sig, strength, nTr] = colMeasures(k)
        p = nan(nRows,1);
        sig = false(nRows,1);
        strength = nan(nRows,1);
        nTr = nan(nRows,1);
        for r = 1:nRows
            if isfield(permResult(r,k), "pVal") && ~isempty(permResult(r,k).pVal), p(r) = permResult(r,k).pVal; end
            if isfield(permResult(r,k), "isSig") && ~isempty(permResult(r,k).isSig), sig(r) = logical(permResult(r,k).isSig); end
            if isfield(permResult(r,k), "strength") && ~isempty(permResult(r,k).strength), strength(r) = permResult(r,k).strength; end
            if isfield(permResult(r,k), "nTrials") && ~isempty(permResult(r,k).nTrials), nTr(r) = permResult(r,k).nTrials; end
        end
    end

    function thrCI = getCI(k)
        thrCI = [nan nan];
        if ~isempty(mdls{k}) && isstruct(mdls{k}) && isfield(mdls{k},"threshCI") && numel(mdls{k}.threshCI)==2
            thrCI = mdls{k}.threshCI;
        end
    end

    function drawThresholdLines(ax, thrA, thrM, thrF, thrCI)
        yl = ylim(ax);

        if all(isfinite(thrCI))
            patch(ax, [thrCI(1) thrCI(2) thrCI(2) thrCI(1)], [yl(1) yl(1) yl(2) yl(2)], ...
                [0.8 0.8 0.8], "FaceAlpha",0.2, "EdgeColor","none", "HandleVisibility","off");
        end
        if isfinite(thrA), xline(ax, thrA, "k--", "auto", "LineWidth", 1.0); end
        if isfinite(thrM), xline(ax, thrM, "r--", "manual", "LineWidth", 1.5); end
        if isinf(thrF),    xline(ax, max(rowVals), "b:", "Inf", "LineWidth", 1.5); end
        if isnan(thrF),    xline(ax, min(rowVals), "b:", "NaN", "LineWidth", 1.5); end

        ylim(ax, yl);
    end

    function overlayModel(ax, k)
        if isempty(mdls{k}) || ~isstruct(mdls{k}) || ~isfield(mdls{k},"model") || isempty(mdls{k}.model)
            return;
        end
        mdl = mdls{k}.model;
        xs = linspace(min(rowVals), max(rowVals), 200).';
        hold(ax,"on");
        try
            if isa(mdl, "GeneralizedLinearModel")
                ps = predict(mdl, table(xs, "VariableNames", {'x'}));
                yyaxis(ax,"right");
                plot(ax, xs, ps, "-", "LineWidth", 1.2);
                yyaxis(ax,"left");
            elseif isa(mdl, "cfit")
                ys = feval(mdl, xs);
                plot(ax, xs, ys, "-", "LineWidth", 1.2);
            elseif isstruct(mdl) && isfield(mdl,"xUnique") && isfield(mdl,"yhatUnique")
                stairs(ax, mdl.xUnique, mdl.yhatUnique, "-", "LineWidth", 1.2);
            end
        catch
        end
        hold(ax,"off");
    end

    function r = defaultWaveRow(k)
        if ~hasS
            r = 1; return
        end
        [~, ~, strength, ~] = colMeasures(k);
        switch options.waveRowPolicy
            case "highestLevel"
                r = nRows;
            case "maxStrength"
                if any(isfinite(strength)), [~, r] = max(strength); else, r = nRows; end
            case "nearThreshold"
                thr = curation.thresh_final(k);
                if isfinite(thr)
                    [~, r] = min(abs(rowVals - thr));
                else
                    if any(isfinite(strength)), [~, r] = max(strength); else, r = nRows; end
                end
        end
        r = min(max(r,1), nRows);
    end

    function flags = computeFlags()
        flags = cell(1, nCols);
        span = max(rowVals) - min(rowVals);
        if span <= 0, span = 1; end

        for k = 1:nCols
            f = strings(0,1);
            [~, sig, strength, nTr] = colMeasures(k);

            if any(sig)
                idx1 = find(sig, 1, "first");
                backslides = sum(sig(idx1:end) == 0);
                if backslides > options.flag.nonMonoTol
                    f(end+1) = "non-monotone detect";
                end
            end

            if options.flag.requireSomeSig && ~any(sig)
                f(end+1) = "no sig rows";
            end

            thrCI = getCI(k);
            if all(isfinite(thrCI))
                if (thrCI(2)-thrCI(1))/span > options.flag.wideCIFrac
                    f(end+1) = "wide CI";
                end
            end

            thrF = curation.thresh_final(k);
            if isfinite(thrF) && (thrF < min(rowVals) || thrF > max(rowVals))
                f(end+1) = "threshold out-of-range";
            end

            if options.flag.minTrials > 0 && any(isfinite(nTr) & (nTr < options.flag.minTrials))
                f(end+1) = "low trials";
            end

            if ~any(isfinite(strength))
                f(end+1) = "no strength";
            end

            if curation.excluded(k), f(end+1) = "excluded"; end
            if curation.noResponse(k), f(end+1) = "no response"; end

            flags{k} = f;
        end
    end

end

% ===================== non-nested helpers =====================

function T = curationToTable(curation, colLabels)
nCols = numel(curation.thresh_auto);
T = table();
T.col = (1:nCols).';
T.label = colLabels(:);
T.thresh_auto = curation.thresh_auto(:);
T.thresh_manual = curation.thresh_manual(:);
T.thresh_final = curation.thresh_final(:);
T.accepted_auto = curation.accepted_auto(:);
T.excluded = curation.excluded(:);
T.noResponse = curation.noResponse(:);
T.notes = curation.notes(:);
T.flags = strings(nCols,1);
for k = 1:nCols
    fl = curation.flags{k};
    if isempty(fl), T.flags(k) = ""; else, T.flags(k) = strjoin(fl, "; "); end
end
T.timestamp = repmat(curation.timestamp, nCols, 1);
end

function s = fmtVal(v)
if isnan(v), s = "NaN"; return; end
if isinf(v), s = "Inf"; return; end
s = string(sprintf("%.4g", v));
end

function e = onoff(tf)
if tf, e = "on"; else, e = "off"; end
end

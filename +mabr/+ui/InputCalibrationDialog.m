function audio = InputCalibrationDialog(audio0,cfg,controller)
% mabr.ui.InputCalibrationDialog  Measure the recorder input's full scale in volts.
%
%   a = mabr.ui.InputCalibrationDialog(a0,cfg,controller) opens a modal window
%   over the mabr.AudioSettings a0 and returns a copy carrying whatever was
%   measured -- OutputFullScale/OutputCalibrated and InputFullScale/
%   InputCalibrated -- or [] when cancelled or when nothing was measured.
%   Nothing is saved here: mabr.ui.AudioSettingsDialog takes the values into
%   its controls, and they are applied by its Commit like any other edit.
%
%   The interface's input gain knob decides how many converter units a volt
%   is, and MABR cannot see the knob. This measures it, in two steps (see
%   mabr.acq.InputCalibrator for the arithmetic):
%
%     1. The output, ONCE PER RIG, against a true-RMS multimeter: play a tone,
%        type in what the meter reads.
%     2. The input, WHENEVER THE KNOB MOVES, through a plain loop-back cable
%        from the signal output to the signal input: press Measure. No meter.
%
%   controller (optional) is the acquisition controller, so the calibrator
%   can refuse while a schedule or the input monitor holds the device, and
%   take the device back from the idle worker otherwise.
%
% Daniel Stolzberg (c) 2026

if nargin < 1 || isempty(audio0), audio0 = mabr.AudioSettings.loadPrefs(); end
if nargin < 2 || isempty(cfg),    cfg = audio0.config(); end
if nargin < 3,                    controller = []; end

audio   = [];
work    = audio0;                   % what the two steps have measured so far
changed = false;
outCh   = audio0.PlayerChannels(1);
inCh    = audio0.RecorderChannels(1);
cal     = mabr.acq.InputCalibrator(audio0,cfg,controller);

% ---- layout -------------------------------------------------------------
fig = uifigure('Name','Input Calibration','Position',[140 140 540 590], ...
    'WindowStyle','modal','Resize','off', ...
    'CloseRequestFcn',@(~,~) onCancel());
mabr.ui.WindowPos.restore(fig,'InputCalibrationDialog',fig.Position);

g = uigridlayout(fig,[13 1]);
g.RowHeight = {48,22,48,30,30,22,22,36,36,48,48,40,32};
g.Padding   = [14 10 14 10];
g.RowSpacing = 6;

grey = [0.3 0.3 0.3];

intro = uilabel(g,'WordWrap','on','FontColor',grey,'Text', ...
    ['The input gain knob decides how many volts read as full scale, and MABR ' ...
     'cannot see it. Measure it here and every recording is in volts again — ' ...
     'at the electrodes, once the amplifier gain is set too.']);
intro.Layout.Row = 1;

% ---- step 1: the output --------------------------------------------------
h1 = uilabel(g,'Text','1.  Output reference — once per rig','FontWeight','bold');
h1.Layout.Row = 2;
t1 = uilabel(g,'WordWrap','on','Text',sprintf( ...
    ['Unplug the speaker amplifier from output %d and put a true-RMS ' ...
     'multimeter (AC volts) on it. Play the tone, read the meter while it ' ...
     'plays, and enter the reading.'],outCh));
t1.Layout.Row = 3;

r1 = uigridlayout(g,[1 6]);
r1.Layout.Row = 4;
r1.ColumnWidth = {'fit',70,'fit',70,'1x',130};
r1.Padding = [0 0 0 0]; r1.ColumnSpacing = 6;
uilabel(r1,'Text','Level');
levelField = uieditfield(r1,'numeric','Value',-10,'Limits',[-60 0], ...
    'ValueDisplayFormat','%g dBFS', ...
    'Tooltip','Digital level the tone is played at for the meter. -10 dBFS reads comfortably on any meter.');
uilabel(r1,'Text','Frequency');
freqField = uieditfield(r1,'numeric','Value',cal.Frequency,'Limits',[20 5000], ...
    'ValueDisplayFormat','%g Hz', ...
    'Tooltip',['Used for both steps. Keep it inside your meter''s AC bandwidth ' ...
        '(400 Hz suits even basic meters).']);
uilabel(r1,'Text','');
playBtn = uibutton(r1,'Text','Play for meter…','ButtonPushedFcn',@(~,~) onPlay());

r2 = uigridlayout(g,[1 3]);
r2.Layout.Row = 5;
r2.ColumnWidth = {'fit',90,60};
r2.Padding = [0 0 0 0]; r2.ColumnSpacing = 6;
uilabel(r2,'Text','Meter reading');
meterField = uieditfield(r2,'numeric','Value',0,'Limits',[0 Inf], ...
    'ValueDisplayFormat','%g V RMS', ...
    'Tooltip','The meter''s AC voltage reading while the tone played, in volts RMS.');
uibutton(r2,'Text','Set','ButtonPushedFcn',@(~,~) onSetOutput(), ...
    'Tooltip','Compute the output''s full scale from this reading and the level above.');
outLbl = uilabel(g,'Text','','FontColor',grey);
outLbl.Layout.Row = 6;

% ---- step 2: the input ---------------------------------------------------
h2 = uilabel(g,'Text','2.  Input — whenever the gain knob moves','FontWeight','bold');
h2.Layout.Row = 7;
t2 = uilabel(g,'WordWrap','on','Text',sprintf( ...
    ['Patch output %d to input %d with a plain cable, the electrode amplifier ' ...
     'unplugged, the knob where you will record. No meter needed.'],outCh,inCh));
t2.Layout.Row = 8;
ifsNow = uilabel(g,'WordWrap','on','FontColor',grey,'Text','');
ifsNow.Layout.Row = 9;

r3 = uigridlayout(g,[1 2]);
r3.Layout.Row = 10;
r3.ColumnWidth = {130,'1x'};
r3.Padding = [0 0 0 0]; r3.ColumnSpacing = 8;
measureBtn = uibutton(r3,'Text','Measure','FontWeight','bold', ...
    'ButtonPushedFcn',@(~,~) onMeasure());
resultLbl = uilabel(r3,'Text','','WordWrap','on');

timingNote = uilabel(g,'WordWrap','on','FontColor',grey,'Text',sprintf( ...
    ['The timing input (%d) needs no calibration: its knob only has to keep ' ...
     'the pulse clear of the 0.1 detection threshold without clipping. ' ...
     'verify_timing_loopback reports that margin.'],audio0.RecorderChannels(2)));
timingNote.Layout.Row = 11;

msgLbl = uilabel(g,'Text','','FontColor',[0.8 0.2 0],'WordWrap','on');
msgLbl.Layout.Row = 12;

r4 = uigridlayout(g,[1 3]);
r4.Layout.Row = 13;
r4.ColumnWidth = {'1x',130,90};
r4.Padding = [0 0 0 0]; r4.ColumnSpacing = 8;
uilabel(r4,'Text','');
useBtn = uibutton(r4,'Text','Use these values','FontWeight','bold', ...
    'BackgroundColor',[0.6 0.9 0.6],'ButtonPushedFcn',@(~,~) onUse(), ...
    'Tooltip','Put the measured values into the Audio Device dialog. Commit applies them there.');
uibutton(r4,'Text','Cancel','ButtonPushedFcn',@(~,~) onCancel());

refresh();

try
    cal.assertUsable();
catch me
    setMessage(me.message,false);
    playBtn.Enable = 'off';
    measureBtn.Enable = 'off';
end

uiwait(fig);

% ===================== nested callbacks ==================================
    function refresh()
        if work.hasOutputReference()
            outLbl.Text = sprintf('Output %d full scale: 1.0 = %.4g V peak %s',outCh, ...
                work.OutputFullScale,paren(mabr.AudioSettings.stampText(work.OutputCalibrated)));
        else
            outLbl.Text = 'Output not measured yet.';
        end
        if isempty(work.InputCalibrated)
            how = 'assumed or typed, not measured';
        else
            how = mabr.AudioSettings.stampText(work.InputCalibrated);
        end
        ifsNow.Text = sprintf('Input %d full scale now: 1.0 = %.4g V peak (%s).', ...
            inCh,work.InputFullScale,how);
        measureBtn.Enable = onOff(work.hasOutputReference() && strcmp(playBtn.Enable,'on'));
        if work.hasOutputReference()
            measureBtn.Tooltip = sprintf(['Play the tone through the loop-back, ' ...
                'auto-ranged, and fit what comes back on input %d.'],inCh);
        else
            measureBtn.Tooltip = 'Measure the output against a meter first (step 1).';
        end
        useBtn.Enable = onOff(changed);
    end

    function onPlay()
        cal.Frequency = freqField.Value;
        lvl = levelField.Value;
        pick = uiconfirm(fig,sprintf(['This plays a steady %g Hz tone at %g dBFS ' ...
            'out of output %d for 20 s.\n\nUnplug the speaker amplifier first.'], ...
            cal.Frequency,lvl,outCh),'Play for meter', ...
            'Options',{'Play','Cancel'},'DefaultOption',2,'CancelOption',2, ...
            'Icon','warning');
        if ~strcmp(pick,'Play'), return; end
        d = uiprogressdlg(fig,'Title','Playing', ...
            'Message',sprintf('%g Hz at %g dBFS on output %d — read the meter now.', ...
                cal.Frequency,lvl,outCh), ...
            'Indeterminate','on','Cancelable','on','CancelText','Stop');
        try
            cal.playForMeter(lvl,20,@() stopRequested(d));
            setMessage('',true);
        catch me
            setMessage(sprintf('Could not play: %s',me.message),false);
        end
        close(d);
        try, focus(meterField); end %#ok<TRYNC> % focus() is R2022a+
    end

    function onSetOutput()
        v = meterField.Value;
        if v <= 0
            setMessage('Enter the meter''s reading (V RMS) first.',false);
            return
        end
        work.OutputFullScale  = mabr.acq.InputCalibrator.outputFullScale(v,levelField.Value);
        work.OutputCalibrated = mabr.AudioSettings.stamp();
        cal.Audio = work;
        changed = true;
        setMessage(sprintf(['%g V RMS at %g dBFS: output %d reaches %.4g V peak ' ...
            'at full scale.'],v,levelField.Value,outCh,work.OutputFullScale),true);
        refresh();
    end

    function onMeasure()
        cal.Frequency = freqField.Value;
        cal.Audio = work;
        d = uiprogressdlg(fig,'Title','Measuring', ...
            'Message',sprintf('Playing %g Hz through output %d → input %d…', ...
                cal.Frequency,outCh,inCh),'Indeterminate','on');
        try
            [ifs,rep] = cal.measureInput();
        catch me
            close(d);
            resultLbl.Text = '';
            setMessage(me.message,false);
            return
        end
        close(d);
        old = work.InputFullScale;
        work.InputFullScale  = ifs;
        work.InputCalibrated = mabr.AudioSettings.stamp();
        changed = true;
        resultLbl.Text = sprintf(['1.0 = %.4g V peak at input %d (was %.4g V, %+.1f dB). ' ...
            'Tone %.1f dBFS out, %.1f dBFS in.'], ...
            ifs,inCh,old,20*log10(ifs/old),rep.Level,rep.InputDbfs);
        if isempty(rep.Warnings)
            resultLbl.FontColor = [0 0.5 0];
            setMessage('',true);
        else
            resultLbl.FontColor = [0.8 0.4 0];
            setMessage(strjoin(rep.Warnings,' '),false);
        end
        refresh();
    end

    function onUse()
        audio = work;
        close_();
    end

    function onCancel()
        audio = [];
        close_();
    end

    function close_()
        mabr.ui.WindowPos.remember(fig,'InputCalibrationDialog');
        delete(fig);
    end

    function setMessage(txt,good)
        msgLbl.Text = txt;
        if good
            msgLbl.FontColor = [0 0.5 0];
        else
            msgLbl.FontColor = [0.8 0.2 0];
        end
    end
end

% ======================= local helpers ================================
function tf = stopRequested(d)
% The progress dialog's Stop only registers once the queue is flushed.
drawnow limitrate
tf = ~isvalid(d) || d.CancelRequested;
end

function s = paren(txt)
if isempty(txt), s = ''; else, s = ['(' txt ')']; end
end

function s = onOff(tf)
if tf, s = 'on'; else, s = 'off'; end
end

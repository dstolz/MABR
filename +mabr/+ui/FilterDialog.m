function policy = FilterDialog(policy0,Fs)
% mabr.ui.FilterDialog  Modal editor for the display filter chain.
%
%   p = mabr.ui.FilterDialog(p0) opens a small modal window over a
%   mabr.FilterPolicy and returns the edited policy, or [] if the user
%   cancelled.
%
%   p = mabr.ui.FilterDialog(p0,Fs) designs and draws the chain at sample
%   rate Fs (default the ADC rate of a default mabr.Config, the rate live sweeps and
%   the saved trace both live at).
%
%   The three filters are independent switches, because that is how they are
%   used at the bench: the high pass fights electrode drift, the low pass
%   fights hiss, and the notch fights whatever the mains is doing today, and
%   a rig rarely wants all three answered the same way.
%
%   The magnitude plot is the chain AS APPLIED — filtfilt runs it in both
%   directions, so the drawn response is |H|^2 and the corners read -6 dB,
%   not -3 dB. Better to draw the truth than the design.
%
%   Nothing here can damage data: the chain applies to what is DISPLAYED and
%   to the sweep metrics derived from a trace, never to the trace itself, so
%   the .abr file is raw whatever is set here. The dialog says so on its
%   face, since a filter dialog is exactly the place a user would fear
%   otherwise.
%
%   See also mabr.FilterPolicy, mabr.ui.App, mabr.ui.AcqController.
%
% Daniel Stolzberg (c) 2026

if nargin < 1 || isempty(policy0), policy0 = mabr.FilterPolicy; end
% Constructed rather than read off the class: the analysis rate is derived
% from the rig's DAC rate now (see mabr.Config), so there is no constant to
% read. A caller with an opinion passes one -- mabr.ui.App always does.
if nargin < 2 || isempty(Fs),      c = mabr.Config; Fs = c.ADCSampleRate; end

policy  = [];                       % [] unless OK is pressed
working = policy0;

% ---- layout -------------------------------------------------------------
fig = uifigure('Name','Display Filters','Position',[100 100 460 540], ...
    'WindowStyle','modal','Resize','off', ...
    'CloseRequestFcn',@(~,~) onCancel());
mabr.ui.WindowPos.restore(fig,'FilterDialog',fig.Position);

g = uigridlayout(fig,[8 4]);
g.RowHeight   = {28,28,28,28,'1x',30,18,32};
g.ColumnWidth = {110,'1x','fit','fit'};
g.Padding     = [12 10 12 10];
g.RowSpacing  = 6;

% Row 1: high pass
hpCheck = uicheckbox(g,'Text','High pass','Value',working.HighPass, ...
    'Tooltip','Removes DC offset, electrode drift, and slow movement artifact.', ...
    'ValueChangedFcn',@(~,~) onChange());
hpCheck.Layout.Row = 1; hpCheck.Layout.Column = 1;
hpField = uieditfield(g,'numeric','Value',working.HighPassHz, ...
    'Limits',[eps Fs/2],'ValueDisplayFormat','%g Hz', ...
    'Tooltip','Corner frequency. Below this the response rolls off.', ...
    'ValueChangedFcn',@(~,~) onChange());
hpField.Layout.Row = 1; hpField.Layout.Column = 2;

% Row 2: low pass
lpCheck = uicheckbox(g,'Text','Low pass','Value',working.LowPass, ...
    'Tooltip','Removes hiss and everything above the response band.', ...
    'ValueChangedFcn',@(~,~) onChange());
lpCheck.Layout.Row = 2; lpCheck.Layout.Column = 1;
lpField = uieditfield(g,'numeric','Value',working.LowPassHz, ...
    'Limits',[eps Fs/2],'ValueDisplayFormat','%g Hz', ...
    'Tooltip','Corner frequency. Above this the response rolls off.', ...
    'ValueChangedFcn',@(~,~) onChange());
lpField.Layout.Row = 2; lpField.Layout.Column = 2;

% Row 3: notch -- centre and width, since the width is the whole question
% of whether a notch is worth having (too wide and it eats the response).
nCheck = uicheckbox(g,'Text','Notch','Value',working.Notch, ...
    'Tooltip','Removes mains hum: 60 Hz here, 50 Hz on a 50 Hz supply.', ...
    'ValueChangedFcn',@(~,~) onChange());
nCheck.Layout.Row = 3; nCheck.Layout.Column = 1;
nField = uieditfield(g,'numeric','Value',working.NotchHz, ...
    'Limits',[eps Fs/2],'ValueDisplayFormat','%g Hz', ...
    'Tooltip','Centre frequency of the notch.', ...
    'ValueChangedFcn',@(~,~) onChange());
nField.Layout.Row = 3; nField.Layout.Column = 2;
nwLabel = uilabel(g,'Text','width','HorizontalAlignment','right');
nwLabel.Layout.Row = 3; nwLabel.Layout.Column = 3;
nwField = uieditfield(g,'numeric','Value',working.NotchWidthHz, ...
    'Limits',[eps Fs/2],'ValueDisplayFormat','%g Hz', ...
    'Tooltip','-3 dB width of the notch. Narrow keeps more of the response.', ...
    'ValueChangedFcn',@(~,~) onChange());
nwField.Layout.Row = 3; nwField.Layout.Column = 4;

% Row 4: shared order for the high/low pass sections
ordLabel = uilabel(g,'Text','Roll-off','HorizontalAlignment','left');
ordLabel.Layout.Row = 4; ordLabel.Layout.Column = 1;
ordDrop = uidropdown(g, ...
    'Items',arrayfun(@(n) sprintf('order %d  (%d dB/oct)',n,6*n), ...
                     mabr.FilterPolicy.Orders,'UniformOutput',false), ...
    'ItemsData',mabr.FilterPolicy.Orders, ...
    'Value',min(mabr.FilterPolicy.Orders(end),max(mabr.FilterPolicy.Orders(1), ...
                2*round(working.Order/2))), ...
    'Tooltip',['Steepness of the high- and low-pass skirts. Steeper is not ' ...
               'better on a 10 ms sweep, and a steep IIR with a 10 Hz corner ' ...
               'is numerically fragile.'], ...
    'ValueChangedFcn',@(~,~) onChange());
ordDrop.Layout.Row = 4; ordDrop.Layout.Column = [2 4];

% Row 5: the response, which is the only honest way to show what the four
% numbers above actually do to a signal.
ax = uiaxes(g);
mabr.ui.hideAxesToolbar(ax);
ax.Layout.Row = 5; ax.Layout.Column = [1 4];
ax.XScale = 'log';
ax.XLim   = [1 Fs/2];
ax.YLim   = [-60 6];
ax.Box    = 'on';
grid(ax,'on');
xlabel(ax,'Frequency (Hz)');
ylabel(ax,'Gain (dB)');
title(ax,sprintf('As applied at %g kHz (zero phase)',Fs/1e3));
respLine = line(ax,nan,nan,'Color',[0.16 0.26 0.42],'LineWidth',2);
line(ax,[1 Fs/2],[-6 -6],'Color',[0.7 0.7 0.7],'LineStyle',':');

% Row 6: what this does and does not touch
noteLbl = uilabel(g,'WordWrap','on','FontColor',[0.3 0.3 0.3], ...
    'Text',['Applies to the live plot, the trace organizer, and the sweep ' ...
            'metrics only. Saved .abr files always hold the raw trace.']);
noteLbl.Layout.Row = 6; noteLbl.Layout.Column = [1 4];

% Row 7: validation
msgLbl = uilabel(g,'Text','','FontColor',[0.8 0.2 0]);
msgLbl.Layout.Row = 7; msgLbl.Layout.Column = [1 4];

% Row 8: transport
defBtn = uibutton(g,'Text','Defaults', ...
    'Tooltip','Back to 10 Hz - 3 kHz with a 60 Hz notch.', ...
    'ButtonPushedFcn',@(~,~) onDefaults());
defBtn.Layout.Row = 8; defBtn.Layout.Column = 1;
okBtn = uibutton(g,'Text','OK','BackgroundColor',[0.6 0.9 0.6], ...
    'FontWeight','bold','ButtonPushedFcn',@(~,~) onOK());
okBtn.Layout.Row = 8; okBtn.Layout.Column = 3;
cancelBtn = uibutton(g,'Text','Cancel','ButtonPushedFcn',@(~,~) onCancel());
cancelBtn.Layout.Row = 8; cancelBtn.Layout.Column = 4;

onChange();
uiwait(fig);

% ===================== nested callbacks ==================================
    function p = readControls()
        % Built from a fresh policy rather than from the one passed in, so a
        % chain that arrived already designed cannot carry a stale design
        % out past an edit.
        p = mabr.FilterPolicy;
        p.HighPass     = hpCheck.Value;
        p.HighPassHz   = hpField.Value;
        p.LowPass      = lpCheck.Value;
        p.LowPassHz    = lpField.Value;
        p.Notch        = nCheck.Value;
        p.NotchHz      = nField.Value;
        p.NotchWidthHz = nwField.Value;
        p.Order        = ordDrop.Value;
    end

    function onChange()
        % The window can go while this is queued -- a close during the first
        % render, or a cancel arriving between a keystroke and its callback.
        % Redrawing into a deleted figure is not an error worth reporting.
        if ~isgraphics(fig), return; end
        working = readControls();

        % A switched-off section's numbers are not wrong, they are just not
        % in play -- greying them says so without hiding what they are.
        hpField.Enable  = onOff(working.HighPass);
        lpField.Enable  = onOff(working.LowPass);
        nField.Enable   = onOff(working.Notch);
        nwField.Enable  = onOff(working.Notch);
        nwLabel.Enable  = onOff(working.Notch);
        ordDrop.Enable  = onOff(working.HighPass || working.LowPass);

        [ok,msg] = working.validate(Fs);
        msgLbl.Text  = msg;
        okBtn.Enable = onOff(ok);
        if ~ok
            set(respLine,'XData',nan,'YData',nan);
            return
        end

        if working.Enabled
            [magDB,f] = working.response(Fs);
        else
            % Nothing enabled is a legitimate choice -- draw the flat line it
            % really is rather than an empty axes.
            f = [1;Fs/2]; magDB = [0;0];
        end
        set(respLine,'XData',f,'YData',magDB);
        title(ax,sprintf('%s  —  as applied at %g kHz (zero phase)', ...
            working.describe(),Fs/1e3));
    end

    function onDefaults()
        d = mabr.FilterPolicy;
        hpCheck.Value = d.HighPass;   hpField.Value = d.HighPassHz;
        lpCheck.Value = d.LowPass;    lpField.Value = d.LowPassHz;
        nCheck.Value  = d.Notch;      nField.Value  = d.NotchHz;
        nwField.Value = d.NotchWidthHz;
        ordDrop.Value = d.Order;
        onChange();
    end

    function onOK()
        % Hand back the SETTINGS, undesigned: the caller designs at whatever
        % rate it needs (AcqController at the live rate, Recording at the
        % trace's own), and a stale design travelling with the object is a
        % bug waiting for a rate change.
        policy = readControls();
        mabr.ui.WindowPos.remember(fig,'FilterDialog');
        delete(fig);
    end

    function onCancel()
        policy = [];
        mabr.ui.WindowPos.remember(fig,'FilterDialog');
        delete(fig);
    end
end

% ======================= local helpers ================================
function s = onOff(tf)
if tf, s = 'on'; else, s = 'off'; end
end

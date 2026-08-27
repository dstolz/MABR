function verify_view_prefs()
% verify_view_prefs  Confirm MABR remembers how it was left: which windows
%                    open at Start, where they sit, and how they draw.
%
%   The settings a rig arranges once and expects back next session. Three of
%   them already had their own verification (artifacts, filters, audio); this
%   covers the rest of what mabr.ui.App now recalls, and the pieces its
%   save/load configuration file carries beyond the protocol itself.
%
%   Part A (mabr.ViewPolicy): the defaults reproduce what MABR always did --
%   the live view and the trace organizer, nothing else -- opens/setOpen work
%   by name, an unknown name is tolerated rather than thrown on, and the
%   policy round-trips through both doors it travels: MATLAB prefs
%   (loadPrefs/savePrefs) and the plain struct a .mabrcfg holds
%   (toStruct/fromStruct). A pref written by hand as junk falls back to the
%   default rather than stopping the app from opening.
%   Part B (live-view look): mabr.ui.LivePlot's display settings persist --
%   layout, grouping, time base, amplitude mode and error band -- so a NEW
%   window opens the way the last one was left. Persisted from the CONTROL
%   STRIP and the right-click menu (a user choosing a look), never from a
%   property assignment (a script driving the view), which is the distinction
%   that keeps a verification script from rewriting somebody's preferences.
%   Part C (mabr.ui.WindowPos): the whole layout as one snapshot, back again
%   through applyAll, junk entries skipped one by one, and place() moving a
%   window that is already on screen.
%   Part D (analysis look): mabr.ui.MetricPlot.saveDefaults/loadDefaults, the
%   pref the configuration file carries so the next analysis window opens
%   wearing the saved one.
%
%   No hardware, no engine, no parallel pool -- but it does open a live-view
%   figure (Part B), the same way verify_live_plot does. The user's own
%   preferences are saved and restored around the whole run, so running this
%   does not disturb them.
%
%   Run:  >> verify_view_prefs
%
% Daniel Stolzberg (c) 2026

fprintf('== verify_view_prefs ==\n');

% Every pref this test writes, saved now and put back on the way out --
% including an error exit, which is what the onCleanup is for.
prefNames = [strcat('ViewOpen',mabr.ViewPolicy.names()), ...
             {'LivePlot','MetricPlot','WindowPos_VerifyViewPrefs','RestoreSession'}];
saved = save_prefs(prefNames);
restorePrefs = onCleanup(@() restore_prefs(prefNames,saved)); %#ok<NASGU>
clear_prefs(prefNames);

% ---- Part A: mabr.ViewPolicy ---------------------------------------------
v = mabr.ViewPolicy;
assert(v.LivePlot && v.TraceOrganizer, ...
    'the default policy must open the live view and the trace organizer');
assert(~v.ProgressMonitor && ~v.Analysis && ~v.StimulusViewer && ~v.Notes, ...
    'the default policy must open nothing else -- that is what MABR always did');
assert(v.count() == 2,'count() should report the two default windows');
assert(numel(mabr.ViewPolicy.names()) == numel(mabr.ViewPolicy.labels()), ...
    'every policy field needs a label for the Settings submenu');
assert(all(cellfun(@(n) isprop(v,n),mabr.ViewPolicy.names())), ...
    'names() must name real properties');

assert(v.opens('LivePlot') && ~v.opens('Analysis'),'opens() should read the fields');
assert(~v.opens('NoSuchWindow'), ...
    'an unknown window must answer false -- a configuration file may name one this MABR lacks');
v2 = v.setOpen('Analysis',true).setOpen('LivePlot',false);
assert(v2.Analysis && ~v2.LivePlot,'setOpen should return the modified copy');
assert(v.Analysis == false, ...
    'setOpen must not mutate the original -- mabr.ViewPolicy is a value object');
v3 = v2.setOpen('NoSuchWindow',true);
assert(isequal(v3,v2),'setOpen with an unknown name should be a no-op, not an error');
assert(contains(v2.summary(),'analysis'),'summary() should name what opens');
assert(contains(mabr.ViewPolicy().setOpen('LivePlot',false) ...
        .setOpen('TraceOrganizer',false).summary(),'No windows'), ...
    'summary() should say so when nothing opens automatically');

% Both doors: MATLAB prefs, and the plain struct a .mabrcfg carries.
mabr.ViewPolicy.savePrefs(v2);
assert(isequal(mabr.ViewPolicy.loadPrefs(),v2), ...
    'the policy did not survive a setpref/getpref round-trip');
assert(isequal(mabr.ViewPolicy.fromStruct(v2.toStruct()),v2), ...
    'the policy did not survive a toStruct/fromStruct round-trip');

% Forgiving, the rule every loadPrefs in MABR follows.
setpref('MABR','ViewOpenAnalysis','yes please');       % not a logical at all
loaded = mabr.ViewPolicy.loadPrefs();
assert(islogical(loaded.Analysis) && ~loaded.Analysis, ...
    'a junk pref must fall back to the property default');
partial = mabr.ViewPolicy.fromStruct(struct('ProgressMonitor',true));
assert(partial.ProgressMonitor && partial.LivePlot, ...
    'fromStruct must restore what is there and default the rest');
assert(isequal(mabr.ViewPolicy.fromStruct('not a struct'),mabr.ViewPolicy), ...
    'fromStruct must survive being handed something that is not a struct');
fprintf('  PASS Part A: which windows open at Start persists, and tolerates a bad pref\n');

% ---- Part B: the live view's look ----------------------------------------
clear_prefs({'LivePlot'});
d = mabr.ui.LivePlot.loadDefaults();
assert(strcmp(d.Layout,'overlay') && isequal(d.TimeBase,[-2 10]) ...
    && strcmp(d.AmpMode,'common') && strcmp(d.ErrorBand,'none'), ...
    'with no pref stored, loadDefaults must return the documented defaults');

lp = mabr.ui.LivePlot();
clean = onCleanup(@() delete(lp)); %#ok<NASGU>
assert(strcmp(lp.Layout,'overlay'),'a first window opens on the defaults');

% A property assignment is a SCRIPT driving the view, not a user choosing a
% look: it must change the view and leave the preference alone.
lp.Layout   = 'stacked';
lp.TimeBase = [-1 8];
assert(~ispref('MABR','LivePlot'), ...
    'setting a property must not write the preference -- only a user choice does');

% The control strip is a user choice. Drive it exactly as a click does.
lp.Layout = 'overlay';
ctrl = live_controls(lp);
ctrl.layout.Value = 4;                       % Stacked
run_callback(ctrl.layout);
ctrl.t0.String = '-3'; ctrl.t1.String = '12';
run_callback(ctrl.t0);
ctrl.amp.Value = 1;                          % Auto (each)
run_callback(ctrl.amp);
assert(strcmp(lp.Layout,'stacked') && isequal(lp.TimeBase,[-3 12]) ...
    && strcmp(lp.AmpMode,'each'),'the control strip should drive the properties');
assert(ispref('MABR','LivePlot'),'a control-strip change must be remembered');

stored = mabr.ui.LivePlot.loadDefaults();
assert(strcmp(stored.Layout,'stacked') && isequal(stored.TimeBase,[-3 12]) ...
    && strcmp(stored.AmpMode,'each'),'the stored look must be the one on screen');

% The error band lives on the right-click menu, and is remembered the same way.
band_menu(lp,'± 1 SEM');
assert(strcmp(lp.ErrorBand,'sem'),'the right-click menu should set the error band');
assert(strcmp(mabr.ui.LivePlot.loadDefaults().ErrorBand,'sem'), ...
    'an error band chosen from the menu must be remembered');

% ... and the next window opens wearing it.
lp2 = mabr.ui.LivePlot();
clean2 = onCleanup(@() delete(lp2)); %#ok<NASGU>
assert(strcmp(lp2.Layout,'stacked') && isequal(lp2.TimeBase,[-3 12]) ...
    && strcmp(lp2.AmpMode,'each') && strcmp(lp2.ErrorBand,'sem'), ...
    'a new live view must open with the settings the last one was left on');

% displaySettings/applySettings are what the configuration file travels
% through, and they are as forgiving as every other fromStruct in MABR.
s = lp2.displaySettings();
lp2.applySettings(struct('Layout','grid','TimeBase',[-2 6]));
assert(strcmp(lp2.Layout,'grid') && isequal(lp2.TimeBase,[-2 6]), ...
    'applySettings should restore the fields it is given');
lp2.applySettings(struct('Layout','no such layout','AmpMode','common'));
assert(strcmp(lp2.Layout,'grid'),'an invalid value must be ignored, not thrown on');
assert(strcmp(lp2.AmpMode,'common'),'... and the valid fields beside it still applied');
lp2.applySettings(s);
assert(isequal(lp2.displaySettings(),s),'the settings struct must round-trip');

% saveDefaults is the App's door for a look restored while no view is open.
mabr.ui.LivePlot.saveDefaults(struct('Layout','separate','ErrorBand','ci', ...
    'ConfidenceLevel',0.99));
back = mabr.ui.LivePlot.loadDefaults();
assert(strcmp(back.Layout,'separate') && strcmp(back.ErrorBand,'ci') ...
    && back.ConfidenceLevel == 0.99,'saveDefaults must be what loadDefaults reads');
setpref('MABR','LivePlot','not a struct at all');
assert(strcmp(mabr.ui.LivePlot.loadDefaults().Layout,'overlay'), ...
    'a corrupt pref must fall back to the defaults rather than stopping a window opening');
fprintf('  PASS Part B: the live view opens the way the last one was left\n');

% ---- Part C: the window layout as one snapshot ---------------------------
setpref('MABR','WindowPos_VerifyViewPrefs',[120 130 640 480]);
snap = mabr.ui.WindowPos.snapshot();
assert(isfield(snap,'VerifyViewPrefs'), ...
    'snapshot must key by window name, with the storage prefix dropped');
assert(isequal(snap.VerifyViewPrefs,[120 130 640 480]),'snapshot must carry the position');

setpref('MABR','WindowPos_VerifyViewPrefs',[1 1 100 100]);
n = mabr.ui.WindowPos.applyAll(snap);
assert(n >= 1,'applyAll should report what it restored');
assert(isequal(getpref('MABR','WindowPos_VerifyViewPrefs'),[120 130 640 480]), ...
    'applyAll must put the saved layout back');

% One bad entry costs itself and nothing else.
n = mabr.ui.WindowPos.applyAll(struct('VerifyViewPrefs',[10 10 300 200], ...
                                      'Broken','not a position'));
assert(n == 1,'a malformed entry must be skipped, not fatal');
assert(isequal(getpref('MABR','WindowPos_VerifyViewPrefs'),[10 10 300 200]), ...
    'the good entry beside it must still be applied');
assert(isequal(mabr.ui.WindowPos.applyAll('not a struct'),0), ...
    'applyAll must survive being handed something that is not a snapshot');

% place() moves a window that is already on screen -- what loading a
% configuration does, since the point of restoring a layout is watching it
% happen rather than being told it will apply next time.
f = figure('Visible','off','Position',[400 400 300 200]);
closeFig = onCleanup(@() delete(f)); %#ok<NASGU>
setpref('MABR','WindowPos_VerifyViewPrefs',[150 160 500 400]);
mabr.ui.WindowPos.place(f,'VerifyViewPrefs');
assert(isequal(f.Position,mabr.ui.WindowPos.clampToScreen([150 160 500 400])), ...
    'place() must move an open window onto its remembered position');
fprintf('  PASS Part C: the whole layout snapshots, restores, and reaches open windows\n');

% ---- Part D: the analysis window's look ----------------------------------
clear_prefs({'MetricPlot'});
d = mabr.ui.MetricPlot.loadDefaults();
assert(strcmp(d.Metric,'rms') && strcmp(d.PlotType,'auto'), ...
    'with no pref stored, an analysis window opens on the documented defaults');

d.Metric   = 'p2p';
d.PlotType = 'bar';
d.Style.Theme = 'dark';
mabr.ui.MetricPlot.saveDefaults(d);
back = mabr.ui.MetricPlot.loadDefaults();
assert(strcmp(back.Metric,'p2p') && strcmp(back.PlotType,'bar') ...
    && strcmp(back.Style.Theme,'dark'), ...
    'the analysis look a configuration carries must survive saveDefaults/loadDefaults');
fprintf('  PASS Part D: the analysis window opens wearing the saved look\n');

fprintf('== verify_view_prefs PASSED ==\n');
end

% =========================================================================
function s = save_prefs(names)
s = struct('name',{},'value',{});
for i = 1:numel(names)
    if ispref('MABR',names{i})
        s(end+1) = struct('name',names{i},'value',getpref('MABR',names{i})); %#ok<AGROW>
    end
end
end

function restore_prefs(names,s)
% Put back exactly what was there: the saved value where there was one, and
% no pref at all where there was none -- a test that leaves its own
% scribbles behind in the user's preferences has changed the thing it was
% checking.
had = {s.name};
for i = 1:numel(had)
    setpref('MABR',had{i},s(i).value);
end
for i = 1:numel(names)
    if ~any(strcmp(names{i},had)) && ispref('MABR',names{i})
        rmpref('MABR',names{i});
    end
end
end

function clear_prefs(names)
for i = 1:numel(names)
    if ispref('MABR',names{i}), rmpref('MABR',names{i}); end
end
end

function c = live_controls(lp)
% The control strip, reached the way verify_live_plot reaches it: by the
% uicontrols themselves rather than through a private property.
c = struct();
p = findall(lp.Figure,'Type','uipanel');
h = findall(p,'Type','uicontrol');
pop  = h(strcmp(get(h,'Style'),'popupmenu'));
edit = h(strcmp(get(h,'Style'),'edit'));
% findall returns children in reverse creation order; put them back in the
% order the strip was built (layout, group, amp) and (t0, t1, manual).
pop  = flipud(pop(:));
edit = flipud(edit(:));
c.layout = pop(1);
c.group  = pop(2);
c.amp    = pop(3);
c.t0     = edit(1);
c.t1     = edit(2);
c.manual = edit(3);
end

function run_callback(h)
cb = get(h,'Callback');
cb(h,[]);
end

function band_menu(lp,label)
% Click one entry of the live view's right-click Error band menu.
item = findall(lp.Figure,'Type','uimenu','Label',label);
assert(~isempty(item),'no "%s" entry on the error-band menu',label);
cb = get(item(1),'Callback');
cb(item(1),[]);
end

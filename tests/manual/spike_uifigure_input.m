function spike_uifigure_input()
% spike_uifigure_input  Which uifigure callbacks fire, in which order, for typing and clicking.
%
%   A MANUAL check, run once by a person on R2021b (MABR's floor) and once on
%   the release in use (R2025a), to confirm what the analysis app's key
%   routing assumes about uifigures (mabr.ui.AnalysisApp.dispatchKey,
%   mabr.ui.analysis.Compat). It is not a verify_* test and nothing runs it
%   automatically: it needs a person at the keyboard.
%
%       >> spike_uifigure_input
%
%   It opens one window holding an edit field, a table with an editable
%   column, a tree, and a classic axes in a panel -- the four kinds of thing
%   the analysis app's keys have to tell apart -- and prints one line per
%   callback to the Command Window: the time, the callback, the key or value,
%   and the figure's CurrentObject. Follow the steps it prints, then paste the
%   Command Window into the issue or the notes:
%
%     1. Click the edit field and type  abc  then Enter.
%        Does WindowKeyPressFcn fire for each letter (it must, for the note
%        editor to suspend the commands), and before or after
%        ValueChangingFcn?
%     2. Double-click a cell of the editable "Note" column, type  xy , Enter.
%        Which of CellEditCallback / CellSelectionCallback /
%        SelectionChangedFcn fire, and does WindowKeyPressFcn see the keys?
%     3. Click a tree node, then press the Down and Up arrows.
%        Does the tree move its selection natively, does SelectionChangedFcn
%        fire per step, and does WindowKeyPressFcn see the arrows?
%     4. Click inside the axes, then press  a  and the Left arrow.
%        Does WindowButtonDownFcn report the axes (HitObject or
%        CurrentObject), and does WindowKeyPressFcn see both keys?
%     5. With the axes clicked, press Alt+Left and Shift+Left.
%        What do Key and Modifier read (and does Alt open the menu bar)?
%     6. Close the window: the summary of what fired is printed.
%
%   See also mabr.ui.AnalysisApp, mabr.ui.analysis.Compat
%
% Daniel Stolzberg (c) 2026

counts = containers.Map('KeyType','char','ValueType','double');
t0 = tic;

fig = uifigure('Name','MABR spike: uifigure input','Position',[200 200 900 560]);
fig.WindowKeyPressFcn   = @(s,e) note('WindowKeyPressFcn',keyText(e),s);
fig.WindowKeyReleaseFcn = @(s,e) note('WindowKeyReleaseFcn',keyText(e),s);
fig.KeyPressFcn         = @(s,e) note('figure KeyPressFcn',keyText(e),s);
fig.WindowButtonDownFcn = @(s,e) note('WindowButtonDownFcn',hitText(s,e),s);
fig.CloseRequestFcn     = @(s,~) finish(s);
uimenu(fig,'Text','&File');      % a menu bar, so Alt has something to open

g = uigridlayout(fig,[2 2],'RowHeight',{'1x','1x'},'ColumnWidth',{'1x','1x'});

p1 = uipanel(g,'Title','1  Edit field');
g1 = uigridlayout(p1,[2 1],'RowHeight',{30,'1x'});
ed = uieditfield(g1,'text','Value','');
ed.ValueChangedFcn = @(s,e) note('EditField ValueChangedFcn',string(e.Value),fig);
try
    ed.ValueChangingFcn = @(s,e) note('EditField ValueChangingFcn',string(e.Value),fig);
catch
    note('setup','EditField has no ValueChangingFcn on this release',fig);
end

p2 = uipanel(g,'Title','2  Table (Note column editable)');
g2 = uigridlayout(p2,[1 1]);
tb = uitable(g2,'Data',table(["8 kHz";"16 kHz";"32 kHz"],[35;45;80],["";"";""], ...
    'VariableNames',{'Series','Final','Note'}),'ColumnEditable',[false false true]);
tb.CellEditCallback      = @(s,e) note('Table CellEditCallback',string(e.NewData),fig);
tb.CellSelectionCallback = @(s,e) note('Table CellSelectionCallback',mat2str(e.Indices),fig);
try
    tb.SelectionChangedFcn = @(s,e) note('Table SelectionChangedFcn','',fig);
catch
    note('setup','Table has no SelectionChangedFcn on this release',fig);
end

p3 = uipanel(g,'Title','3  Tree');
g3 = uigridlayout(p3,[1 1]);
tr = uitree(g3);
for s = ["SUBJ-ID-1254","SUBJ-ID-959"]
    n = uitreenode(tr,'Text',char(s));
    for d = ["Baseline","2weeks"]
        uitreenode(n,'Text',char(d));
    end
    expand(n);
end
tr.SelectionChangedFcn = @(s,e) note('Tree SelectionChangedFcn',string(e.SelectedNodes(1).Text),fig);
try
    tr.DoubleClickedFcn = @(s,e) note('Tree DoubleClickedFcn','',fig);
catch
    note('setup','Tree has no DoubleClickedFcn on this release (R2022b+)',fig);
end

p4 = uipanel(g,'Title','4  Classic axes');
ax = axes(p4,'Units','normalized','Position',[0.1 0.15 0.85 0.75]);
plot(ax,linspace(0,10,200),sin(linspace(0,10,200)),'PickableParts','none');
ax.ButtonDownFcn = @(s,e) note('axes ButtonDownFcn',sprintf('x=%.2f',e.IntersectionPoint(1)),fig);
try
    disableDefaultInteractivity(ax);
catch
end

fprintf('\n== spike_uifigure_input (%s) ==\n',version);
fprintf(['Steps: 1 type abc+Enter in the edit field; 2 edit a Note cell; 3 click a tree node, ' ...
    'then Down/Up; 4 click the axes, press a and Left; 5 Alt+Left, Shift+Left; 6 close.\n\n']);

    function note(what,detail,f)
        if isKey(counts,what), counts(what) = counts(what) + 1; else, counts(what) = 1; end
        cur = '';
        try
            co = f.CurrentObject;
            if ~isempty(co), cur = class(co); end
        catch
        end
        fprintf('%7.3f  %-30s %-24s current=%s\n',toc(t0),what,char(detail),cur);
    end

    function finish(f)
        fprintf('\n-- what fired --\n');
        k = keys(counts);
        for i = 1:numel(k)
            fprintf('%-30s %d\n',k{i},counts(k{i}));
        end
        delete(f);
    end
end

function s = keyText(e)
mods = '';
try
    mods = strjoin(e.Modifier,'+');
catch
end
ch = '';
try
    ch = e.Character;
catch
end
s = sprintf('Key=%s Mod=%s Char=%s',e.Key,mods,ch);
end

function s = hitText(f,e)
s = '';
try
    if isprop(e,'HitObject'), s = ['hit=' class(e.HitObject)]; return; end
catch
end
try
    s = ['current=' class(f.CurrentObject)];
catch
end
end

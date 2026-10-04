classdef ChangeData < event.EventData
% mabr.ui.analysis.ChangeData  What changed, for a listener of mabr.ui.analysis.Model.
%
%   Every Model event (RootChanged, ProjectChanged, SessionChanged,
%   ResultsChanged, SelectionChanged, SettingsChanged, StatusChanged,
%   BusyChanged) carries one of these, so a view can decide how much to redraw
%   from the event alone -- without asking the Model what it did:
%
%       addlistener(model,'ResultsChanged',@(~,e) view.refresh(e.What,e.Keys));
%
%   What    one word from a fixed vocabulary: "all", "files", "rejection",
%           "detection", "measures", "thresholds", "curation", "peaks",
%           "labels", "columns", "pools", "status", "save", "message",
%           "queue", "condition", "series", "level", "wave", "sweeps",
%           "busy", "idle". "all" means rebuild; a narrower word names the
%           part of the results (or of the selection) that moved.
%   Keys    string column: the condition, series or session keys concerned;
%           EMPTY means all of them (never "none").
%   Text    a sentence for the status line ("" when there is nothing to say).
%           A curation command puts its own echo here -- "Accepted fit 34.9 dB
%           for Tone 8 kHz (was manual 40) -- Ctrl+Z to undo" -- so the window
%           shows what happened without the Model owning a status bar.
%   Level   0 information, 1 warning, 2 error (colours the status line).
%   Origin  the Model method that raised the event ("acceptFit", ...), for
%           diagnostics and tests that record the order of events. (The
%           constructor takes it as Source=..., the contract's name; the
%           property cannot be called Source, which event.EventData already
%           defines as the object that raised the event -- the Model.)
%
%   A value object in all but name: listeners only read it.
%
%   See also mabr.ui.analysis.Model, mabr.ui.analysis.View
%
% Daniel Stolzberg (c) 2026

    properties
        What   (1,1) string = "all"
        Keys   (:,1) string = strings(0,1)
        Text   (1,1) string = ""
        Level  (1,1) double = 0
        Origin (1,1) string = ""
    end

    properties (Constant)
        % The words What may hold. A view switching on What can rely on
        % nothing else ever arriving.
        Vocabulary = ["all","files","rejection","detection","measures", ...
            "thresholds","curation","peaks","labels","columns","pools", ...
            "status","save","message","queue","condition","series","level", ...
            "wave","sweeps","busy","idle"]
    end

    methods
        function obj = ChangeData(what,opts)
            % ChangeData(what,Keys=..,Text=..,Level=..,Source=..)
            %
            %   what  one word of Vocabulary (default "all"); anything else
            %         errors mabr:ui:analysis:ChangeData:badWhat, because a
            %         listener switching on What would silently ignore it
            arguments
                what (1,1) string = "all"
                opts.Keys = strings(0,1)
                opts.Text (1,1) string = ""
                opts.Level (1,1) double = 0
                opts.Source (1,1) string = ""
            end
            if ~any(what == mabr.ui.analysis.ChangeData.Vocabulary)
                error('mabr:ui:analysis:ChangeData:badWhat', ...
                    '"%s" is not a ChangeData word (see ChangeData.Vocabulary).',what);
            end
            obj.What   = what;
            k = string(opts.Keys);
            obj.Keys   = reshape(k(~ismissing(k)),[],1);
            obj.Text   = opts.Text;
            obj.Level  = opts.Level;
            obj.Origin = opts.Source;
        end
    end
end

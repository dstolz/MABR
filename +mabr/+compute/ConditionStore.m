classdef ConditionStore
% mabr.compute.ConditionStore  The per-condition sweep table the online
% analysis is computed over.
%
%   A "condition" is one stimulus ID with every artifact-clean sweep so far
%   recorded for it, the time base of those sweeps, and the informative
%   parameters that place it on an axis. The store is a plain struct array of
%   them -- a value, so a copy of it can travel to a worker or sit in a window
%   without either owning the other -- and this class is the set of static
%   functions that build one, add to one, and merge two:
%
%       C = mabr.compute.ConditionStore.empty();
%       C = ConditionStore.merge(C,ConditionStore.fromBlock(block));
%       L = ConditionStore.fromLive(snap,stimuli);
%       A = ConditionStore.conditions(C,L);        % what a metric sees
%
%   Lifted whole from mabr.ui.MetricPlot, which used to hold these as private
%   statics, so that the window and the metrics worker build their tables by
%   the same rules. Two rules are load-bearing:
%
%     * merge() ACCUMULATES: a repeat or make-up run of a stimulus already in
%       the store adds its sweeps to that condition rather than replacing it,
%       because it is more data for the same condition. A different sweep
%       length means the window or the rate changed underneath, and then the
%       newest wins.
%     * conditions() lets a LIVE condition override the finalized one of the
%       same stimulus, so the point on the plot is the run in progress while
%       there is one, and the authoritative block once there is not.
%
%   Fields of a condition: Key (the stimulus ID), Label, Params (struct of
%   informative parameters, numeric scalars), Sweeps [nSamples x nSweeps]
%   volts, Time [nSamples x 1] s re onset, SampleRate, NumTotal (sweeps
%   acquired, rejected ones included), NumArtifacts, Live.
%
%   See also mabr.compute.evaluateJobs, mabr.metrics.online.context,
%   mabr.ui.MetricPlot.
%
% Daniel Stolzberg (c) 2019-2026

    methods (Static)
        function s = empty()
            s = struct('Key',{},'Label',{},'Params',{},'Sweeps',{},'Time',{}, ...
                       'SampleRate',{},'NumTotal',{},'NumArtifacts',{},'Live',{});
        end

        function c = newCondition()
            c = struct('Key','','Label','','Params',struct(),'Sweeps',[], ...
                       'Time',[],'SampleRate',1,'NumTotal',0,'NumArtifacts',0, ...
                       'Live',false);
        end

        function store = merge(store,c)
            % Same stimulus, same sweep length -> the sweeps ACCUMULATE: a
            % make-up or repeat run is more data for that condition, not a
            % replacement. A different sweep length means the window or the
            % rate changed under it, and the newest wins.
            j = [];
            if ~isempty(store), j = find(strcmp({store.Key},c.Key),1); end
            if isempty(j)
                if isempty(store), store = c; else, store(end+1) = c; end
                return
            end
            if size(store(j).Sweeps,1) == size(c.Sweeps,1)
                store(j).Sweeps       = [store(j).Sweeps c.Sweeps];
                store(j).NumTotal     = store(j).NumTotal + c.NumTotal;
                store(j).NumArtifacts = store(j).NumArtifacts + c.NumArtifacts;
                store(j).Params       = c.Params;
                store(j).Live         = false;
            else
                store(j) = c;
            end
        end

        function c = fromBlock(block)
            % One finalized mabr.data.Block as a condition, or [] when it has
            % no clean sweeps to contribute.
            c = [];
            if isempty(block), return; end
            adc = block.ADC;
            sw  = double(adc.CleanSweepData);      % [nSamples x nCleanSweeps]
            if isempty(sw), return; end

            c = mabr.compute.ConditionStore.newCondition();
            c.Key          = mabr.compute.ConditionStore.blockKey(block);
            c.Label        = c.Key;
            c.Params       = mabr.compute.ConditionStore.blockParams(block);
            c.Sweeps       = sw;
            c.Time         = double(adc.TimeVector(:));   % s, starts at the onset
            c.SampleRate   = adc.SampleRate;
            c.NumTotal     = adc.NumSweeps;
            c.NumArtifacts = adc.NumArtifacts;
            c.Live         = false;
        end

        function L = fromLive(snap,stimuli)
            % The run in progress as conditions, from an
            % AcqController.liveSnapshot payload ([] -> none). The snapshot
            % always describes ONE run, and only while it is streaming, so
            % this builds a fresh table every time rather than accumulating:
            % the finalized block is where accumulation happens. `stimuli`
            % (a mabr.stim.StimulusSet, or []) supplies the parameters.
            L = mabr.compute.ConditionStore.empty();
            if isempty(snap) || ~isstruct(snap) || ~isfield(snap,'Sweeps') ...
                    || isempty(snap.Sweeps)
                return
            end

            S   = double(snap.Sweeps).';           % [nSamples x nSweeps]
            t   = double(snap.Time(:));            % s, may start negative
            idx = double(snap.StimIndex(:)).';
            bad = logical(snap.Bad(:)).';
            n   = min([size(S,2) numel(idx) numel(bad)]);
            if n < 1, return; end
            S = S(:,1:n); idx = idx(1:n); bad = bad(1:n);

            for k = 1:numel(snap.Stimuli)
                u    = snap.Stimuli(k);
                mine = idx == u;
                if ~any(mine), continue; end
                keep = mine & ~bad;

                c = mabr.compute.ConditionStore.newCondition();
                if k <= numel(snap.Labels)
                    c.Key = char(snap.Labels{k});
                else
                    c.Key = sprintf('stimulus %d',u);
                end
                c.Label        = c.Key;
                c.Params       = mabr.compute.ConditionStore.liveParams(stimuli,u);
                c.Sweeps       = S(:,keep);
                c.Time         = t;
                c.SampleRate   = snap.SampleRate;
                c.NumTotal     = nnz(mine);
                c.NumArtifacts = nnz(mine & bad);
                c.Live         = true;

                if isempty(L), L = c; else, L(end+1) = c; end %#ok<AGROW>
            end
        end

        function C = conditions(blocks,live)
            % Every condition a metric would be computed over, a live one
            % overriding the finalized data of the same stimulus. The merge
            % rule lives here alone, so the plot, the export, the worker and
            % the tests agree.
            C = blocks;
            for i = 1:numel(live)
                j = [];
                if ~isempty(C), j = find(strcmp({C.Key},live(i).Key),1); end
                if isempty(j)
                    if isempty(C), C = live(i); else, C(end+1) = live(i); end %#ok<AGROW>
                else
                    C(j) = live(i);
                end
            end
        end

        function p = liveParams(stimuli,u)
            % The informative parameters of stimulus u, for a condition with no
            % Block yet. `stimuli` is a mabr.stim.StimulusSet, or -- on a
            % worker, which has no bank -- a cell of the bank's meta structs
            % indexed by stimulus (what mabr.compute.Cmd.RunStart carries).
            % Guarded: a bank swapped under a running window costs the point
            % its parameters, not the window.
            p = struct();
            if isempty(stimuli), return; end
            try
                if iscell(stimuli)
                    p = mabr.compute.ConditionStore.metaParams(stimuli{u});
                else
                    p = mabr.compute.ConditionStore.metaParams(stimuli.meta(u));
                end
            catch %#ok<CTCH>
            end
        end

        function k = blockKey(block)
            k = '';
            if isfield(block.Stim,'Meta') && isfield(block.Stim.Meta,'ID')
                k = char(string(block.Stim.Meta.ID));
            end
            if isempty(k), k = 'stimulus'; end
        end

        function p = blockParams(block)
            p = struct();
            if isfield(block.Stim,'Meta')
                p = mabr.compute.ConditionStore.metaParams(block.Stim.Meta);
            end
        end

        function p = metaParams(m)
            % The declared informative parameters, numeric scalars only -- they
            % are what an axis can be made of. Everything else in the metadata
            % is still on the Block; it just cannot be plotted against.
            p = struct();
            if ~isstruct(m) || ~isfield(m,'informativeParams'), return; end
            names = cellstr(m.informativeParams);
            for k = 1:numel(names)
                f = names{k};
                if isfield(m,f) && isnumeric(m.(f)) && isscalar(m.(f))
                    p.(matlab.lang.makeValidName(f)) = double(m.(f));
                end
            end
        end

        function names = paramNames(C)
            % Every parameter any condition carries, in first-seen order -- so
            % Frequency stays ahead of Level if that is how the bank lists them.
            names = {};
            for i = 1:numel(C)
                f = fieldnames(C(i).Params);
                for k = 1:numel(f)
                    if ~any(strcmp(f{k},names)), names{end+1} = f{k}; end %#ok<AGROW>
                end
            end
        end

        function v = paramValue(c,name)
            if isfield(c.Params,name) && isnumeric(c.Params.(name)) ...
                    && isscalar(c.Params.(name))
                v = double(c.Params.(name));
            else
                v = NaN;
            end
        end

        function keys = roster(C)
            % The condition keys in table order -- what a published column
            % index refers to.
            keys = {C.Key};
        end
    end
end

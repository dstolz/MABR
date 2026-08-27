function [runs,pols] = normalize(out,ctx,quiet)
% mabr.stim.strategy.normalize  Turn whatever a custom strategy returned into
% the canonical run list mabr.stim.Schedule holds.
%
%   [runs,pols] = mabr.stim.strategy.normalize(out,ctx) accepts any of the
%   return shapes below and produces {1 x nRuns} cells of row vectors: RUNS
%   of stimulus indices in play order, and POLS of the +1/-1 applied at each
%   of those onsets. It throws with an mabr:stim:strategy:* identifier when
%   the return cannot be read as a plan at all.
%
%   ACCEPTED RETURN SHAPES. Write whichever is least effort for your design:
%
%     seq                     a numeric vector -> ONE run of those stimuli,
%                             in that order. The common case.
%     {seq1,seq2,...}         a cell of numeric vectors -> that many runs, in
%                             that order. Use it to split a session into
%                             blocks the operator can stop between.
%     struct('Runs',...)      .Runs is either of the above, and the optional
%                             .Polarities mirrors its shape. Use it only when
%                             you want to place polarity yourself.
%
%   An empty return (or a plan whose runs are all empty) is a plan with
%   nothing in it, not an error: a strategy is allowed to conclude there is
%   nothing to present, and Schedule.build treats it as it treats zero
%   repetitions.
%
%   POLARITY IS ASSIGNED FOR YOU unless you supply it. The k-th presentation
%   of an entry flagged alternatePolarity gets +1 for odd k and -1 for even k,
%   counted ACROSS THE WHOLE PLAN rather than restarted per run -- so an entry
%   presented across several runs still ends up balanced between the two
%   polarities, which is the entire reason for alternating them (an unbalanced
%   split leaves exactly the stimulus artifact the alternation is meant to
%   cancel). This reproduces the built-in strategies' polarity exactly, so a
%   custom reordering of a blocked or cycled plan gets the same signs it would
%   have got from the built-in. Supply .Polarities only if you need otherwise;
%   they are then taken at face value, checked for shape and for being +/-1.
%
%   THE ONE INVARIANT is checked here and WARNED about, not enforced: a plan
%   presenting entry i a different number of times than ctx.repetitions(i)
%   logs a critical line naming the entries and the difference, and is then
%   used as returned. Departing deliberately is a legitimate reason to write a
%   strategy; doing it by accident is by far the more common one, and a plan
%   that quietly presented 300 sweeps where 512 were asked for is a session
%   the operator would rather have been told about while it could still be
%   fixed. Structural mistakes -- an index off the end of the bank, a
%   non-integer, a polarity that is not +/-1 -- are errors, because no design
%   intends them and none of them can be presented at all.
%
%   normalize(out,ctx,true) suppresses that warning, which is what
%   mabr.stim.strategy.validate passes: a strategy being checked at selection
%   time has not been asked to present anything yet, so a line about what it
%   would have presented is noise rather than news.
%
%   See also mabr.stim.strategy.context, mabr.stim.strategy.validate,
%   mabr.stim.strategy.custom_template.
%
% Daniel Stolzberg (c) 2019-2026

if nargin < 3 || isempty(quiet), quiet = false; end
n = ctx.numStimuli;

% --- Unpack the return into runs + (optional) polarities -----------------
supplied = {};
if isstruct(out)
    assert(isscalar(out) && isfield(out,'Runs'),'mabr:stim:strategy:shape', ...
        ['A struct return must be a 1x1 struct with a Runs field ' ...
         '(optionally Polarities). See mabr.stim.strategy.normalize.']);
    runs = out.Runs;
    if isfield(out,'Polarities'), supplied = out.Polarities; end
else
    runs = out;
end

runs     = asCells(runs,'Runs');
supplied = asCells(supplied,'Polarities');

assert(isempty(supplied) || numel(supplied) == numel(runs), ...
    'mabr:stim:strategy:polarityCount', ...
    'Returned %d run(s) but %d polarity vector(s); they must correspond.', ...
    numel(runs),numel(supplied));

% --- Check the sequences, and drop runs with nothing in them -------------
% An empty run would prep and stream a block of pure silence, which is not
% what any strategy means by returning one.
keep = true(1,numel(runs));
for r = 1:numel(runs)
    v = runs{r};
    assert(isnumeric(v) || islogical(v),'mabr:stim:strategy:runType', ...
        'Run %d is %s; a run must be a numeric vector of stimulus indices.', ...
        r,class(v));
    v = double(v(:))';
    if isempty(v), keep(r) = false; runs{r} = zeros(1,0); continue, end
    assert(all(isfinite(v)) && all(v == round(v)), ...
        'mabr:stim:strategy:runIndex', ...
        'Run %d holds a non-integer or non-finite stimulus index.',r);
    bad = v < 1 | v > n;
    assert(~any(bad),'mabr:stim:strategy:runRange', ...
        ['Run %d references stimulus %d, but the bank holds %d entries ' ...
         '(indices are 1-based, into the bank the context described).'], ...
        r,v(find(bad,1)),n);
    runs{r} = v;
end
runs = runs(keep);
if ~isempty(supplied), supplied = supplied(keep); end

% --- Polarity ------------------------------------------------------------
pols = cell(1,numel(runs));
if isempty(supplied)
    % Occurrence-counted across the plan -- see the header.
    seen = zeros(1,n);
    for r = 1:numel(runs)
        v = runs{r};
        p = ones(1,numel(v));
        for k = 1:numel(v)
            i       = v(k);
            seen(i) = seen(i) + 1;
            if ctx.alternatePolarity(i) && mod(seen(i),2) == 0, p(k) = -1; end
        end
        pols{r} = p;
    end
else
    for r = 1:numel(runs)
        p = supplied{r};
        assert(isnumeric(p) || islogical(p),'mabr:stim:strategy:polarityType', ...
            'Polarity %d is %s; it must be a numeric vector of +1/-1.',r,class(p));
        p = double(p(:))';
        assert(numel(p) == numel(runs{r}),'mabr:stim:strategy:polarityLength', ...
            'Polarity %d has %d entries but run %d has %d presentations.', ...
            r,numel(p),r,numel(runs{r}));
        assert(all(p == 1 | p == -1),'mabr:stim:strategy:polarityValue', ...
            'Polarity %d holds a value other than +1 or -1.',r);
        pols{r} = p;
    end
end

% --- The invariant: warn, never refuse -----------------------------------
if quiet, return, end
if ~isempty(runs)
    got = accumarray([runs{:}]',1,[n 1])';
else
    got = zeros(1,n);
end
want = ctx.repetitions(:)';
off  = find(got ~= want);
if ~isempty(off)
    show = off(1:min(4,numel(off)));
    txt  = strjoin(arrayfun(@(i) sprintf('#%d %s: %d of %d',i, ...
        char(string(ctx.IDs{i})),got(i),want(i)),show,'UniformOutput',false),'; ');
    if numel(off) > numel(show), txt = [txt sprintf('; +%d more',numel(off)-numel(show))]; end
    mabr.log.vprintf(0,1, ...
        ['Custom strategy presents %d of %d entries a different number of times ' ...
         'than scheduled (%s). Using the plan as returned -- if that was not ' ...
         'intended, the sequence is wrong.'],numel(off),n,txt);
end
end

function c = asCells(v,what)
% A vector becomes one cell; a cell array is taken as given. Anything else is
% neither a sequence nor a list of them.
if isempty(v) && ~iscell(v), c = {}; return, end
if iscell(v)
    c = reshape(v,1,[]);
else
    assert(isvector(v) || isempty(v),'mabr:stim:strategy:shape', ...
        '%s must be a vector or a cell array of vectors, not a %s array.', ...
        what,mat2str(size(v)));
    c = {v};
end
end

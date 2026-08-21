function verify_custom_advance()
% verify_custom_advance  The custom advance-function contract: the canonical
%                        context, the conformance validator, the stereotype
%                        template, and a user function selected from a file
%                        driving a real early stop.
%
%   Part A (context): mabr.stim.advance.context merges tuning parameters with
%   live metrics into the one struct every criterion is called under, with the
%   live metric winning over a same-named parameter.
%
%   Part B (validate): mabr.stim.advance.validate accepts the two supplied
%   criteria and the template, and rejects the ways a custom function can be
%   wrong — not a handle, errors on a context field, or returns a non-scalar.
%
%   Part C (template): mabr.stim.advance.custom_template fires on the same
%   logic it documents (a correlation floor, a sweep floor, a hard cap).
%
%   Part D (end-to-end): resolve a custom function FROM A FILE the way the GUI
%   does (folder onto the path, str2func by name, validate), hand it to a real
%   mabr.ui.AcqController in TESTING loopback, and confirm the run it drives
%   stops early — the whole point of letting a user supply their own criterion.
%
%   Requires the Parallel Computing Toolbox (Part D only). Run:
%       >> verify_custom_advance
%
% Daniel Stolzberg (c) 2026

fprintf('== verify_custom_advance ==\n');

% ---- Part A: canonical context -----------------------------------------
params = struct('targetSweeps',512,'corrThreshold',0.5,'minSweeps',32, ...
                'maxSweeps',Inf,'myKnob',7);
live   = struct('numSweeps',64,'numTotal',70,'numArtifacts',6, ...
                'corr',0.42,'elapsedSeconds',3.2);
ctx = mabr.stim.advance.context(params,live);
for f = {'targetSweeps','corrThreshold','minSweeps','maxSweeps','myKnob', ...
         'numSweeps','numTotal','numArtifacts','corr','elapsedSeconds'}
    assert(isfield(ctx,f{1}),'context missing documented field %s',f{1});
end
assert(ctx.numSweeps == 64,'live metric did not override');
assert(ctx.myKnob == 7,'a custom parameter did not pass through');
% A same-named field in live must win over the parameter.
ctx2 = mabr.stim.advance.context(struct('corr',0),struct('corr',0.9));
assert(ctx2.corr == 0.9,'live metric must win over a same-named parameter');
% An empty/absent live argument is tolerated (params passed straight through).
ctx3 = mabr.stim.advance.context(params,[]);
assert(ctx3.myKnob == 7 && ~isfield(ctx3,'corr'),'empty live should leave params alone');
fprintf('  PASS Part A: context merges params and live metrics\n');

% ---- Part B: conformance validator -------------------------------------
assert(mabr.stim.advance.validate(@mabr.stim.advance.num_sweeps));
assert(mabr.stim.advance.validate(@mabr.stim.advance.corr_threshold));
assert(mabr.stim.advance.validate(@mabr.stim.advance.custom_template));
assert(mabr.stim.advance.validate(@(c) c.corr >= c.corrThreshold), ...
    'a well-formed anonymous criterion should validate');
assert(~mabr.stim.advance.validate(42),'a non-handle must be rejected');
assert(~mabr.stim.advance.validate(@(c) c.no_such_field_zzz), ...
    'a criterion that errors on a missing field must be rejected');
assert(~mabr.stim.advance.validate(@(c) [1 2 3]), ...
    'a non-scalar return must be rejected');
fprintf('  PASS Part B: validate accepts conforming, rejects malformed\n');

% ---- Part C: the template behaves as documented ------------------------
base = struct('minSweeps',32,'maxSweeps',Inf,'corrThreshold',0.5);
assert(~mabr.stim.advance.custom_template(setfield2(base,'numSweeps',10,'corr',0.9)), ...
    'template should not fire below minSweeps');
assert( mabr.stim.advance.custom_template(setfield2(base,'numSweeps',40,'corr',0.9)), ...
    'template should fire when count and correlation are met');
assert(~mabr.stim.advance.custom_template(setfield2(base,'numSweeps',40,'corr',0.1)), ...
    'template should not fire below the correlation threshold');
b2 = base; b2.maxSweeps = 100;
assert( mabr.stim.advance.custom_template(setfield2(b2,'numSweeps',200,'corr',0)), ...
    'template should fire at the hard cap regardless of correlation');
fprintf('  PASS Part C: custom_template fires on its documented logic\n');

% ---- Part D: a file-resolved custom function stops a run early ----------
cfg  = mabr.Config;
reps = 120;
stopAt = 20;

% Write a user criterion to a scratch folder and resolve it exactly as the
% GUI's "Custom…" picker does: put the folder on the path, str2func by name,
% and validate before trusting it.
td   = tempname; mkdir(td);
name = 'mabr_test_advance_stopat';
fid  = fopen(fullfile(td,[name '.m']),'w');
fprintf(fid,'function done = %s(ctx)\n',name);
fprintf(fid,'done = ctx.numSweeps >= %d;\n',stopAt);
fprintf(fid,'end\n');
fclose(fid);
addpath(td);
cleanPath = onCleanup(@() cleanupScratch(td));

fcn = str2func(name);
assert(mabr.stim.advance.validate(fcn),'the file-resolved criterion must validate');

ctrl = mabr.ui.AcqController(cfg,true);
cleaner = onCleanup(@() delete(ctrl)); %#ok<NASGU>
ctrl.waitUntilReady();

ctrl.setStimuli(mabr.stim.demoStimuli(cfg,'Frequencies',8,'Levels',60));
ctrl.Schedule.Strategy    = 'blocked';
ctrl.Schedule.Repetitions = reps;
ctrl.Schedule.ISI         = 1/21.1;
ctrl.Schedule.build();
ctrl.Schedule.TestingFrameDelay = 0.004;
ctrl.Window  = [0 0.01];
ctrl.Filters = mabr.FilterPolicy(false,false,false);  % criterion ignores corr; keep it simple
ctrl.AdvanceFcn    = fcn;
ctrl.AdvanceParams = struct('targetSweeps',reps,'corrThreshold',0.5, ...
                            'minSweeps',8,'maxSweeps',Inf);
ctrl.Session.OutputPath = '';

ctrl.start();
t0 = tic;
while ctrl.State ~= mabr.ui.ProgState.SchedComplete && toc(t0) < 90
    pause(0.05);
end
assert(ctrl.State == mabr.ui.ProgState.SchedComplete,'schedule did not complete');

assert(ctrl.Session.NumBlocks == 1,'expected exactly one finalized block');
n = ctrl.Session.Blocks(1).NumSweeps;
assert(n >= stopAt,'run stopped before the criterion could fire (%d sweeps)',n);
assert(n < 0.75*reps,'run did NOT stop early: %d of %d sweeps',n,reps);
fprintf('  PASS Part D: file-resolved custom criterion stopped at %d of %d sweeps\n', ...
    n,reps);

fprintf('== verify_custom_advance PASSED ==\n');
end

% =====================================================================
function s = setfield2(s,varargin)
% Set several fields at once: setfield2(s,'a',1,'b',2).
for i = 1:2:numel(varargin), s.(varargin{i}) = varargin{i+1}; end
end

function cleanupScratch(td)
rmpath(td);
try, rmdir(td,'s'); end %#ok<TRYNC>
end

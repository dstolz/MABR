function verify_loop_mode()
% verify_loop_mode  Loop: the run in progress is presented again, pass after
%                   pass, until Loop is switched off.
%
%   Part A (pure, no pool): mabr.stim.Schedule.loopRun. A pass goes directly
%   after its run and is that run again, presentation for presentation and
%   sign for sign; the rest of the plan waits behind it unchanged; the pass
%   is flagged IsLoop and nothing else;
%   a make-up run's pass is a full run of its stimulus and is not charged to
%   the make-up budget; dropPendingMakeup leaves passes alone; reset() drops
%   them; the Disabled mask drops a pass of a condition switched off; an
%   index off the plan is refused, and so is an intermixed plan -- Loop
%   holds one condition, and an intermixed run is all of them.
%
%   Part B (pure): no .abr is ever overwritten. Loop passes of one condition
%   are short enough to start within the same second, which is all the
%   filename's timestamp resolves -- so a second file of the same name lands
%   beside the first as <name>_2.abr, and the first is left as it was.
%
%   Part C (end-to-end, Test Mode loopback): with Loop set, a conventional
%   run is presented again and again -- each pass its own block and its own
%   .abr, none overwritten, all credited to the schedule -- and once Loop is
%   cleared the pass in progress finishes, the plan goes on to the next run,
%   and the schedule completes.
%
%   Part D: Advance under Loop moves on to the next run, which is then held
%   in its turn; Abort under Loop halts, and nothing is presented after it;
%   and an intermixed plan is not looped whatever Loop says (canLoop).
%
%   Part E: stimulation only loops the same way, one .stimlog per pass.
%
%   Parts C-E require the Parallel Computing Toolbox. None need hardware.
%   Run:  >> verify_loop_mode
%
% Daniel Stolzberg (c) 2026

fprintf('== verify_loop_mode ==\n');

cfg = mabr.Config;

% ---- Part A: Schedule.loopRun ---------------------------------------------
% Entries 1 and 3 alternate polarity and the counts are odd, so a pass has an
% unequal split of signs to copy and an off-by-one cannot hide.
demo = mabr.stim.demoStimuli(cfg,'Frequencies',8,'Levels',[30 45 60],'PipDuration',0.002);
ids  = demo.IDs();
raw  = struct('signal',{},'ID',{},'SampleRate',{},'alternatePolarity',{});
for i = 1:demo.numStimuli
    raw(i).signal            = demo.signal(i);
    raw(i).ID                = ids{i};
    raw(i).SampleRate        = demo.SampleRate;
    raw(i).alternatePolarity = mod(i,2) == 1;
end
bank = mabr.stim.StimulusSet(raw,cfg);

sch = mabr.stim.Schedule(bank,cfg);
sch.Strategy    = 'conventional';
sch.Repetitions = [5 4 3];
sch.build();
built    = sch.Runs;
builtPol = sch.Polarities;
assert(sch.NumRuns == 3 && isequal(sch.IsLoop,false(1,3)), ...
    'a built plan should hold three runs and no loop pass');
assert(isequal(builtPol{1},[1 -1 1 -1 1]),'test premise: run 1 alternates');

k = sch.loopRun(1);
assert(k == 2 && sch.NumRuns == 4, ...
    'the pass should go directly after its run (got run %d of %d)',k,sch.NumRuns);
assert(isequal(sch.Runs{2},built{1}) && isequal(sch.Polarities{2},builtPol{1}), ...
    'the pass must be run 1 again, presentation for presentation and sign for sign');
assert(isequal(sch.Runs([1 3 4]),built) && isequal(sch.Polarities([1 3 4]),builtPol), ...
    'the rest of the plan must wait behind the pass, unchanged and in order');
assert(isequal(sch.IsLoop,[false true false false]) && ~any(sch.IsMakeup) ...
    && ~any(sch.IsRepeat),'the pass must be flagged a loop pass and nothing else');
assert(sch.current() == 1,'inserting a pass must not move the plan');

% The plan walks onto the pass; a pass can be looped in its turn; and once
% nothing holds it the plan goes on with the run that was next.
assert(sch.advance() == 2 && all(sch.runSequence() == 1), ...
    'advance() should land on the pass');
sch.loopRun();                        % the current run, by default
assert(sch.NumRuns == 5 && isequal(sch.IsLoop,[false true true false false]), ...
    'a pass should loop like any other run');
assert(sch.advance() == 3 && all(sch.runSequence() == 1),'expected the second pass');
assert(sch.advance() == 4 && all(sch.runSequence() == 2), ...
    'after the loop the plan should go on with the run that was next');

% A make-up run holds what an artifact cost, not the condition's run: its
% pass is a full run of the stimulus, and is no charge on the make-up budget.
sch.appendMakeup([2 0 0]);
mk = sch.NumRuns;
assert(sch.IsMakeup(mk) && isequal(sch.runSequence(mk),[1 1]), ...
    'test premise: a two-presentation make-up run of stimulus 1');
used = sch.MakeupUsed(1);
while sch.current() < mk, sch.advance(); end
k = sch.loopRun(mk);
assert(k == mk+1 && isequal(sch.runSequence(k),ones(1,5)) ...
    && isequal(sch.runPolarity(k),[1 -1 1 -1 1]), ...
    'a make-up run''s pass should be a full run of its stimulus, got %s / %s', ...
    mat2str(sch.runSequence(k)),mat2str(sch.runPolarity(k)));
assert(sch.IsLoop(k) && ~sch.IsMakeup(k) && sch.MakeupUsed(1) == used, ...
    'a make-up run''s pass is a loop pass, and not charged to the make-up budget');

% Withdrawing pending make-up (Repeat cleared mid-schedule) takes the make-up
% runs and nothing else.
sch.appendMakeup([0 1 0]);
n = sch.NumRuns;
assert(sch.dropPendingMakeup() == 1 && sch.NumRuns == n-1 && sch.IsLoop(mk+1), ...
    'withdrawing pending make-up must leave a loop pass where it is');

% A user repeat is its own kind of run, and reset() drops all three kinds.
sch.repeatRun(2);
assert(sch.IsRepeat(end) && ~sch.IsLoop(end),'a repeat run is not a loop pass');
sch.reset();
assert(isequal(sch.Runs,built) && isequal(sch.Polarities,builtPol) ...
    && isequal(sch.IsLoop,false(1,3)) && sch.current() == 1, ...
    'reset() must return the plan build() produced, with no loop pass left');

% A pass is a run not yet started, so the Disabled mask (setEnabled, the
% presentation-order window) applies to it: switching the looped condition
% off ends the loop on it, and the plan goes on.
sch.loopRun(1);
sch.setEnabled(1,false);
assert(~sch.isComplete(),'the rest of the plan is still to come');
assert(sch.advance() == 2 && all(sch.runSequence() == 2) && sch.NumRuns == 3 ...
    && isequal(sch.IsLoop,false(1,3)), ...
    'a pass of a disabled condition should be dropped, and the plan go on');
sch.reset();

assert_throws(@() sch.loopRun(99),'mabr:stim:Schedule:runRange');
assert_throws(@() sch.loopRun(0), 'mabr:stim:Schedule:runRange');

% Loop holds ONE condition. An intermixed run is every condition at once, so
% an intermixed plan is refused and left as it was; a shuffled run ORDER is
% still one condition per run, and loops.
for strat = {'interleaved','interleaved-random','shuffled'}
    schI = mabr.stim.Schedule(bank,cfg);
    schI.Strategy    = strat{1};
    schI.Repetitions = [5 4 3];
    schI.Seed        = 3;
    schI.build();
    assert_throws(@() schI.loopRun(1),'mabr:stim:Schedule:loopIntermixed');
    assert(schI.NumRuns == 1 && ~any(schI.IsLoop), ...
        '%s: a refused loop must leave the plan as it was',strat{1});
end
schS = mabr.stim.Schedule(bank,cfg);
schS.Strategy    = 'conventional-shuffled';
schS.Repetitions = [5 4 3];
schS.Seed        = 3;
schS.build();
first = schS.runSequence(1);
assert(schS.loopRun(1) == 2 && isequal(schS.runSequence(2),first), ...
    'a shuffled run order still holds one condition per run, and should loop');
fprintf('  PASS Part A: a pass is its run again, inserted, flagged, dropped by reset; intermixed refused\n');

% ---- Part B: no .abr is ever overwritten ------------------------------------
stamp = char(datetime('now','Format','yyyyMMdd''T''HHmmssSSS'));
outB  = fullfile(tempdir,['mabr_loop_io_' stamp]);
mkdir(outB);
cleanB = onCleanup(@() rmdir(outB,'s'));

% Two runs of one condition stamped with the same second -- what two short
% loop passes are -- with different samples in them.
t  = '2026-09-30T10:00:00';
b1 = make_block('8kHz_60dB',8,t);
b2 = make_block('8kHz_60dB',8,t);
f1 = mabr.data.io.writeABR(b1,outB,'SUBJ_ID_42');
f2 = mabr.data.io.writeABR(b2,outB,'SUBJ_ID_42');
f3 = mabr.data.io.writeABR(b2,outB,'SUBJ_ID_42');
[~,n1,e1] = fileparts(f1);
[~,n2,e2] = fileparts(f2);
[~,n3,e3] = fileparts(f3);
assert(strcmp(n1,'SUBJ_ID_42_Frequency_8kHz_Level_60dB_260930T100000') && strcmp(e1,'.abr'), ...
    'test premise: the first file takes the ordinary name (got %s%s)',n1,e1);
assert(strcmp(n2,[n1 '_2']) && strcmp(e2,'.abr') && strcmp(n3,[n1 '_3']) && strcmp(e3,'.abr'), ...
    'a taken name should be suffixed _2, _3 after the timestamp (got %s%s, %s%s)',n2,e2,n3,e3);
A = load(f1,'-mat','ABR_Data');
B = load(f2,'-mat','ABR_Data');
S1 = mabr.data.io.buildStruct(b1);
S2 = mabr.data.io.buildStruct(b2);
assert(isequal(A.ABR_Data.ADC.Data,S1.ADC.Data), ...
    'the first file was changed by writing the second');
assert(isequal(B.ABR_Data.ADC.Data,S2.ADC.Data) && ~isequal(S1.ADC.Data,S2.ADC.Data), ...
    'the second file does not hold the second run');
assert(strcmp(A.ABR_Data.StartTime,B.ABR_Data.StartTime), ...
    'the suffix must not change the start time the file records');
assert(numel(dir(fullfile(outB,'*.abr'))) == 3,'expected three files side by side');
fprintf('  PASS Part B: a second file of the same name is written beside the first\n');

% ---- Part C: a looped run, end to end ---------------------------------------
outC = fullfile(tempdir,['mabr_loop_' stamp]);
mkdir(outC);
cleanC = onCleanup(@() rmdir(outC,'s'));

ctrl = mabr.ui.AcqController(cfg,true);          % Test Mode loopback
cleaner = onCleanup(@() delete(ctrl));
ctrl.waitUntilReady();

pair = mabr.stim.demoStimuli(cfg,'Frequencies',8,'Levels',[30 60],'PipDuration',0.002);
reps = 6;
setup(ctrl,pair,reps,false);
ctrl.Session.Subject.ID = 'SUBJ_ID_4242';
ctrl.Session.OutputPath = outC;
[id1,id2,s1,s2] = run_ids(ctrl);

assert(~ctrl.Loop,'a controller should start with Loop clear');
ctrl.Loop = true;
ctrl.start();
wait_until(@() ctrl.Session.NumBlocks >= 3,90,'three passes of run 1');
assert(ctrl.State ~= mabr.ui.ProgState.SchedComplete, ...
    'a looping schedule must not complete by itself');
ctrl.Loop = false;
wait_state(ctrl,mabr.ui.ProgState.SchedComplete,90);

got   = block_ids(ctrl,0);
nPass = sum(got == id1);
assert(nPass >= 3 && sum(got == id2) == 1 && got(end) == id2 && all(got(1:end-1) == id1), ...
    'expected run 1 held for 3+ passes, then run 2 once (got %s)',strjoin(got,', '));
assert(all([ctrl.Session.Blocks.NumSweeps] == reps), ...
    'every pass should be a whole run of %d sweeps (got %s)',reps, ...
    mat2str([ctrl.Session.Blocks.NumSweeps]));
sch = ctrl.Schedule;
assert(nnz(sch.IsLoop) == nPass-1 && sch.NumRuns == 2 + nPass-1, ...
    'the plan should hold one loop pass per extra pass (%d passes, %d flagged, %d runs)', ...
    nPass,nnz(sch.IsLoop),sch.NumRuns);
assert(sch.RunCounts(s1) == reps*nPass && sch.RunCounts(s2) == reps, ...
    'every pass should be credited to its stimulus (RunCounts %s)',mat2str(sch.RunCounts));
files = dir(fullfile(outC,'*.abr'));
assert(numel(files) == ctrl.Session.NumBlocks, ...
    '%d blocks were saved as %d .abr files -- a pass overwrote another', ...
    ctrl.Session.NumBlocks,numel(files));
fprintf('  PASS Part C: run 1 held for %d passes (%d .abr files), then the plan went on\n', ...
    nPass,numel(files));

% ---- Part D: Advance moves on under Loop; Abort halts ------------------------
ctrl.Session.OutputPath = '';                   % nothing more to check on disk
n0 = ctrl.Session.NumBlocks;
ctrl.Loop = true;
ctrl.start();                                   % reset() drops Part C's passes
wait_until(@() ctrl.Session.NumBlocks >= n0 + 2,90,'two passes of run 1');
ctrl.stopBlock();                               % Advance
wait_until(@() sum(block_ids(ctrl,n0) == id2) >= 2,90,'run 2 held for two passes');
ctrl.Loop = false;
wait_state(ctrl,mabr.ui.ProgState.SchedComplete,90);
got = block_ids(ctrl,n0);
k   = find(got == id2,1);
assert(~isempty(k) && k > 2 && all(got(1:k-1) == id1) && all(got(k:end) == id2) ...
    && numel(got) - k + 1 >= 2, ...
    'Advance should move on to run 2, which is then held (got %s)',strjoin(got,', '));

n0 = ctrl.Session.NumBlocks;
ctrl.Loop = true;
ctrl.start();
wait_until(@() ctrl.Session.NumBlocks >= n0 + 2,90,'two passes of run 1');
ctrl.abort();
wait_state(ctrl,mabr.ui.ProgState.Idle,30);
nb = ctrl.Session.NumBlocks;
pause(1);
assert(ctrl.State == mabr.ui.ProgState.Idle && ctrl.Session.NumBlocks == nb, ...
    'Abort under Loop must halt: state %s, %d block(s) after it', ...
    string(ctrl.State),ctrl.Session.NumBlocks - nb);
assert(all(block_ids(ctrl,n0) == id1),'Abort should have halted on run 1');
ctrl.Loop = false;

% An intermixed plan: Loop cannot hold it, so a Loop left set (as a script
% could) is ignored and the one run plays through to completion.
setup(ctrl,pair,reps,false,'interleaved');
assert(~ctrl.canLoop(),'an intermixed plan must not be loopable');
n0 = ctrl.Session.NumBlocks;
ctrl.Loop = true;
ctrl.start();
wait_state(ctrl,mabr.ui.ProgState.SchedComplete,90);
assert(ctrl.Schedule.NumRuns == 1 && ~any(ctrl.Schedule.IsLoop) ...
    && ctrl.Session.NumBlocks == n0 + 2, ...
    'an intermixed run must play once and not be looped (%d runs, %d blocks)', ...
    ctrl.Schedule.NumRuns,ctrl.Session.NumBlocks - n0);
ctrl.Loop = false;
fprintf('  PASS Part D: Advance moved on and the next run was held; Abort halted; intermixed not looped\n');

% ---- Part E: stimulation only -----------------------------------------------
outE = fullfile(outC,'stimonly');
nb   = ctrl.Session.NumBlocks;
setup(ctrl,pair,reps,true);
ctrl.Session.OutputPath = outE;
ctrl.Loop = true;
ctrl.start();
wait_until(@() numel(dir(fullfile(outE,'*.stimlog'))) >= 3,90,'three stimulation logs');
ctrl.Loop = false;
wait_state(ctrl,mabr.ui.ProgState.SchedComplete,90);
logs = dir(fullfile(outE,'*.stimlog'));
sch  = ctrl.Schedule;
nPass = sch.NumRuns - 1;
assert(nPass >= 3 && nnz(sch.IsLoop) == nPass-1, ...
    'run 1 should have been held for 3+ passes (%d runs, %d flagged)', ...
    sch.NumRuns,nnz(sch.IsLoop));
assert(numel(logs) == sch.NumRuns, ...
    'expected one .stimlog per pass and run (%d), found %d',sch.NumRuns,numel(logs));
assert(sch.RunCounts(s1) == reps*nPass && sch.RunCounts(s2) == reps, ...
    'every pass played should be credited (RunCounts %s)',mat2str(sch.RunCounts));
assert(ctrl.Session.NumBlocks == nb,'stimulation only must build no block');
fprintf('  PASS Part E: stimulation only held run 1 for %d passes, one .stimlog each\n',nPass);

fprintf('== verify_loop_mode PASSED ==\n');
end


% =====================================================================
function setup(ctrl,bank,reps,stimOnly,strategy)
% A two-run conventional plan (by default), paced fast: a pass is a fraction
% of a second, which is what makes same-second file names likely in Part C.
if nargin < 5, strategy = 'conventional'; end
ctrl.setStimuli(bank);
ctrl.Schedule.Strategy        = strategy;
ctrl.Schedule.Repetitions     = reps;
ctrl.Schedule.ISI             = 0.02;
ctrl.Schedule.StimulationOnly = stimOnly;
ctrl.Schedule.build();
ctrl.Schedule.TestingFrameDelay = 0.001;
end


function [id1,id2,s1,s2] = run_ids(ctrl)
% The stimulus each of the plan's two runs presents, by index and by ID.
r1 = ctrl.Schedule.runSequence(1);
r2 = ctrl.Schedule.runSequence(2);
s1 = r1(1);
s2 = r2(1);
id1 = string(ctrl.Stimuli.id(s1));
id2 = string(ctrl.Stimuli.id(s2));
end


function ids = block_ids(ctrl,from)
% The stimulus ID of every block after the first `from`, in the order the
% session received them.
B = ctrl.Session.Blocks;
B = B(from+1:end);
ids = strings(1,numel(B));
for i = 1:numel(B)
    ids(i) = string(B(i).Stim.Meta.ID);
end
end


function wait_until(cond,timeout,what)
% Let callbacks run until cond() holds.
t0 = tic;
while ~cond() && toc(t0) < timeout
    pause(0.05);
end
assert(cond(),'timed out after %g s waiting for %s',timeout,what);
end


function wait_state(ctrl,state,timeout)
t0 = tic;
while ctrl.State ~= state && toc(t0) < timeout
    pause(0.05);
end
assert(ctrl.State == state,'expected %s within %g s, still %s', ...
    string(state),timeout,string(ctrl.State));
end


function assert_throws(f,id)
try
    f();
catch me
    assert(strcmp(me.identifier,id),'expected %s, got %s: %s',id,me.identifier,me.message);
    return
end
error('verify_loop_mode:noThrow','expected %s, nothing was thrown',id);
end


function block = make_block(id,freq,startTime)
% A short synthetic block, enough to write a .abr from (after verify_notes').
Fs = 12000; df = 1;
nSweeps = 6; period = round(Fs/21.1);
N = nSweeps*period + period;
data   = 1e-9*randn(N,1);
onsets = (round(0.05*Fs) + (0:nSweeps-1)*period)';
rec  = mabr.data.Recording(Fs,data,onsets,round(0.01*Fs),df);
meta = struct('ID',id,'Frequency',freq,'Level',60, ...
              'informativeParams',{{'Frequency','Level'}}, ...
              'Label',{{sprintf('ID = %s',id),'Level = 60'}});
block = mabr.data.Block(struct('Meta',meta,'SampleRate',Fs),rec,startTime);
end

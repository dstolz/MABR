function verify_offline_script()
% verify_offline_script  ScriptWriter: exact literals and replication scripts that reproduce an analysis, no hardware.
%
%   mabr.analysis.ScriptWriter writes an analysed session -- its files and
%   exclusions, every setting, every hand edit -- as a plain MATLAB script.
%   The claim is EXACT replication, so every check below is an equality, not
%   a tolerance.
%
%   Part A  literal(): eval(literal(v)) is isequaln v (same class and size)
%           for every supported type -- doubles at full precision, NaN/Inf/
%           -Inf/-0 (the sign kept), empties at their sizes, singles, 64-bit
%           integers past 2^53, complex, sparse, logicals, char and string
%           with quotes, control characters and non-ASCII text, <missing>,
%           datetimes (NaT, time zones, the sub-millisecond part of 'now'),
%           durations, categoricals, scalar/array/empty structs, cells,
%           tables with properties and a one-row char variable, N-D arrays,
%           Settings -- in the shortest text that does it; a function handle
%           is refused
%   Part B  the script generated from a hand-built results v2 struct, run
%           with the Session calls stubbed out: setup, DATAROOT-relative
%           folders, every setting written out and its hash asserted, the
%           edit tables and expected results as written, the comparison
%           ("replicated exactly", and planted differences -- a <missing>
%           value among them -- listed, never thrown; a difference of
%           floating-point rounding alone counted as a replication, not
%           listed); a study script with two sets of settings and a skipped
%           v1 item; write() (UTF-8, folder created, a valid script name);
%           checkcode reports nothing on any generated file; refusals
%   Part C  a SyntheticABR session analysed with small permutations, then
%           edited every way (a manual rejection, a detection override, a
%           peak placed by hand and one marked absent, accepted / manual
%           level / no-response / excluded decisions): its script, run in a
%           workspace of its own on a moved copy of the data, reproduces
%           Thresholds, Conditions p/isSig/Detected, Peaks and every Rejected
%           flag isequaln, and says "replicated exactly" -- with a conduction
%           delay override of its own (A9), whose reported latencies (re sound
%           arrival) come back the same; and the same session opened from its
%           results file, re-analysed there (another threshold method, peaks
%           from the stored means), is replicated exactly too
%   Part D  the script's export equals a direct Export of the original
%           session (every CSV, readtable), the analysis time aside; the
%           raw tables (blocks, sweeps as parquet) come from the session
%           the script analysed
%   Part E  a study script over two sessions with labels and different
%           settings (one with a speaker-distance conduction delay)
%           reproduces both sessions and the thresholds table
%
%   Everything is written under one tempname folder, removed on the way out. No preference is read or written, no
%   window opened, no pool started.
%
%   Run:  >> verify_offline_script
%
%   See also mabr.analysis.ScriptWriter, mabr.analysis.Session,
%   mabr.analysis.Export, mabrtest.SyntheticABR.
%
% Daniel Stolzberg (c) 2026

fprintf('== verify_offline_script ==\n');
tAll  = tic;
figs0 = findall(groot,'Type','figure');
root  = string(tempname);
mkdir(root);
cleanup = onCleanup(@() mabrtest.SyntheticABR.rmdirQuiet(root));
W = @mabr.analysis.ScriptWriter.literal;

% =========================================================================
%  Part A -- literal() round trips
% =========================================================================
nowDt = datetime('now');
T1 = table([1;2],["a";"b"],[true;false],'VariableNames',{'x','y','ok'});
T2 = head(table([1;1],['Size';'Size'],'VariableNames',{'n','s'}),1);    % a 1-row char variable
T3 = table({1;'a'},struct('q',{1;2}),[1 2;3 4],NaT(2,1),'VariableNames',{'c','s','m','t'});
T4 = table([1;2],'VariableNames',{'x'},'RowNames',{'r1','r2'});
T4.Properties.VariableUnits = {'ms'};
T4.Properties.VariableDescriptions = {'latency'};
T4.Properties.Description = 'with properties';
T4.Properties.DimensionNames = {'Row','Vars'};
T4.Properties.UserData = struct('note',"kept");
T5 = table(strings(0,1),zeros(0,1),NaT(0,1),'VariableNames',{'Key','Value','Time'});
T6 = table([1;2],["µV";"dB SPL"],'VariableNames',{'level re thr','unit (text)'});
cases = {
    'double',          {pi, 0.1, -2.5e-12, 1e22, 123456789012345678, realmax, realmin/2^20, ...
                        [1 -2 3], [1;2;3], [1 -2; 3 4], magic(4)/7, (1:150)/7, ((1:150)/7).'}
    'special doubles', {NaN, Inf, -Inf, -0, [NaN Inf -Inf -0 0 1], NaN(3,1), -Inf(1,2), ...
                        zeros(2,3), ones(2,2), repmat(7.25,1,4), -zeros(1,3), [0 -0]}
    'empty doubles',   {[], zeros(0,1), zeros(1,0), zeros(0,3), zeros(3,0)}
    'other numeric',   {single(pi), single([1.5 NaN -0]), single.empty(0,2), int8([-128 127]), ...
                        uint8(255), int32([1 2; 3 4]), uint16(zeros(0,1)), ...
                        int64(9007199254740993), intmax('uint64'), [intmin('int64') intmax('int64')], ...
                        complex(1,-0), complex([1 2],[3 -4]), sparse([1 0; 0 2]), sparse(3,4)}
    'logical',         {true, false, [true false true], false(0,1), true(2,3), logical([1 0; 0 1]), ...
                        sparse(logical([1 0 1]))}
    'char',            {'abc', '', char(zeros(1,0)), char(zeros(0,3)), 'it''s "quoted"', ['ab';'cd'], ...
                        ['a' newline 'b'], char(9), [char(13) newline], 'µV ≤ 3 – ok', ...
                        ['ab'; ['c' newline]], repmat('x',1,300)}
    'string',          {"abc", "", "say ""hi"" and 'bye'", ["a" "b"; "c" "d"], strings(0,1), strings(1,0), ...
                        string(missing), ["x" missing], [missing missing], "µV ≤ 3 – Ωmega 日本", ...
                        "line1" + newline + "line2", ["a";"a";"a"], string(newline), ...
                        "tab" + char(9) + "bed" + char(13), "% not a comment ... nor a continuation", ...
                        ["a" + newline + "b", "c"; "d", newline + "e"], ...
                        string(compose("key%03d",(1:60)'))}
    'missing',         {missing, repmat(missing,2,2)}
    'datetime',        {datetime(2026,10,1,10,0,0), datetime(2026,10,1,10,0,0.25), NaT, NaT(2,1), ...
                        [datetime(2026,10,1) NaT], nowDt, nowDt + seconds(12345.678), ...
                        nowDt + seconds((1:5)'*0.37), datetime(2026,10,1,10,0,0,'TimeZone','UTC'), ...
                        datetime('now','TimeZone','America/New_York'), datetime.empty(0,1), ...
                        datetime(1850,3,4,5,6,7.125)}
    'duration etc.',   {milliseconds([1.5 NaN Inf]), seconds(3), minutes(zeros(0,1)), ...
                        categorical(["a","b","a"]), categorical(["lo","hi",missing],["lo","hi"],'Ordinal',true), ...
                        categorical(strings(0,1))}
    'struct',          {struct('a',1,'b',"x"), struct(), struct('c',{{1,2}}), struct('a',{1,2}), ...
                        struct('a',{1;2}), struct('a',{1,2;3,4}), struct('a',cell(1,0)), struct('a',{}), ...
                        repmat(struct(),0,1), repmat(struct(),2,1), struct('s',struct('t',{1,2})), ...
                        struct('t',T1,'n',[],'e',{{}}), mabr.analysis.Settings().toStruct()}
    'cell',            {{}, {1,'a';"b",[]}, cell(0,2), {{1}}, {struct('a',1)}, {T1; "x"}}
    'table',           {T1, T2, T3, T4, T5, T6, table(), table.empty(3,0), ...
                        table("k","V","P",1.9,'VariableNames',{'Key','Wave','Kind','Latency'}), ...
                        table("RowNames","Row",'VariableNames',{'a','b'})}   % one row, text a parameter name could be
    'N-D',             {rand(2,3,2), reshape(string(1:8),2,2,2), true(1,2,2), cell(2,1,2), ...
                        repmat(struct('a',1),[1 2 2])}
    };
nCase = 0;
for g = 1:size(cases,1)
    vals = cases{g,2};
    for k = 1:numel(vals)
        v = vals{k};
        s = W(v);
        assert(isstring(s) && isscalar(s),'%s #%d: literal() did not return one string.',cases{g,1},k);
        try
            b = eval(s);
        catch ME
            error('verify_offline_script:literal','%s #%d (%s): the literal does not evaluate (%s):\n%s', ...
                cases{g,1},k,class(v),ME.message,s);
        end
        assert(strcmp(class(b),class(v)) && isequal(size(b),size(v)) && isequaln(b,v), ...
            '%s #%d (%s): eval(literal(v)) differs from v:\n%s',cases{g,1},k,class(v),s);
        if isfloat(v) && isreal(v) && ~issparse(v)
            neg = v(:) == 0 & 1./double(v(:)) < 0;
            assert(isequal(neg,b(:) == 0 & 1./double(b(:)) < 0), ...
                '%s #%d: the sign of a zero was lost:\n%s',cases{g,1},k,s);
        end
        nCase = nCase + 1;
    end
end
% the shortest exact text, not %.17g noise
assert(W(0.1) == "0.1" && W(-0) == "-0" && W([1 2 3]) == "[1 2 3]" && W([]) == "[]" && ...
    W(zeros(0,1)) == "zeros(0,1)" && W(NaN(2,1)) == "NaN(2,1)" && W(1/3) == "0.3333333333333333" && ...
    W(single(0.1)) == "single(0.1)" && W(single([0.3 -0])) == "single([0.3 -0])", ...
    'literal() does not write the shortest exact decimal.');
assert(W("it's") == """it's""" && W('it''s') == "'it''s'" && W(string(missing)) == "string(missing)", ...
    'literal() quoting is not as written.');
assert(W(datetime(2026,10,1,10,0,0)) == "datetime(""2026-10-01T10:00:00"", 'InputFormat', ""yyyy-MM-dd'T'HH:mm:ss"")", ...
    'A whole-second datetime is not written as ISO text with its InputFormat.');
% a long literal is continued over lines (and still evaluates)
s = W((1:150)/7);
assert(numel(splitlines(s)) > 5 && contains(s," ..." + newline), 'A long row was not continued over lines.');
% a Settings object writes out every property and comes back identical
st = mabr.analysis.Settings(NumPermutations=250,HighPass=[],Criterion=0.4,ThresholdMethod="custom", ...
    GroupBy=["Stimulus" "Frequency"],SplitHalfWindow=[1 6],Profile="Lab ""quoted"" µ");
st.Waves(end+1) = struct('Name',"VI",'Enabled',false,'TMin',5.5,'TMax',6.5,'Expected',6, ...
    'LatencyShift',0.02,'Stimulus',"ClickTrain");
b = eval(W(st));
assert(isa(b,'mabr.analysis.Settings') && isequaln(b.toStruct(),st.toStruct()) && b.hash() == st.hash(), ...
    'literal(Settings) does not rebuild the same settings.');
f = string(fieldnames(st.toStruct()));
assert(all(arrayfun(@(n) contains(W(st),n + "="),f(f ~= "SettingsVersion"))), ...
    'literal(Settings) leaves a property out.');
% refusals
try
    W(@sin);
    error('verify_offline_script:noError','literal() wrote a function handle.');
catch ME
    assert(strcmp(ME.identifier,'mabr:analysis:ScriptWriter:unsupported'), ...
        'literal(@sin) failed with %s, not mabr:analysis:ScriptWriter:unsupported.',ME.identifier);
end
fprintf('  PASS Part A: literal() round-trips %d values of every supported type exactly, in the shortest text\n',nCase);

% =========================================================================
%  Part B -- a generated script, with the Session calls stubbed out
% =========================================================================
studyRoot = fullfile(root,"study");
sessFolder = fullfile(studyRoot,"SUBJ-ID-9001","SUBJ-ID-9001_Baseline");
[R,fake] = handResults(sessFolder,"SUBJ-ID-9001/SUBJ-ID-9001_Baseline");
[code,info] = mabr.analysis.ScriptWriter.session(R,DataRoot=studyRoot,IncludeExport=false, ...
    Title="Replicate SUBJ-ID-9001 — baseline (µ-test)");
assert(isstring(code) && isscalar(code) && endsWith(code,newline),'session() did not return one string.');
flat = replace(code,newline + "% "," ");          % the header's comment lines joined
need = ["% Replicate SUBJ-ID-9001 — baseline (µ-test)", "%% Setup", "MABRROOT = ", ...
    "if ~exist('DATAROOT','var'), DATAROOT = ", "addpath(", "%% Settings", ...
    "settings = mabr.analysis.Settings(", "assert(settings.hash() == """ + R.Provenance.SettingsHash + """", ...
    "%% Session: SUBJ-ID-9001_Baseline", ...
    "S = mabr.analysis.Session(fullfile(DATAROOT,""SUBJ-ID-9001"",""SUBJ-ID-9001_Baseline""), ...", ...
    "Name=""SUBJ-ID-9001_Baseline""", "Key=""SUBJ-ID-9001/SUBJ-ID-9001_Baseline""", ...
    "Exclude=""SUBJ-ID-9001_Baseline/SUBJ-ID-9001_Frequency-4kHz_Level-0dB_261001T100000.abr""", ...
    "UnitOverride=struct('InputFullScale', NaN, 'AmplifierGain', 0.5)", "Verbose=true);", ...
    "S.TimeOffset = 0.25;", "S.ConductionDelayOverride = NaN;", "edits = struct( ...", "S.adoptEdits(edits);", "S.analyze(settings);", ...
    "expected = struct( ...", "replicatedExactly = compareWithRecorded(S,expected,""SUBJ-ID-9001_Baseline"");", ...
    "function same = compareWithRecorded(S,expected,label)", "MABR " + info.Commit];
for t = need
    assert(contains(flat,t),'The session script lacks "%s".',t);
end
assert(~contains(code,"%% Export") && ~contains(code,"OUTFOLDER"),'IncludeExport=false still exports.');
assert(info.DataRoot == normalizedPath(studyRoot) && isequal(info.Keys,R.Summary.Key) && ...
    info.SettingsHash == R.Provenance.SettingsHash && isempty(info.Warnings),'session() info is wrong.');
% every setting is written out by name
for nm = reshape(string(fieldnames(R.Settings)),1,[])
    if nm == "SettingsVersion", continue; end
    assert(contains(code,"    " + nm + "="),'The script does not write the setting %s.',nm);
end

% Run it, the Session stubbed: S becomes a struct, adoptEdits captures the
% edits, analyze() becomes the results the fake session "computes".
real = mabr.analysis.ScriptWriter.write(fullfile(root,"scripts","SUBJ-ID-9001_replicate"),code);
assert(endsWith(real,fullfile("scripts","SUBJ_ID_9001_replicate.m")) && isfile(real), ...
    'write() did not make the name a valid script name (%s).',real);
file = mabr.analysis.ScriptWriter.write(fullfile(root,"stubs","session_stub.m"),stubbed(code));
[ws,out] = runScript(file,studyRoot,"",fake);
assert(isequaln(ws.settings.toStruct(),R.Settings),'The script''s settings differ from the recorded ones.');
assert(ws.MABRROOT == string(mabr.Config.root()) && ws.DATAROOT == studyRoot,'MABRROOT/DATAROOT wrong.');
E = ws.capturedEdits;
assert(isequaln(E.ManualRejections,R.ManualRejections) && isequaln(E.DetectionOverrides,R.DetectionOverrides) && ...
    isequaln(E.PeakOverrides,R.PeakOverrides) && isequaln(E.CurationArchive,R.CurationArchive), ...
    'The edit tables the script replays differ from the recorded ones.');
cur = R.Thresholds(R.Thresholds.Decision ~= "" | R.Thresholds.Note ~= "", ...
    ["Key" mabr.analysis.ScriptWriter.CurationColumns]);
assert(isequaln(E.Thresholds,cur),'The curation the script replays is not the decided/noted rows.');
assert(ws.replicatedExactly == true && contains(out,"SUBJ-ID-9001_Baseline: replicated exactly"), ...
    'Identical results were not reported as replicated exactly:\n%s',out);
X = ws.expected;
assert(isequaln(X.Thresholds,R.Thresholds(:,{'Key','Threshold','Status','Censored','Final','FinalCensored', ...
    'FinalLo','FinalHi','Decision'})) && isequaln(X.Conditions,R.Conditions(:,{'Key','p','isSig','Detected', ...
    'nClean','nRejected'})) && isequaln(X.Peaks,R.Peaks(:,{'Key','Wave','State','PeakLatency','PeakValue', ...
    'TroughLatency','TroughValue'})),'The expected results written are not the recorded ones.');

% A difference is listed, never thrown -- and so is a missing table.
bad = fake;
bad.Thresholds.Final(2) = 47;
bad.Peaks.PeakLatency(3) = bad.Peaks.PeakLatency(3) + 1e-3;
bad.Peaks.PeakValue(3) = bad.Peaks.PeakValue(3)*(1 + 1e-9);   % rounding: counted, not listed
bad.Conditions(end,:) = [];
bad.Thresholds.Status(1) = missing;                        % a value fprintf cannot print as it is
[ws,out] = runScript(file,studyRoot,"",bad);
assert(ws.replicatedExactly == false && contains(out,"4 value(s) differ") && ...
    contains(out,"Final was 45, now 47") && contains(out,"recorded, but not reproduced") && ...
    contains(out,"PeakLatency was") && contains(out,"Status was ""ok"", now <missing>") && ...
    ~contains(out,"PeakValue was"),'Planted differences were not listed (or rounding was):\n%s',out);
% A difference of rounding alone -- a session the results were recorded from
% opened from a results file that held its averages in single precision --
% is a replication, said as such, never a list of "differences" of 1e-8 ms.
near = fake;
near.Peaks.PeakLatency = near.Peaks.PeakLatency.*(1 + 1e-9*(1:height(near.Peaks)).');
[ws,out] = runScript(file,studyRoot,"",near);
assert(ws.replicatedExactly == true && contains(out,"SUBJ-ID-9001_Baseline: replicated (") && ...
    contains(out,"within floating-point rounding") && ~contains(out,"differ"), ...
    'Rounding-only differences were not reported as a replication:\n%s',out);
[ws,out] = runScript(file,studyRoot,"",struct('Key',"x"));
assert(ws.replicatedExactly == false && contains(out,"could not compare"), ...
    'A session without results tables threw or was called replicated:\n%s',out);

% checkcode: nothing on the session script with export and figures, and the
% one written above
full = mabr.analysis.ScriptWriter.session(R,IncludePlots=true,ExportOptions=struct( ...
    'Tables',["thresholds","conditions","peaks"],'ThresholdsAll',true,'Formats',["csv" "mat"],'RScript',false));
assert(contains(full,"%% Export") && contains(full,"ThresholdsAll=true") && ...
    contains(full,"Tables=[""thresholds"", ""conditions"", ""peaks""]") && ...
    contains(full,"Formats=[""csv"", ""mat""]") && ~contains(full,"writeRScript") && ...
    contains(full,"%% Figures") && contains(full,"S.plotAudiogram();") && ...
    contains(full,"OUTFOLDER = fullfile(tempdir,""mabr_replication_"), ...
    'The export/figure sections do not carry the options asked for.');
fullFile = mabr.analysis.ScriptWriter.write(fullfile(root,"scripts","full.m"),full);
raw = mabr.analysis.ScriptWriter.study(struct('Key',"k",'Results',R,'Labels',[],'Notes',[],'Session',[]), ...
    ExportOptions=struct('Tables',["thresholds","blocks","sweeps"],'Formats',"parquet"));
assert(contains(raw,"'Session',S);") && contains(raw,"sweepFiles = table();") && ...
    contains(raw,"mabr.analysis.Export.writeRaw(S,items(1),OUTFOLDER,Tables=""sweeps"",Formats=""parquet"")") && ...
    contains(raw,"exportFiles = [exportFiles; sweepFiles];") && contains(raw,"Tables=[""thresholds"", ""blocks""]"), ...
    'Raw tables are not exported from the analysed sessions (sweeps through Export.writeRaw).');
rawFile = mabr.analysis.ScriptWriter.write(fullfile(root,"scripts","raw.m"),raw);
for f = [real fullFile rawFile]
    msgs = checkcode(char(f),'-id','-struct');
    assert(isempty(msgs),'checkcode reports on %s: %s',f,msgText(msgs));
end
% the file is UTF-8, as written
fid = fopen(real,'r');
raw = fread(fid,Inf,'*uint8').';
fclose(fid);
assert(contains(string(native2unicode(raw,'UTF-8')),"— baseline (µ-test)") && ~isequal(raw(1:3),uint8([239 187 191])), ...
    'The script file does not hold its non-ASCII title as UTF-8 (without a byte-order mark).');

% DataRoot: default = the session folder's parent; outside it = full paths
c2 = mabr.analysis.ScriptWriter.session(R,IncludeExport=false,IncludeCheck=false);
assert(contains(c2,"DATAROOT = """ + normalizedPath(fileparts(sessFolder)) + """") && ...
    contains(c2,"S = mabr.analysis.Session(fullfile(DATAROOT,""SUBJ-ID-9001_Baseline"")") && ...
    ~contains(c2,"compareWithRecorded") && ~contains(c2,"expected ="), ...
    'The default DATAROOT is not the session folder''s parent (or IncludeCheck=false still checks).');
[c3,i3] = mabr.analysis.ScriptWriter.session(R,DataRoot=fullfile(root,"elsewhere"),IncludeEdits=false);
assert(contains(c3,"S = mabr.analysis.Session(""" + normalizedPath(sessFolder) + """") && ...
    any(contains(i3.Warnings,"Not every session folder")) && ~contains(c3,"adoptEdits") && ...
    contains(replace(c3,newline + "% "," "),"does NOT replay the manual edits"), ...
    'A folder outside DataRoot is not written in full (or IncludeEdits=false still replays).');

% study(): two sessions, two sets of settings, a v1 item left out
sess2 = fullfile(studyRoot,"SUBJ-ID-9002","SUBJ-ID-9002_Baseline");
[R2,fake2] = handResults(sess2,"SUBJ-ID-9002/SUBJ-ID-9002_Baseline",mabr.analysis.Settings(Alpha=0.01));
lab = struct('Subject',"SUBJ-ID-9002",'SubjectRaw',"SUBJ-ID-9002",'Timepoint',"Baseline", ...
    'TimepointOrder',1,'Group',"control",'InStudy',true,'TestMode',false,'DaysFromReference',0, ...
    'TimeOffset',0,'Comment',"",'Free',struct('Weight',62.5), ...
    'UsedInStudy',struct('SeriesKey',R2.Thresholds.Key,'Used',true(height(R2.Thresholds),1)));
items = struct('Key',{"SUBJ-ID-9001/SUBJ-ID-9001_Baseline","old/v1","SUBJ-ID-9002/SUBJ-ID-9002_Baseline"}, ...
    'Results',{R,struct('Version',1,'Name',"old"),R2},'Labels',{[],[],lab},'Notes',{[],[],[]},'Session',{[],[],[]});
[sc,si] = mabr.analysis.ScriptWriter.study(items,DataRoot=studyRoot,IncludeExport=false);
assert(contains(sc,"%% Session 1 of 2: SUBJ-ID-9001_Baseline") && contains(sc,"%% Session 2 of 2: SUBJ-ID-9002_Baseline") && ...
    contains(sc,"settings2 = mabr.analysis.Settings(") && contains(sc,"S.analyze(settings2);") && ...
    contains(sc,"replicated(2) = compareWithRecorded(") && height(si.Skipped) == 1 && ...
    si.Skipped.Key == "old/v1" && contains(si.Skipped.Reason,"version 1"), ...
    'The study script does not cover the two sessions with their own settings, or the v1 item is not skipped.');
sreal = mabr.analysis.ScriptWriter.write(fullfile(root,"scripts","study_replicate.m"),sc);
sfile = mabr.analysis.ScriptWriter.write(fullfile(root,"stubs","study_stub.m"),stubbed(sc));
[ws,out] = runScript(sfile,studyRoot,"",{fake,fake2});
assert(isequal(ws.replicated,[true true]) && contains(out,"2 of 2 sessions replicated.") && ...
    isequaln(ws.settings2.toStruct(),R2.Settings),'The study script does not replicate both sessions:\n%s',out);
msgs = checkcode(char(sreal),'-id','-struct');
assert(isempty(msgs),'checkcode reports on the study script: %s',msgText(msgs));

% refusals
mustFail(@() mabr.analysis.ScriptWriter.session(struct('Version',1,'Name',"old")), ...
    'mabr:analysis:ScriptWriter:notReplicable');
Rn = R; Rn.Settings = [];
mustFail(@() mabr.analysis.ScriptWriter.session(Rn),'mabr:analysis:ScriptWriter:notAnalysed');
[c4,i4] = mabr.analysis.ScriptWriter.session(R,ExportOptions=struct('Bogus',1,'Formats',"parquet"));
assert(any(contains(i4.Warnings,"ExportOptions.Bogus")) && contains(c4,"Warnings when this script was written") && ...
    contains(c4,"Formats=""parquet""") && ~contains(c4,"Bogus="), ...
    'An unknown export option is not left out with a warning (or a known one not passed on).');
mustFail(@() mabr.analysis.ScriptWriter.study(items(2)),'mabr:analysis:ScriptWriter:noSessions');
mustFail(@() mabr.analysis.ScriptWriter.session(fullfile(root,"nope.mat")),'mabr:analysis:ScriptWriter:badSource');
fprintf(['  PASS Part B: the generated script sets up, writes every setting and asserts its hash, replays the ' ...
    'edits, records and compares the results (a difference listed, not thrown; rounding alone counted as a replication); study with two settings; ' ...
    'write() UTF-8 + valid name; checkcode clean; refusals\n']);

% =========================================================================
%  Parts C-E -- the real thing, once Session can analyze and adopt edits
% =========================================================================
runReplication(root);

% =========================================================================
figs1 = findall(groot,'Type','figure');
assert(all(ismember(figs1,figs0)),'verify_offline_script left a figure open.');
clear cleanup
fprintf('== verify_offline_script PASSED (%.1f s) ==\n',toc(tAll));
end

% =========================================================================
%  Parts C-E
% =========================================================================
function runReplication(root)
% A SyntheticABR session analysed, edited every way, written as a script and
% run again from the files.
truth = mabrtest.SyntheticABR.defaults();
truth.Levels  = 0:20:80;
truth.nSweeps = 64;
data = fullfile(root,"data");
s1 = fullfile(data,"SUBJ-ID-9001","SUBJ-ID-9001_Baseline");
mabrtest.SyntheticABR.writeSession(s1,truth,Subject="SUBJ-ID-9001",Stimuli=["Tone" "ClickTrain"]);
settings = mabr.analysis.Settings(NumPermutations=100,SplitHalfResamples=50,MinSweeps=20,MinPerPolarity=10);

t0 = tic;
S0 = mabr.analysis.Session(s1,Key="SUBJ-ID-9001/SUBJ-ID-9001_Baseline",Verbose=false);
S0.TimeOffset = 0.2;
S0.ConductionDelayOverride = 0.3;                % A9: this session's own conduction delay
S0.analyze(settings);
assert(abs(S0.LatencyOffset - 0.5) < 1e-12 && all(S0.Peaks.LatencyOffset == S0.LatencyOffset), ...
    'The session''s latency offset is not its TimeOffset plus its conduction delay override.');
tAnalyse = toc(t0);

% ---- edits of every kind, data edits first -----------------------------
sk = S0.seriesKeys();
assert(numel(sk) == 4,'Expected 4 series (Tone 4/8/16 kHz and the click), found %d.',numel(sk));
c1 = S0.seriesConditions(sk(1));          % levels ascending
c2 = S0.seriesConditions(sk(2));
c3 = S0.seriesConditions(sk(3));
c4 = S0.seriesConditions(sk(4));
S0.setSweepsRejected(c1(end),[3 7],true);                 % a manual rejection (top level)
S0.setDetectionOverride(c2(3),0);                          % a detection override (mid level)
P = S0.Peaks;
row = find(P.Key == c3(1) & P.Wave == "I",1);              % lowest level: nothing below to re-track
lat = P.PeakLatency(row);
if ~isfinite(lat), lat = 1.6; end
S0.setPeak(c3(1),"I","P",lat + 0.25);                      % a peak placed by hand
S0.setPeakAbsent(c4(1),"II",true);                         % a peak marked absent
S0.acceptFit(sk(1));                                       % accepted
lv = S0.Thresholds.MaxLevel(S0.seriesRow(sk(2)));
S0.setDecision(sk(2),"manual",Value=lv - 20,Kind="level"); % manual level
S0.setDecision(sk(3),"noresponse");                        % no response
S0.setDecision(sk(4),"excluded");                          % excluded
assert(height(S0.ManualRejections) >= 2 && height(S0.DetectionOverrides) == 1 && ...
    height(S0.PeakOverrides) == 2 && all(ismember(["accepted","manual","noresponse","excluded"], ...
    S0.Thresholds.Decision)),'The edits did not land on the original session.');

% ---- the script, run from a moved copy of the data -----------------------
lab = struct('Subject',"SUBJ-ID-9001",'SubjectRaw',"SUBJ-ID-9001",'Timepoint',"Baseline", ...
    'TimepointOrder',1,'Group',"control",'InStudy',true,'TestMode',false,'DaysFromReference',0, ...
    'TimeOffset',0.2,'ConductionDelay',0.3,'Comment',"",'Free',struct(), ...
    'UsedInStudy',struct('SeriesKey',S0.Thresholds.Key,'Used',true(height(S0.Thresholds),1)));
xo = struct('Tables',["sessions","conditions","thresholds","peaks","peak_measures","io_slopes","waveforms", ...
    "blocks","sweeps"],'BlockSize',16);                    % two raw tables, from the analysed S
                                                           % (64 sweeps, some rejected: blocks of 16)
code = mabr.analysis.ScriptWriter.session(S0,DataRoot=data,Labels=lab,ExportOptions=xo);
assert(contains(code,"S.TimeOffset = 0.2;") && contains(code,"S.ConductionDelayOverride = 0.3;") && ...
    contains(code,"ConductionDelayMode=""none""") && contains(code,"SpeakerDistance=10"), ...
    'The script does not carry the session''s latency overrides and the conduction-delay settings.');
file = mabr.analysis.ScriptWriter.write(fullfile(root,"scripts","replicate_analysis.m"),code);
msgs = checkcode(char(file),'-id','-struct');
assert(isempty(msgs),'checkcode reports on the replication script: %s',msgText(msgs));
moved = fullfile(root,"moved");
copyfile(data,moved);
outScript = fullfile(root,"export_script");
t0 = tic;
[ws,out] = runScript(file,moved,outScript,[]);
tRun = toc(t0);
S = ws.S;
assert(isa(S,'mabr.analysis.Session') && startsWith(S.Paths(1),moved), ...
    'The script did not read the moved copy of the data (DATAROOT).');
assert(ws.replicatedExactly == true && contains(out,"replicated exactly"), ...
    'The script''s own check did not report an exact replication:\n%s',out);
same(S.Thresholds,S0.Thresholds,["Key","Threshold","Status","Censored","Final","FinalCensored", ...
    "FinalLo","FinalHi","Decision","ManualValue","ManualKind"],"Thresholds");
same(S.Conditions,S0.Conditions,["Key","p","isSig","Detected","nClean","nRejected"],"Conditions");
same(S.Peaks,S0.Peaks,["Key","Wave","State","PeakLatency","PeakValue","TroughLatency","TroughValue", ...
    "TroughState","AmpPT","LatencyOffset"],"Peaks");
assert(isequal(S.Conditions.Key,S0.Conditions.Key) && isequal(S.Conditions.Rejected,S0.Conditions.Rejected), ...
    'The Rejected flags differ from the original''s.');
assert(S.TimeOffset == 0.2 && S.ConductionDelayOverride == 0.3 && S.LatencyOffset == S0.LatencyOffset, ...
    'TimeOffset / ConductionDelayOverride not replayed.');
% the latencies as reported (re sound arrival) are the original's, and are
% not the raw ones
ok = isfinite(S0.Peaks.PeakLatency);
assert(any(ok) && isequaln(mabr.analysis.Peaks.reported(S.Peaks.PeakLatency,S.Peaks.LatencyOffset), ...
    mabr.analysis.Peaks.reported(S0.Peaks.PeakLatency,S0.Peaks.LatencyOffset)) && ...
    all(abs(mabr.analysis.Peaks.reported(S0.Peaks.PeakLatency(ok),S0.Peaks.LatencyOffset(ok)) - ...
    (S0.Peaks.PeakLatency(ok) - 0.5)) < 1e-12), ...
    'The reported latencies (re sound arrival, 0.5 ms offset) are not replicated.');
% A session OPENED FROM ITS RESULTS and re-analysed from there -- another
% threshold method, the peaks re-picked from the stored means, as the app does
% on a session it opened from its results file -- is replicated EXACTLY by its
% script, which analyses the raw files: the means are stored as computed.
rf = fullfile(root,"results_C.mat");
S0.saveResults(rf,IncludeSweeps=false);                    % as the app and a batch write them
R1 = mabr.analysis.Session.fromResults(rf);
R1.Verbose = false;
assert(~R1.HasSweeps,'A session from its results file has sweeps.');
s2 = mabr.analysis.Settings(NumPermutations=100,SplitHalfResamples=50,MinSweeps=20,MinPerPolarity=10, ...
    ThresholdMethod="perm-descending");
R1.analyze(s2,Steps=["thresholds","peaks"]);
code2 = mabr.analysis.ScriptWriter.session(R1,DataRoot=data,IncludeExport=false);
file2 = mabr.analysis.ScriptWriter.write(fullfile(root,"scripts","replicate_from_results.m"),code2);
[ws2,out2] = runScript(file2,moved,"",[]);
assert(ws2.replicatedExactly == true && contains(out2,"replicated exactly"), ...
    'A session re-analysed from its results file was not replicated exactly by its script:\n%s',out2);
same(ws2.S.Peaks,R1.Peaks,["Key","Wave","State","PeakLatency","PeakValue","TroughLatency","TroughValue"], ...
    "Peaks (from results)");
fprintf(['  PASS Part C: a session analysed and edited every way is reproduced exactly by its script, run ' ...
    'from a moved copy of the data, its 0.3 ms conduction delay override and reported latencies ' ...
    'included (analysis %.1f s, script %.1f s); so is one re-analysed from its results file ' ...
    '(perm-descending, peaks from the stored means)\n'],tAnalyse,tRun);

% =========================================================================
%  Part D -- the export equals a direct Export of the original
% =========================================================================
items = struct('Key',S0.Key,'Results',S0.toStruct(false,true),'Labels',lab, ...
    'Notes',ws.items.Notes,'Session',[]);
T = mabr.analysis.Export.tables(items,Tables=setdiff(xo.Tables,["blocks","sweeps"],'stable'),ThresholdsAll=false,OnlyReviewed=false, ...
    IncludeExcluded=false,IncludeTestMode=false,WaveformWindow=[-2 10],Settings=settings);
files = mabr.analysis.Export.write(T,fullfile(root,"export_direct"),Formats="csv");
sameExports(files,ws.exportFiles);
for f = ["mabr_import.R","mabr_columns.csv","mabr_export.json","mabr_settings.json"]
    assert(isfile(fullfile(outScript,f)),'The script did not write %s.',f);
end
% the raw tables come from the session the script analysed (blocks through
% Export.tables, sweeps through Export.writeRaw as parquet: never CSV)
xf = ws.exportFiles(string(ws.exportFiles.File) ~= "",:);
rb = xf(string(xf.Table) == "blocks",:);
rs = xf(string(xf.Table) == "sweeps",:);
assert(height(rb) == 1 && isfile(rb.File(1)) && rb.Rows(1) > 0 && ...
    height(rs) >= 1 && all(string(rs.Format) == "parquet") && all(isfile(rs.File)), ...
    'The script did not export the raw tables (blocks, sweeps as parquet) from its analysed session.');
M = jsondecode(fileread(fullfile(outScript,"mabr_export.json")));
assert(M.SchemaVersion == 1 && contains(M.Scope,"Replication") && isfield(M.Options,'Tables'), ...
    'The script''s manifest does not record the replication and its options.');
fprintf(['  PASS Part D: the script''s export equals a direct Export of the original (%d tables, ' ...
    'readtable), with R script, dictionary, manifest, and the raw tables of the analysed session\n'], ...
    height(files));

% =========================================================================
%  Part E -- a study script over two sessions
% =========================================================================
s2 = fullfile(data,"SUBJ-ID-9002","SUBJ-ID-9002_Baseline");
mabrtest.SyntheticABR.writeSession(s2,truth,Subject="SUBJ-ID-9002",Start=datetime(2026,10,1,11,0,0), ...
    ShiftByFreq=[10 0 20]);
settings2 = mabr.analysis.Settings(NumPermutations=100,SplitHalfResamples=50,MinSweeps=20, ...
    MinPerPolarity=10,ThresholdMethod="perm-descending",ConductionDelayMode="distance", ...
    SpeakerDistance=12,SpeedOfSound=345,TimeOffset=0.05);
S2 = mabr.analysis.Session(s2,Key="SUBJ-ID-9002/SUBJ-ID-9002_Baseline",Verbose=false);
S2.analyze(settings2);
lab2 = lab;
lab2.Subject = "SUBJ-ID-9002";  lab2.SubjectRaw = "SUBJ-ID-9002";  lab2.Group = "exposed";
lab2.TimeOffset = NaN;  lab2.ConductionDelay = NaN;  lab2.Free = struct('Weight',71);
lab2.UsedInStudy = struct('SeriesKey',S2.Thresholds.Key,'Used',true(height(S2.Thresholds),1));
lab.Free = struct('Weight',64);
items = struct('Key',{S0.Key,S2.Key},'Results',{S0.toStruct(false,true),S2.toStruct(false,true)}, ...
    'Labels',{lab,lab2},'Notes',{[],[]},'Session',{[],[]});
code = mabr.analysis.ScriptWriter.study(items,DataRoot=data,ExportOptions=struct('Tables',"thresholds"));
assert(contains(code,"ConductionDelayMode=""distance""") && contains(code,"SpeakerDistance=12") && ...
    contains(code,"SpeedOfSound=345") && contains(code,"S.ConductionDelayOverride = NaN;"), ...
    'The study script does not carry the second session''s conduction-delay settings.');
file = mabr.analysis.ScriptWriter.write(fullfile(root,"scripts","replicate_study.m"),code);
msgs = checkcode(char(file),'-id','-struct');
assert(isempty(msgs),'checkcode reports on the study script: %s',msgText(msgs));
outStudy = fullfile(root,"export_study");
[ws,out] = runScript(file,data,outStudy,[]);
assert(isequal(ws.replicated,[true true]) && contains(out,"2 of 2 sessions replicated."), ...
    'The study script did not replicate both sessions:\n%s',out);
T = mabr.analysis.Export.tables(items,Tables="thresholds",ThresholdsAll=false,OnlyReviewed=false, ...
    IncludeExcluded=false,IncludeTestMode=false,WaveformWindow=[-2 10],Settings=settings);
files = mabr.analysis.Export.write(T,fullfile(root,"export_study_direct"),Formats="csv");
sameExports(files,ws.exportFiles);
th = readtable(files.File(1),'TextType','string','Delimiter',',');
assert(numel(unique(th.session_id)) == 2 && all(ismember(["control","exposed"],th.group)), ...
    'The study''s thresholds export does not hold both sessions with their labels.');
fprintf('  PASS Part E: a study script over two sessions (two settings, labels) reproduces both and the thresholds table\n');
end

% =========================================================================
%  Helpers
% =========================================================================
function [R,fake] = handResults(folder,key,settings)
% A results v2 struct (10 section 16.1) for a session never analysed here:
% three tone series and a click, curated every way, with edits.
if nargin < 3, settings = mabr.analysis.Settings(NumPermutations=200); end
[~,name] = fileparts(folder);
name = string(name);
subj = extractBefore(name,"_");
R = struct();
R.Version = 2;
R.Provenance = struct('AnalyzedAt','2026-10-01T12:00:00','MATLABVersion',version, ...
    'MABRVersion',"abc1234",'Host',"RIG",'User',"tester",'SettingsHash',settings.hash());
R.Settings = settings.toStruct();
R.StepState = struct('segment',[],'reject',[],'detect',[],'measure',[],'thresholds',[],'peaks',[]);
R.Summary = struct('Key',key,'Keys',key,'Paths',folder,'Name',name,'Subject',subj, ...
    'SubjectRaw',subj,'Date',"2026-10-01",'SampleRate',12000,'Window',[-12 12], ...
    'Exclude',name + "/" + subj + "_Frequency-4kHz_Level-0dB_261001T100000.abr", ...
    'UnitOverride',struct('InputFullScale',NaN,'AmplifierGain',0.5),'TimeOffset',0.25);
sKey = ["Stimulus=Tone|AcqMode=conventional|Frequency=4"; "Stimulus=Tone|AcqMode=conventional|Frequency=8"
        "Stimulus=Tone|AcqMode=conventional|Frequency=16"; "Stimulus=ClickTrain|AcqMode=conventional"];
lv = (0:20:80)';
cKey = strings(0,1);
for k = 1:numel(sKey)
    cKey = [cKey; sKey(k) + "|Level=" + lv]; %#ok<AGROW>
end
n = numel(cKey);
p = mod((1:n)'*0.137,1);
R.Conditions = table(cKey,p,p < 0.05,p < 0.05 | (1:n)' == 3,repmat(64,n,1),mod((1:n)',3), ...
    'VariableNames',{'Key','p','isSig','Detected','nClean','nRejected'});
th = table(sKey,[35;25;45;NaN],["ok";"ok";"ok";"insufficient"],["interval";"interval";"interval";""], ...
    [35;45;Inf;NaN],["interval";"interval";"right";""],[30;40;80;NaN],[40;50;NaN;NaN], ...
    ["accepted";"manual";"noresponse";"excluded"],[NaN;50;NaN;NaN],["";"level";"";""], ...
    ["";"looks right";"";"electrode came loose"],["tester";"tester";"tester";"tester"], ...
    datetime(2026,10,1,12,0,[1;2;3;4]),[35;NaN;NaN;NaN],repmat("perm-glm",4,1), ...
    'VariableNames',{'Key','Threshold','Status','Censored','Final','FinalCensored','FinalLo','FinalHi', ...
    'Decision','ManualValue','ManualKind','Note','ReviewedBy','ReviewedAt','ReviewedValue','ReviewedMethod'});
th(end+1,:) = {"Stimulus=Tone|AcqMode=interleaved|Frequency=4",30,"ok","none",30,"none",30,30,"", ...
    NaN,"","","",NaT,NaN,""};                       % an undecided series: carries nothing
R.Thresholds = th;
waves = ["I";"II";"III";"IV";"V"];
pk = table(repelem(cKey(1:4),5,1),repmat(waves,4,1),repmat("auto",20,1), ...
    1.5 + (0:19)'*0.01 + 1/3,(1:20)'*1e-7,2 + (0:19)'*0.01,-(1:20)'*1e-7, ...
    'VariableNames',{'Key','Wave','State','PeakLatency','PeakValue','TroughLatency','TroughValue'});
pk.State(2) = "manual";  pk.State(7) = "absent";  pk.PeakLatency(7) = NaN;
R.Peaks = pk;
R.PeakOverrides = table([cKey(1);cKey(2)],["II";"II"],["P";"P"],["manual";"absent"],[1.9;NaN], ...
    datetime(2026,10,1,12,0,[5;6]),["tester";"tester"], ...
    'VariableNames',{'Key','Wave','Kind','State','Latency','Time','By'});
R.ManualRejections = table(repmat(name + "/" + subj + "_Frequency-8kHz_Level-80dB_261001T100015.abr",2,1), ...
    [3;7],[true;false],datetime(2026,10,1,12,0,[7;8]) + milliseconds([0.5;0.123456]),["tester";"tester"], ...
    'VariableNames',{'FileId','SweepIndex','Reject','Time','By'});
R.DetectionOverrides = table(cKey(8),0,datetime(2026,10,1,12,0,9),"tester", ...
    'VariableNames',{'Key','Value','Time','By'});
R.CurationArchive = table("Stimulus=Tone|AcqMode=pooled|Frequency=4","accepted",NaN,"","old note", ...
    "tester",datetime(2026,9,30,9,0,0),40,"perm-descending",'VariableNames',{'Key','Decision', ...
    'ManualValue','ManualKind','Note','ReviewedBy','ReviewedAt','ReviewedValue','ReviewedMethod'});
R.Messages = table(NaT(0,1),strings(0,1),strings(0,1),strings(0,1), ...
    'VariableNames',{'Time','Level','Step','Text'});
R.EditLog = table(NaT(0,1),strings(0,1),strings(0,1),strings(0,1),strings(0,1),strings(0,1), ...
    'VariableNames',{'Time','User','Action','Key','Old','New'});
% what a session that replicates exactly would hold afterwards
fake = struct('Key',key,'Thresholds',R.Thresholds,'Conditions',R.Conditions,'Peaks',R.Peaks);
end

function code = stubbed(code)
% The generated script with the Session calls replaced: S is a struct,
% adoptEdits captures the edits, analyze() hands back FAKE (the results a
% session would have; one per session of a study, in order).
code = regexprep(code,'S = mabr\.analysis\.Session\(.*?Verbose=true\);','S = struct();');
code = replace(code,"S.adoptEdits(edits);","capturedEdits = edits;");
k = 0;
while true
    m = regexp(code,'S\.analyze\((settings\d*)\);','tokens','once');
    if isempty(m), break; end
    k = k + 1;
    code = regexprep(code,'S\.analyze\((settings\d*)\);', ...
        sprintf('if iscell(FAKE), S = FAKE{%d}; else, S = FAKE; end   % $1',k),'once');
end
end

function [ws,out] = runScript(file,DATAROOT,OUTFOLDER,FAKE) %#ok<INUSD> read by the script
% Run a generated script in a workspace of its own (this function's), with
% DATAROOT and OUTFOLDER defined beforehand as a user would, and hand back
% what it left behind and what it printed.
if OUTFOLDER == "", clear OUTFOLDER; end
out = evalc('run(file)');
ws = struct();
for v = reshape(string(who),1,[])
    if ismember(v,["file","ws","out","FAKE","v"]), continue; end
    ws.(v) = eval(v);
end
end

function same(A,B,cols,what)
% Columns of two tables isequaln, row by row in the same order.
assert(height(A) == height(B),'%s: %d rows reproduced, %d in the original.',what,height(A),height(B));
for c = cols
    assert(ismember(c,string(A.Properties.VariableNames)) && ismember(c,string(B.Properties.VariableNames)), ...
        '%s has no %s column.',what,c);
    assert(isequaln(A.(c),B.(c)),'%s.%s differs from the original''s.',what,c);
end
end

function sameExports(fa,fb)
% Every file of export fa (Export.write's files table) equals the same
% table's file in fb (readtable), the analysis time aside.
fa = fa(string(fa.File) ~= "",:);
fb = fb(string(fb.File) ~= "",:);
assert(height(fa) > 0,'The direct export wrote nothing.');
for k = 1:height(fa)
    j = find(string(fb.Table) == string(fa.Table(k)) & string(fb.Format) == string(fa.Format(k)),1);
    assert(~isempty(j),'The script''s export has no %s %s.',fa.Table(k),fa.Format(k));
    A = readtable(fa.File(k),'TextType','string','Delimiter',',');
    B = readtable(fb.File(j),'TextType','string','Delimiter',',');
    drop = cellstr(intersect(["analyzed_at","created"],string(A.Properties.VariableNames)));
    A(:,drop) = [];
    B(:,drop) = [];
    assert(isequaln(A,B),'%s differs between the script''s export and a direct one.',fa.Table(k));
end
end

function t = msgText(msgs)
% checkcode messages as one line.
t = "";
for k = 1:numel(msgs)
    t = t + sprintf('L%d %s: %s | ',msgs(k).line,msgs(k).id,msgs(k).message);
end
end

function mustFail(fcn,id)
try
    fcn();
catch ME
    assert(strcmp(ME.identifier,id),'Expected %s, got %s (%s).',id,ME.identifier,ME.message);
    return
end
error('verify_offline_script:noError','Expected %s, but nothing was thrown.',id);
end

function p = normalizedPath(p)
% A folder as ScriptWriter writes it: native separators, no trailing one.
p = string(p);
if ispc, p = replace(p,"/","\"); end
if endsWith(p,filesep), p = extractBefore(p,strlength(p)); end
end

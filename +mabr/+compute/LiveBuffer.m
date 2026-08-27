classdef LiveBuffer < mabr.compute.PublishBuffer
% mabr.compute.LiveBuffer  What the DSP worker publishes twenty times a
% second: the statistics of the run in progress, as mabr.compute.Pipeline.step
% returns them. read() returns exactly that struct, which is what lets
% mabr.ui.AcqController's live tick be the same code whether the numbers came
% from a worker or from its own pipeline.
%
%   Sufficient statistics, never sweeps: the latest sweep, the correlation,
%   the counts, and per condition the mean, SD and counts (see the Pipeline
%   help for why that is all a view needs). At 16 conditions and a 20 ms
%   window a publish writes ~60 KB into a ~17 MB file; readers slice rows
%   and never read the file.
%
%   Layout (all fields carry both halves -- see PublishBuffer):
%       Info       [16 x 2] per-half scalars, rows named by Fields below
%       TimeBase   [MaxSamples x 2]
%       Latest     [MaxSamples x 2]
%       Mean, SD   [2*MaxConds x MaxSamples]
%       CondCounts [2*MaxConds x 3]   clean total rejected
%       Stimuli    [2*MaxConds x 1]   the stimulus index each row describes
%
% Daniel Stolzberg (c) 2026

    properties (Constant)
        % Rows of Info. Named here rather than numbered at every use.
        Fields = struct('RunId',1,'NumConds',2,'NumSamples',3,'ReqSeq',4, ...
                        'LatestBad',5,'Corr',6,'NumSweeps',7,'NumClean',8, ...
                        'NumArtifacts',9,'LatestStim',10);
        NumInfo = 16;
    end

    properties (SetAccess = immutable)
        MaxSamples (1,1) double
        MaxConds   (1,1) double
    end

    methods
        function obj = LiveBuffer(cfg,writable)
            if nargin < 2, writable = false; end
            ms = cfg.MaxComputeSamples;
            mc = cfg.MaxComputeConditions;
            fmt = { ...
                'double',[mabr.compute.LiveBuffer.NumInfo 2],'Info'; ...
                'double',[ms 2],'TimeBase'; ...
                'double',[ms 2],'Latest'; ...
                'double',[2*mc ms],'Mean'; ...
                'double',[2*mc ms],'SD'; ...
                'double',[2*mc 3],'CondCounts'; ...
                'double',[2*mc 1],'Stimuli'};
            obj@mabr.compute.PublishBuffer(cfg.computeLiveFile,fmt,writable);
            obj.MaxSamples = ms;
            obj.MaxConds   = mc;
        end
        function zero(obj)
            % The header AND the per-half words: a fresh worker must not
            % leave a previous session's last publish readable.
            zero@mabr.compute.PublishBuffer(obj);
            obj.Map.Data.Info(:) = 0;
        end
    end

    methods (Access = protected)
        function writeHalf(obj,h,s)
            % s: the mabr.compute.Pipeline.step struct, plus ReqSeq.
            F  = obj.Fields;
            nS = numel(s.Time);
            nC = numel(s.Stimuli);
            assert(nS <= obj.MaxSamples,'mabr:compute:LiveBuffer:samples', ...
                'A sweep of %d samples exceeds the buffer''s %d.',nS,obj.MaxSamples);
            assert(nC <= obj.MaxConds,'mabr:compute:LiveBuffer:conditions', ...
                'A run of %d conditions exceeds the buffer''s %d.',nC,obj.MaxConds);
            col = h + 1;
            rws = obj.rows(h,obj.MaxConds,nC);

            info = zeros(obj.NumInfo,1);
            info(F.RunId)        = s.RunId;
            info(F.NumConds)     = nC;
            info(F.NumSamples)   = nS;
            info(F.ReqSeq)       = getf(s,'ReqSeq',0);
            info(F.LatestBad)    = double(s.LatestBad);
            info(F.Corr)         = s.Corr;
            info(F.NumSweeps)    = s.NumSweeps;
            info(F.NumClean)     = s.NumClean;
            info(F.NumArtifacts) = s.NumArtifacts;
            info(F.LatestStim)   = getf(s,'LatestStim',0);

            obj.Map.Data.Info(:,col)         = info;
            obj.Map.Data.TimeBase(1:nS,col)  = s.Time(:);
            obj.Map.Data.Latest(1:nS,col)    = s.Latest(:);
            if nC > 0
                obj.Map.Data.Mean(rws,1:nS)      = s.Mean;
                obj.Map.Data.SD(rws,1:nS)        = s.SD;
                obj.Map.Data.CondCounts(rws,:)   = s.CondCounts;
                obj.Map.Data.Stimuli(rws,1)      = s.Stimuli(:);
            end
        end

        function s = readHalf(obj,h)
            F    = obj.Fields;
            col  = h + 1;
            info = double(obj.Map.Data.Info(:,col));
            nS   = info(F.NumSamples);
            nC   = info(F.NumConds);
            if nS < 0 || nS > obj.MaxSamples || nC < 0 || nC > obj.MaxConds ...
                    || (nS == 0 && info(F.RunId) == 0)
                s = []; return          % never published, or torn header
            end
            rws = obj.rows(h,obj.MaxConds,nC);
            s = struct('RunId',info(F.RunId), ...
                'Time',double(obj.Map.Data.TimeBase(1:nS,col)).', ...
                'NumSamples',nS, ...
                'Latest',double(obj.Map.Data.Latest(1:nS,col)).', ...
                'LatestBad',logical(info(F.LatestBad)), ...
                'LatestStim',info(F.LatestStim), ...
                'Corr',info(F.Corr), ...
                'NumSweeps',info(F.NumSweeps),'NumClean',info(F.NumClean), ...
                'NumArtifacts',info(F.NumArtifacts), ...
                'Stimuli',double(obj.Map.Data.Stimuli(rws,1)).', ...
                'Mean',double(obj.Map.Data.Mean(rws,1:nS)), ...
                'SD',double(obj.Map.Data.SD(rws,1:nS)), ...
                'CondCounts',double(obj.Map.Data.CondCounts(rws,:)), ...
                'ReqSeq',info(F.ReqSeq));
        end
    end
end

function v = getf(s,f,d)
if isfield(s,f) && ~isempty(s.(f)), v = s.(f); else, v = d; end
end

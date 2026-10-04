classdef OfflineFixture
% mabrtest.OfflineFixture  A small analysed study on disk, for the analysis-app tests.
%
%   F = mabrtest.OfflineFixture.make() writes a synthetic study
%   (mabrtest.SyntheticABR.writeStudy: two subjects at Baseline and 2 weeks,
%   plus a mixed tone/click session with both acquisition modes), catalogs
%   it, and -- with Analyse true -- runs mabr.analysis.Batch over every
%   session so each has a results file. Everything goes to tempdir:
%
%       F = mabrtest.OfflineFixture.make();
%       app = mabr.ui.AnalysisApp(F.Root,Visible="off",ResultsFolder=F.ResultsFolder, ...
%                 CacheFolder=F.CacheFolder,Settings=F.Settings,Restore=false, ...
%                 RememberState=false,ProgressMode="none",AutoRefresh=false);
%       ...
%       clear F      % (or let it go out of scope) -- all three folders are removed
%
%   opts.Analyse   run the batch so results exist (default true)
%   opts.Subjects  ["SUBJ-ID-9001","SUBJ-ID-9002"]
%   opts.Mixed     write the mixed tone/click session (default true)
%   opts.Small     a small truth: Freqs [4 16] kHz, Levels 0:20:80 dB,
%                  64 sweeps per condition (default true) -- the whole make()
%                  takes well under 20 s
%
%   F  (returned) struct:
%     Root, ResultsFolder, CacheFolder   tempname each
%     Study       writeStudy's info (Sessions table, SessionInfo, Truth)
%     Truth       the truth the files were written from
%     Settings    mabr.analysis.Settings with NumPermutations 100,
%                 SplitHalfResamples 50, MinSweeps 20, MinPerPolarity 10
%     Keys        the catalog's session keys
%     Batch       Batch.run's table ([] without Analyse)
%     Cleanup     onCleanup removing the three folders
%
%   c = mabrtest.OfflineFixture.closer(app,F) is the one cleanup a test with
%   an app on the fixture needs: it closes the app (its close-time save
%   included) and THEN removes the fixture's folders. Two separate
%   onCleanup objects -- the app's closer and F.Cleanup -- run in no
%   guaranteed order when a test errors, and an app closed after the folders
%   went would write its results folder back into tempdir.
%
%   Never writes a pref and never opens a window.
%
%   See also mabrtest.SyntheticABR, mabr.analysis.Batch, verify_offline_app
%
% Daniel Stolzberg (c) 2026

    methods (Static)
        function F = make(opts)
            arguments
                opts.Analyse (1,1) logical = true
                opts.Subjects (1,:) string = ["SUBJ-ID-9001","SUBJ-ID-9002"]
                opts.Mixed (1,1) logical = true
                opts.Small (1,1) logical = true
            end
            root    = string(tempname);
            results = string(tempname);
            cache   = string(tempname);
            F = struct();
            F.Root          = root;
            F.ResultsFolder = results;
            F.CacheFolder   = cache;
            F.Cleanup       = onCleanup(@() mabrtest.OfflineFixture.remove([root results cache]));

            truth = mabrtest.SyntheticABR.defaults();
            if opts.Small
                truth.Freqs          = [4 16];
                truth.Threshold      = [30 40];
                truth.Levels         = 0:20:80;
                truth.nSweeps        = 64;
                truth.ArtifactSweeps = [5 40];
                truth.FlaggedSweeps  = 40;
            end
            F.Truth = truth;
            F.Study = mabrtest.SyntheticABR.writeStudy(root,truth,'Subjects',opts.Subjects, ...
                'Mixed',opts.Mixed);
            F.Settings = mabr.analysis.Settings('NumPermutations',100,'SplitHalfResamples',50, ...
                'MinSweeps',20,'MinPerPolarity',10);

            c = mabr.analysis.Catalog(root,'CacheFolder',cache,'ResultsFolder',results);
            c.scan();
            F.Keys  = reshape(string(c.Sessions.Key),[],1);
            F.Batch = [];
            if opts.Analyse
                p = mabr.analysis.Project.open(string(c.ResultsFolder));
                p.ensureSessions(c);
                items = mabrtest.OfflineFixture.items(c,p,F.Keys);
                F.Batch = mabr.analysis.Batch.run(items,F.Settings,'SkipCurrent',false, ...
                    'LogFile',string(fullfile(results,'logs','fixture_batch.csv')),'Project',p);
                p.save();
            end
        end

        function items = items(c,p,keys)
            % Batch.run's items table for catalog keys -- Project.batchItems,
            % exactly as Model.batch builds it (paths, exclusions, overrides).
            items = p.batchItems(reshape(string(keys),[],1),c);
        end

        function c = closer(app,F)
            % onCleanup: close APP (one app or several; any already gone is
            % passed by), then remove F's folders.
            c = onCleanup(@() mabrtest.OfflineFixture.closeAll(app,F));
        end

        function closeAll(app,F)
            % Close every app given -- saving what is pending, as closing
            % does -- and then remove F's folders. Never throws.
            for k = 1:numel(app)
                try
                    a = app(k);
                    if iscell(app), a = app{k}; end
                    if ~isempty(a) && isvalid(a)
                        try
                            a.Model.flush();
                        catch
                        end
                        delete(a);
                    end
                catch
                end
            end
            try
                mabrtest.OfflineFixture.remove([F.Root F.ResultsFolder F.CacheFolder]);
            catch
            end
        end

        function remove(folders)
            % Remove the fixture's folders; never throws.
            for f = reshape(string(folders),1,[])
                try
                    mabrtest.SyntheticABR.rmdirQuiet(f);
                catch
                end
            end
        end
    end
end

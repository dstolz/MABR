%% 1. Batch ABR Analysis

addpath_nogit('c:\src\MABR')

% rootPth = "C:/Users/dstolz/My Drive/PROJECTS/MABR/MABR_Analysis/abr_data/";
% resultPth = "C:/Users/dstolz/My Drive/PROJECTS/MABR/MABR_Analysis/X";
% resultPth = "C:/Users/dstolz/My Drive/PROJECTS/MABR/MABR_Analysis/abr_results";
% rootPth = "C:/Users/dstolz/My Drive/PROJECTS/NIHL and Perceptual Learning/abr_data";
% resultPth = "C:/Users/dstolz/My Drive/PROJECTS/NIHL and Perceptual Learning/abr_results";

rootPth = "C:/Users/dstolz/My Drive/PROJECTS/FM_Detection/abr_data/POST";
resultPth = "C:/Users/dstolz/My Drive/PROJECTS/FM_Detection/abr_results";

abrSessions = getABRSessions(rootPth);


fprintf(2,'WORK IN PROGRESS\n')

% skipExisting = true;
skipExisting = false;

debug = false;
% debug = true;

fullWin = [-12 12]; % ms

respWin = [0 10]; % ms
plotWindow = [-2 12];


Fs    = 12000;  % Sampling Frequency

% lowpass
Fpass = 1500;   % Passband Frequency
Fstop = 3000;   % Stopband Frequency
Apass = 0.5;      % Passband Ripple (dB)
Astop = 30;     % Stopband Attenuation (dB)
h = fdesign.lowpass('fp,fst,ap,ast', Fpass, Fstop, Apass, Astop, Fs);
HdLP = design(h, 'equiripple', ...
    'MinOrder', 'any', ...
    'StopbandShape', 'flat', ...
    'SystemObject', true);
% fvtool(HdLP)

% highpass
Fstop = 150;    % Stopband Frequency
Fpass = 300;    % Passband Frequency
Astop = 30;     % Stopband Attenuation (dB)
Apass = 0.5;      % Passband Ripple (dB)
h = fdesign.highpass('fst,fp,ast,ap', Fstop, Fpass, Astop, Apass, Fs);
HdHP = design(h, 'equiripple', ...
    'MinOrder', 'any', ...
    'StopbandShape', 'flat', ...
    'SystemObject', true);
% fvtool(HdHP)


for k = 1:length(abrSessions)
    abrSessionName = extractSessionName(abrSessions{k});

    fprintf('Dataset %d/%d. %s\n', k, length(abrSessions), abrSessionName)

    T = parseABRFiles(abrSessions{k});

    if isempty(T)
        fprintf(2, '* No valid file names, skipping *\n')
        continue
    end

    subject_id = regexp(abrSessions{k},'SUBJ-ID-\d+','match','once');

    abrSessionDate = min(T.timestamp);
    abrSessionDate.Format = "dd-MMM-uuuu";



    td = abrSessionDate;
    td.Format = "uuMMdd";
    ffnOut = fullfile(resultPth,sprintf('%s_%s.mat',subject_id,td));

    if skipExisting && isfile(ffnOut)
        fprintf('\tResults already exist, skipping ...\n')
        continue
    end


    % Filter and Extract ABR signals
    [S, U, Fs, winIdx] = extractABRResponses(T,fullWin, ...
        HighpassHd=HdHP,LowpassHd=HdLP);

    S = S'; % freq x lvl -> lvl x freq
    tvec = winIdx ./ Fs; % time vector

    % detrend
    warning('off','MATLAB:detrend:PolyNotUnique')
    S = cellfun(@(a) detrend(a,1),S,'uni',0,'ErrorHandler',@errEmpty);
    warning('on','MATLAB:detrend:PolyNotUnique')



    % Artifact detection and rejection
    [S, artInd] = rejectArtifacts(S, ...
        respInd = tvec >= respWin(1) & tvec <= respWin(2), ...
        feature = 'absPeak', ...
        useParallel = true, ...
        plot = false);








    if debug
        fprintf(2,'debug mode enabled\n')
    end





    % Plot ABRs
    h = use_fig('ABR_grid');
    plotABRGrid(S, U, Fs, winIdx, plotWindow = plotWindow);
    tl = h.Children;
    title(tl, abrSessionName,Interpreter = 'none');
    subtitle(tl, char(abrSessionDate))
    drawnow







    % Find threshold
    rind = tvec >=  respWin(1)/1000 & tvec <=  respWin(2)/1000;
    St = cellfun(@(a) a(rind,:),S,'uni',0,'ErrorHandler',@errEmpty);

    [thresh_hat,permResult,thresholdMdls] = abrPermutationThreshold(St,U.soundLevel, ...
        method = "tfce", ...
        nPerm = 2000, ...
        alpha = 0.05, ...
        thresholdType = "glm", ...
        fitTarget="binary", ...
        criterion = 0.75, ...
        useParallel = true, ...
        debug = false);
    

    clear St





    % no response at presented sound levels
    ind = thresh_hat > max(U.soundLevel);
    thresh_hat(ind) =  max(U.soundLevel)+5;

    % % threshold could be below 0, but we never really see this
    % thresh_hat(thresh_hat < 0) = 0;





    % Plot ABR audiogram
    h = use_fig('ABR_Audiogram');
    plotABRThresholds(thresh_hat,U.frequency);
    ylim([min(U.soundLevel)-5 max(U.soundLevel)+5]);

    tl = h.Children;
    title(tl,abrSessionName,Interpreter = 'none');
    subtitle(tl,char(abrSessionDate))
    drawnow





    % Save Data
    fprintf('\tsaving results: %s ...',ffnOut)
    save(ffnOut,'subject_id','T','S','U','Fs','winIdx','thresh_hat','permResult','thresholdMdls','respWin','tvec');
    fprintf(' done\n')


    % pause
end




%% 2. View and curate data


% resultPth = "C:/Users/dstolz/My Drive/PROJECTS/MABR/MABR_Analysis/abr_results";
% resultPth = "C:/Users/dstolz/My Drive/PROJECTS/NIHL and Perceptual Learning/abr_results";
resultPth = "C:/Users/dstolz/My Drive/PROJECTS/FM_Detection/abr_results";


a = dir(fullfile(resultPth,'*.mat'));


rng(12)
a = a(randperm(length(a)));


skipCurated = false;

for i = 1:length(a)
    fprintf('%d of %d \n',i,length(a))

    fn = a(i).name;

    ffn = fullfile(a(i).folder,fn);


    clear thresh_checked

    load(ffn);

    if isfield(U,'level'), U.soundLevel = U.level; end

    cm = colorcet('R1','N',length(U.frequency));


    if ~exist('thresh_checked','var')
        thresh_checked = thresh_hat;
    elseif skipCurated
        fprintf('\talready curated, skipping ... \n')
        continue
    end

    use_fig('ABR Thresholds');


    % [curation,state] = abrPermutationThresholdCuration(U.soundLevel,thresh_hat,permResult,thresholdMdls, ...
    %     S = S)

    plotABRThresholds(thresh_checked, U.frequency,cm = cm);

    use_fig('ABR Matrix');
    h = plotABRGrid(S, U, Fs, winIdx,cm = cm);

    st = nan(size(U.frequency));
    for j = 1:length(thresh_checked)
        if thresh_checked(j) > max(U.soundLevel)
            st(j) = length(U.soundLevel);
        else
            st(j) = find(U.soundLevel >= fix(thresh_checked(j)),1);
        end
        hj = h(st(j),j);
        yline(hj,min(hj.YLim),'-r',LineWidth = 5);
    end

    for j = 1:length(U.frequency)
        t = input(sprintf('%d Hz: %.1f dB:  ',U.frequency(j),thresh_checked(j)));
        if ~isempty(t)
            thresh_checked(j) = t;
        end

        use_fig('ABR Thresholds');
        plotABRThresholds(thresh_checked, U.frequency,cm = cm);
    end

    save(ffn,'subject_id','T','S','U','Fs','winIdx','thresh_hat','thresh_checked')
end



%% 3A. Across Session Analysis

% resultPth = "C:/Users/dstolz/My Drive/PROJECTS/MABR/MABR_Analysis/abr_results";
resultPth = "C:/Users/dstolz/My Drive/PROJECTS/FM_Detection/abr_results";


plotWindow = [-2 9];

a = dir(fullfile(resultPth,'*.mat'));

D = cellfun(@(a,b) load(fullfile(a,b)),{a.folder},{a.name},'uni',1);


for i = 1:length(D)
    ts = D(i).T.timestamp(1);
    ts.Format = 'uuMMdd';
    D(i).date = ts;
end
subjs = unique({D.subject_id});
subjs(string(subjs) == "SUBJ-ID-1107") = [];
[~, i] = sort([D.date]);
D = D(i);

use_fig('Thresholds');
nCol = ceil(sqrt(length(subjs)));
nRow = ceil(length(subjs)/nCol);
tl = tiledlayout(nRow,nCol);
tl.Padding = "compact";
tl.TileSpacing = "tight";

cm = colorcet('L1', 'N', 3);

for s = subjs
    idx = ismember({D.subject_id},s);
    d = D(idx);

    % Create a next tile for this subject (placeholder)
    ax = nexttile(tl);

    % Create a uipanel in the same position as this tile
    pos = ax.Position;
    % delete(ax); % remove placeholder axes
    ax.Visible = "off";

    p = uipanel('Parent', gcf, 'Units', 'normalized', 'Position', pos, ...
        'BorderType', 'none' ,'BackgroundColor','w');

    % Create axes manually within the panel
    ax1 = axes('Parent', p, 'Position', [0.1 0.55 0.85 0.4]);
    hold(ax1, 'on');
    colororder(ax1, cm);
    for i = 1:length(d)
        plot(ax1, d(i).U.frequency, d(i).thresh_checked, ...
            'o-', ...
            Color = cm(i,:), ...
            MarkerFaceColor = cm(i,:), ...
            DisplayName = char(d(i).date));
    end
    hold(ax1, 'off');
    grid(ax1, 'on');
    set(ax1, 'XScale', 'log');
    box(ax1,'on')
    xticks(ax1, d(1).U.frequency);
    ylim(ax1, [0 90]);
    title(ax1, char(s));
    ylabel('Threshold (dB SPL)')
    xlabel(ax1,'Frequency (kHz)')
    legend(ax1, 'Location', 'southwest','Box','off');

    % Second subplot: Threshold shifts
    ax2 = axes('Parent', p, 'Position', [0.1 0.1 0.85 0.35]);
    tc = vertcat(d.thresh_checked);
    dtc = tc - tc(1, :);
    if size(dtc, 1) > 1, dtc(1, :) = []; end
    plot(ax2, d(1).U.frequency, dtc, '-sk', 'LineWidth', 2, ...
        'MarkerFaceColor', 'k');
    % stem(ax2, d(1).U.frequency, dtc, '-sk', 'LineWidth', 2, ...
    %     'MarkerFaceColor', 'k');
    grid(ax2, 'on');
    set(ax2, 'XScale', 'log');
    xticks(ax2, d(1).U.frequency);
    yline(ax2, 0, 'LineWidth', 2);
    ylim(ax2,[-10 60]);
    % ylim(ax2,[-1.1 1.1]*max(abs(ylim)))
    xlabel(ax2,'Frequency (kHz)')
    ylabel(ax2,'Threshold Shift (dB)')
end


%% 3B. Sample stats
% Download CSV file for the "Noise Exposure" tab on the Tracker
% https://docs.google.com/spreadsheets/d/1yz6v2yPvJ5x5eadOeCg_mi6VQG9dgERB2v817w_CUrA/edit?gid=838637860#gid=838637860


showIndividuals = false;

NE = readtable(fullfile(resultPth,"Trackers - Noise Exposure.csv"),  ...
    TextType="string", ...
    NumHeaderLines=1);
i = ismissing(NE.Protocol);
NE(i,:) = [];

subjs = NE.subject_id;


% assumes same frequencies for all subjects/sessions (true)
X = nan(2,length(U.frequency),length(subjs));
isNE = false(size(subjs));
k = 1;
for s = subjs
    idx = find([D.subject_id] == s);
    X(1:length(idx),:,k) = vertcat(D(idx).thresh_checked);

    isNE(k) = any(NE.subject_id == s & startsWith(NE.Protocol,"NEID"));
    k = k + 1;
end

dX = squeeze(X(2,:,:) - X(1,:,:));

U = D(1).U;

use_fig('ABR stats')
gl = tiledlayout('flow');


nexttile


calcStats = @(data) struct('n', sum(~isnan(data),3), ...
    'mean', mean(data,3,"omitmissing"), ...
    'std', std(data,0,3,"omitmissing"));

Y.pre = calcStats(X(1,:,:));
Y.sham = calcStats(X(2,:,~isNE));
Y.ne = calcStats(X(2,:,isNE));

Y.pre.sem = Y.pre.std ./ sqrt(Y.pre.n);
Y.sham.sem = Y.sham.std ./ sqrt(Y.sham.n);
Y.ne.sem = Y.ne.std ./ sqrt(Y.ne.n);


cm = colorcet('R3','N',4);

f = U.frequency;
if showIndividuals
    line(f,squeeze(X(1,:,:)),Color = cm(1,:),LineWidth =0.1,LineStyle = "-", HandleVisibility = 'off');
    line(f,squeeze(X(2,:,~isNE)),Color = cm(3,:),LineWidth =0.1,LineStyle = "-", HandleVisibility = 'off');
    line(f,squeeze(X(2,:,isNE)),Color = cm(2,:),LineWidth =0.1,LineStyle = "-", HandleVisibility = 'off');
else
    patch([f(:)', fliplr(f(:)')],[Y.pre.mean + Y.pre.sem, fliplr(Y.pre.mean- Y.pre.sem)],cm(1,:),FaceAlpha = 0.3,EdgeColor = "none",HandleVisibility = "off");
    patch([f(:)', fliplr(f(:)')],[Y.ne.mean + Y.ne.sem, fliplr(Y.ne.mean- Y.ne.sem)],cm(2,:),FaceAlpha = 0.3,EdgeColor = "none",HandleVisibility = "off");
    patch([f(:)', fliplr(f(:)')],[Y.sham.mean + Y.sham.sem, fliplr(Y.sham.mean- Y.sham.sem)],cm(3,:),FaceAlpha = 0.3,EdgeColor = "none",HandleVisibility = "off");
end

lw = 3;
line(f,Y.pre.mean,LineWidth = lw, DisplayName = sprintf("Baseline (%d)",Y.pre.n(1)));
line(f,Y.ne.mean,LineWidth = lw, DisplayName = sprintf("Noise Exposed (%d)",Y.ne.n(1)));
line(f,Y.sham.mean,LineWidth =lw, DisplayName = sprintf("Sham (%d)",Y.sham.n(1)));


grid on
box on
set(gca,'xscale','log');
xticks(U.frequency)
colororder(cm);
legend(Location="northwest",Box="off")

yline(85,':k',HandleVisibility='off')
ylim([0 85]);
ylabel('threshold (dB SPL)')
xlabel('frequency (Hz)')
title('ABR Audiograms')


nexttile
dY.ne.n = sum(~isnan(dX(:,isNE)),2);
dY.ne.mean = mean(dX(:,isNE),2,"omitmissing");
dY.ne.std  = std(dX(:,isNE),0,2,"omitmissing");
dY.ne.sem  = dY.ne.std ./ sqrt(dY.ne.n);

dY.sham.n = sum(~isnan(dX(:,~isNE)),2);
dY.sham.mean = mean(dX(:,~isNE),2,"omitmissing");
dY.sham.std  = std(dX(:,~isNE),0,2,"omitmissing");
dY.sham.sem  = dY.sham.std ./ sqrt(dY.sham.n);

yline(0,LineWidth = 2,HandleVisibility= 'off')

if showIndividuals
    line(U.frequency,dX(:,isNE),LineWidth = 0.5,Color = cm(2,:),HandleVisibility= 'off')
    line(U.frequency,dX(:,~isNE),LineWidth = 0.5,Color = cm(3,:),HandleVisibility= 'off')
else
    patch([f(:); flipud(f(:))],[dY.ne.mean-dY.ne.sem;flipud(dY.ne.mean+dY.ne.sem)],cm(2,:),FaceAlpha = 0.3,EdgeColor = "none",HandleVisibility = "off");
    patch([f(:); flipud(f(:))],[dY.sham.mean-dY.sham.sem;flipud(dY.sham.mean+dY.sham.sem)],cm(3,:),FaceAlpha = 0.3,EdgeColor = "none",HandleVisibility = "off");
end
line(U.frequency,dY.ne.mean,Color = cm(2,:),LineWidth = lw,MarkerFaceColor =  cm(2,:), DisplayName = sprintf("Noise Exposed (%d)",dY.ne.n(1)));
line(U.frequency,dY.sham.mean,Color = cm(3,:),LineWidth = lw,MarkerFaceColor =  cm(3,:), DisplayName = sprintf("Sham (%d)",dY.sham.n(1)));


grid on
set(gca,'xscale','log');
xticks(U.frequency)

box on
% ylim([-1.2 1.2]*max(abs(ylim)))

ylabel('threshold shift (dB)')
xlabel('frequency (Hz)')
title('Change in ABR Threshold')

legend(Location = "northwest",Box="off")



%% 4 Peak finding

% compute mean ABR for each stimulus
Sm = cellfun(@(a) mean(a,2),S,'uni',0);
ind = cellfun(@isempty,Sm);
[Sm{ind}] = deal(nan(size(Sm{find(~ind,1)})));
% Sm = cat(2,Sm{:});

use_fig('peaks')

tl = tiledlayout(size(S,1),size(S,2));
tl.TileSpacing = "tight";
tl.Padding = "compact";
tl.TileIndexing = 'columnmajor';

rind = tvec >=  respWin(1)/1000 & tvec <=  respWin(2)/1000;


Sm = flipud(Sm);
permResult = flipud(permResult);
parfor_progress(numel(Sm));
for i = 1:numel(Sm)
    nexttile
    
    
    if isempty(Sm{i}), continue; end

    % preserve response window only
    Smp = Sm{i}(rind);
    tvecRw = tvec(rind);

    plot(tvecRw,Smp);
    yline(0,'-k');
    grid on

    mask = permResult(i).pos.mask | permResult(i).neg.mask;

    line(tvecRw(mask),Smp(mask),Color = 'r',Marker = '.',LineStyle = "none")

    parfor_progress();
end
parfor_progress(0);

ax = tl.Children;
set(ax,'xtick',[],'ytick',[])
linkaxes(ax)

















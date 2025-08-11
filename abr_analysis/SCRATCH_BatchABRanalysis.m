%% 1. Batch ABR Analysis

addpath('C:\Users\dstolz\My Drive\temp_analysis\ABR_analysis\')

rootPth = "C:/Users/dstolz/My Drive/PROJECTS/MABR/MABR_Analysis/abr_data/";
resultPth = "C:/Users/dstolz/My Drive/PROJECTS/MABR/MABR_Analysis/abr_results";

abrSessions = getABRSessions(rootPth);
% abrSessions = {'C:\Users\dstolz\My Drive\PROJECTS\MABR\MABR_Analysis\abr_data\SUBJ-ID-979\SUBJ-ID-979_Baseline'};


debug = false;
% debug = true;

filePattern = "SUBJ_ID_(\d+)_Frequency_([\d_]+kHz)_Level_(\d+dB)_(\d{6}T\d{6})\.abr";
fullWin = [-10 10]; % ms

respWin = [0 9]; % ms
plotWindow = [-2 9];


skipExisting = true;
% skipExisting = false;


for k = 1:length(abrSessions)
    abrSessionName = extractSessionName(abrSessions{k});
    fprintf('%d/%d. Processing: %s\n', k, length(abrSessions), abrSessionName)

    T = parseABRFiles(abrSessions{k}, filePattern);
    if isempty(T)
        fprintf(2, '* No valid file names, skipping *\n')
        continue
    end


    abrSessionDate = T.timestamp(1);
    abrSessionDate.Format = "dd-MMM-uuuu";



    td = abrSessionDate;
    td.Format = "uuMMdd";
    ffnOut = fullfile(resultPth,sprintf('%s_%s.mat',T.subject_id(1),td));
    
    if skipExisting && isfile(ffnOut)
        fprintf('\tResults already exist, skipping ...\n')
        continue
    end


    % Extract ABR signals
    [S, U, Fs, winIdx] = extractABRResponses(T, abrSessions{k}, fullWin);





    % Preprocess
    S = rejectArtifacts(S, Fs, winIdx, respWin);
    S = filterABRData(S, Fs, [300 3000]);
    S = cellfun(@(a) detrend(a,2),S,'uni',0,'ErrorHandler',@errEmpty);





    if debug
        fprintf(2,'debug mode enabled\n')
    end



    tvec = fullWin(1)/1000:1/Fs:fullWin(2)/1000;

    % Find threshold
    [thresh_hat,permResult,logModels] = abrPermutationThreshold(S, U, winIdx, Fs, ...
        responseWindow = respWin, ...
        minClusterSize = 1, ...
        thresholdType = "logistic", ...
        debug = debug);


    % [thresh_hat,permResult] = abrPermutationThreshold(S, U, winIdx, Fs, ...
    %     responseWindow = respWin, ...
    %     minClusterSize = 1, ...
    %     thresholdType = "minimum", ...
    %     debug = debug);






    % Plot ABRs
    h = use_fig('ABR_grid');
    plotABRGrid(S, U, Fs, winIdx, plotWindow = plotWindow);
    tl = h.Children;
    title(tl, abrSessionName,Interpreter = 'none');
    subtitle(tl, char(abrSessionDate))
    drawnow

    % Plot ABR audiogram
    h = use_fig('ABR_Audiogram');
    plotABRThresholds(thresh_hat,U.frequency);

    tl = h.Children;
    title(abrSessionName,Interpreter = 'none');
    subtitle(char(abrSessionDate))
    drawnow





    % Save Data
    fprintf('\tsaving results: %s ...',ffnOut)
    save(ffnOut,'T','S','U','Fs','winIdx','thresh_hat','permResult','respWin','tvec');
    fprintf(' done\n')


    % pause
end




%% 2. View and curate data


resultPth = "C:/Users/dstolz/My Drive/PROJECTS/MABR/MABR_Analysis/abr_results";

a = dir(fullfile(resultPth,'*.mat'));


rng(12)
a = a(randperm(length(a)));


skipCurated = true;

for i = 1:length(a)
    fprintf('%d of %d \n',i,length(a))

    fn = a(i).name;

    ffn = fullfile(a(i).folder,fn);


    clear thresh_checked

    load(ffn);

    cm = colorcet('R1','N',length(U.frequency));


    if ~exist('thresh_checked','var')
        thresh_checked = thresh_hat;
    elseif skipCurated
        fprintf('\talready curated, skipping ... \n')
        continue
    end

    use_fig('ABR Thresholds');
    plotABRThresholds(thresh_checked, U.frequency,cm = cm);

    use_fig('ABR Matrix');
    h = plotABRGrid(S, U, Fs, winIdx,cm = cm);

    st = nan(size(U.frequency));
    for j = 1:length(thresh_checked)
        if thresh_checked(j) > max(U.level)
            st(j) = length(U.level);
        else
            st(j) = find(U.level >= fix(thresh_checked(j)),1);
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

    save(ffn,'T','S','U','Fs','winIdx','thresh_hat','thresh_checked')
end



%% 3A. Across Session Analysis

resultPth = "C:/Users/dstolz/My Drive/PROJECTS/MABR/MABR_Analysis/abr_results";

plotWindow = [-2 9];

a = dir(fullfile(resultPth,'*.mat'));

D = cellfun(@(a,b) load(fullfile(a,b)),{a.folder},{a.name},'uni',1);


for i = 1:length(D)
    D(i).subject_id = D(i).T.subject_id(1);
    ts = D(i).T.timestamp(1);
    ts.Format = 'uuMMdd';
    D(i).date = ts;
end
subjs = unique([D.subject_id]);
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
    idx = [D.subject_id] == s;
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
            'DisplayName', char(d(i).date));
    end
    hold(ax1, 'off');
    grid(ax1, 'on');
    set(ax1, 'XScale', 'log');
    xticks(ax1, d(1).U.frequency);
    ylim(ax1, [0 80]);
    titlef(ax1, s);
    legend(ax1, 'Location', 'northwest','Box','off');

    % Second subplot: Threshold shifts
    ax2 = axes('Parent', p, 'Position', [0.1 0.1 0.85 0.35]);
    tc = vertcat(d.thresh_checked);
    dtc = tc - tc(1, :);
    if size(dtc, 1) > 1, dtc(1, :) = []; end
    stem(ax2, d(1).U.frequency, dtc, '-sk', 'LineWidth', 2, ...
        'MarkerFaceColor', 'k');
    grid(ax2, 'on');
    set(ax2, 'XScale', 'log');
    xticks(ax2, d(1).U.frequency);
    yline(ax2, 0, 'LineWidth', 2);
    ylim([-1.1 1.1]*max(abs(ylim)))
end


%% 3B. Sample stats
% Download CSV file for the "Noise Exposure" tab on the Tracker
% https://docs.google.com/spreadsheets/d/1yz6v2yPvJ5x5eadOeCg_mi6VQG9dgERB2v817w_CUrA/edit?gid=838637860#gid=838637860


showIndividuals = false;

NE = readtable(fullfile(resultPth,"Trackers - Noise Exposure.csv"),  ...
    TextType="string", ...
    NumHeaderLines=1);

% assumes same frequencies for all subjects/sessions (true)
X = nan(2,length(U.frequency),length(subjs));
isNE = false(size(subjs));
k = 1;
for s = subjs
    idx = find([D.subject_id] == s);
    X(1:length(idx),:,k) = vertcat(D(idx).thresh_checked);

    isNE(k) = any(NE.SubjectID == s & startsWith(NE.Protocol,"NEID"));
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


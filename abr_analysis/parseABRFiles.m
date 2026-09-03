function T = parseABRFiles(sessionPath, options)
%PARSEABRFILES Parse *.abr MAT files into a table of stimulus params and metadata.
%   T = PARSEABRFILES(sessionPath, filePattern=expr) scans sessionPath for
%   '*.abr' files whose names match the regular expression (default "^SUBJ*").
%   For each matching file, the function loads the variable ABR_Data and builds
%   one table row containing stimulus parameters and file metadata.
%
%   INPUT
%     sessionPath  Folder to scan. Default: current folder returned by CD.
%     filePattern  (name-value in options) Regular expression passed to REGEXP
%                  to filter file names. Only matching files are kept.
%
%   OUTPUT
%     T            Table with columns:
%                    - one variable per entry in ABR_Data.SIG.informativeParams
%                      (values taken from ABR_Data.SIG.(param), cast to double)
%                    - timestamp  : datetime from ABR_Data.StartTime
%                    - fileName   : string file name
%                    - folder     : string folder path
%
%   NOTES
%     - Expects each .abr file to contain a variable 'ABR_Data' with fields:
%       SIG.informativeParams, SIG.(param), StartTime, etc.
%     - Uses PARFOR_PROGRESS for progress reporting if available on the path.
%
%   EXAMPLE
%     T = parseABRFiles("C:\data\session1", filePattern="^SUBJ\d+");
% 
% dstolz@umd.edu 2025

arguments
    sessionPath = cd
    options.filePattern = "^SUBJ*"
end



d = dir(fullfile(sessionPath, '*.abr'));

ind = cellfun(@isempty,regexp({d.name},options.filePattern,'once'));
d(ind) = [];


warning('off','audio:audioPlayerRecorder:invalidDevice')


parfor_progress(length(d),sprintf('Processing %d files\t',length(d)))
for i = 1:length(d)
    
    ffn = fullfile(d(i).folder,d(i).name);
    
    a = load(ffn,'-mat','ABR_Data');


    if ~isfield(a,'ABR_Data')
        fprintf(2,'ABR Data missing: "%s"\n',ffn)
        continue
    end


    a = a.ABR_Data;

    if isstruct(a.SIG)
        p = a.SIG.informativeParams;


        for j= 1:length(p)
            x = double(a.SIG.(p{j}));
            if isempty(x) % old format (?)
                x = a.SIG.dataParams.(p{j});
            end
            T(i).(p{j}) = x;
        end

    end

    T(i).timestamp = datetime(a.StartTime);
    
    T(i).fileName = string(d(i).name);
    
    T(i).folder = string(d(i).folder);

    parfor_progress;
end
parfor_progress(0);

i = cellfun(@isempty,{T.fileName});
T(i) = [];

T = struct2table(T);

warning('on','audio:audioPlayerRecorder:invalidDevice')
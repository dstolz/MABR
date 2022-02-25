classdef Universal < handle
    % class contains general inormation for the ABR software
    
    properties
        MODE (1,1) abr.Cmd {mustBeGreaterThanOrEqual(MODE,126)} = abr.Cmd.Normal;
        
        DACSampleRate = 192000
    end
    
    properties (SetAccess = private)
        
        iconPath        (1,:) char
        hash            (1,:) char
        shortHash       (1,:) char
        commitDate      (1,:) char
        meta            (1,1) struct
        
        availableSignals (1,:) cell
        
        matlabExePath   (1,:) char = fullfile(matlabroot,'bin','matlab.exe');
        runtimePath     (1,:) char
        signalPath      (1,:) char
        errorLogPath    (1,:) char

        comFile         (1,:) char
        inputBufferFile (1,:) char
        inputTimingFile (1,:) char
        dacFile         (1,:) char
        infoFile        (1,:) char
        
        hasAllToolboxes (1,1) logical = false;

                
        
    end
    
    properties (Access = private)
        gitPath
    end
    
    properties (Constant)
        ADCSampleRate = 12000;
        frameLength   = 1024;
        maxInputBufferLength = 2^26; % should be power of 2 enough for at least a minute of data at 192kHz sampling rate

        SoftwareVersion = '22A';
        DataVersion     = '22A';
        Author          = 'Daniel Stolzberg';
        AuthorEmail     = 'daniel.stolzberg@gmail.com';
        GithubRepository= 'https://github.com/dstolz/abr';
        
        RequiredToolboxes = {'MATLAB',9.5; ...
                             'Signal Processing Toolbox',8.1; ...
                             'Audio Toolbox',1.5; ...
                             'DSP System Toolbox',9.1};
                
        DocumentationFile = 'MABR_Help.json'; % must be on Matlab's path
        DocumentationPDF  = 'MABR_Documentation.pdf'; % must be on Matlab's path
    end
    
    methods
        % Constructor
        function obj = Universal()
            
            obj.set_verbosity; % sets GVerbosity from previous pref
            
            obj.errorLogPath = fullfile(fileparts(obj.root),'.error_logs');
            if ~isfolder(obj.errorLogPath), mkdir(obj.errorLogPath); end
            
            obj.runtimePath = fullfile(fileparts(obj.root),'.runtime_data');
            if ~isfolder(obj.runtimePath); mkdir(obj.runtimePath); end

            obj.signalPath = fullfile(obj.root,'+sigdef','+sigs');
            
            obj.dacFile         = fullfile(obj.runtimePath,'dac.wav');
            obj.comFile         = fullfile(obj.runtimePath,'com.dat');
            obj.inputBufferFile = fullfile(obj.runtimePath,'input_buffer.dat');
            obj.inputTimingFile = fullfile(obj.runtimePath,'input_timing.dat');
            obj.infoFile        = fullfile(obj.runtimePath,'info.mat');
            
            
%             try
%                 if ~libisloaded('user32')
%                     loadlibrary('C:\WINDOWS\system32\user32.dll','user32.h');
%                 end
%                 L = calllib('user32', 'GetAsyncKeyState', int32(1)) ~= 0; %#ok<NASGU>
%             catch me
%                 vprintf(0,1,me)
%                 pth = which('mingw.mlpkginstall');
%                 vprintf(0,1,'Must run and install: %s',pth)
%             end
            
        end
        
        function banner(obj)
            banner = [ ...
                {'       __  ______    ____  ____     '}; ...
                {'      /  |/  /   |  / __ )/ __ \    '}; ...
                {'     / /|_/ / /| | / __  / /_/ /    '}; ...
                {'    / /  / / ___ |/ /_/ / _, _/     '}; ...
                {'   /_/  /_/_/  |_/_____/_/ |_|      '}; ...
                {' Matlab Auditory Brainstem Response '}];
            
            
            i = 1;
            banner{i} = sprintf('%s|\tSoftware v%s',banner{i},obj.SoftwareVersion); i = i + 1;
            banner{i} = sprintf('%s|\tData     v%s',banner{i},obj.DataVersion); i = i + 1;
            banner{i} = sprintf('%s|\tgit commit <a href="matlab: web(''%s'',''-browser'')">%s</a>',banner{i},obj.GithubRepository,obj.shortHash); i = i + 1;
            banner{i} = sprintf('%s|',banner{i}); i = i + 1;
            banner{i} = sprintf('%s|\t<a href="matlab: type Copyright.txt">Copyright 2022</a>',banner{i}); i = i + 1;
            banner{i} = sprintf('%s|\t<a href="matlab: disp(''Email: daniel.stolzberg@gmail.com'')">Daniel Stolzberg, PhD</a>',banner{i}); i = i + 1;
            banner{end+1} = '';
            
            disp(char(banner))
            
            obj.hasAllToolboxes;
        end
        
        
        function set.MODE(obj,newMode)
            obj.MODE = newMode;
            vprintf(1,newMode == abr.Cmd.Test,'PROGRAM MODE = %s',char(newMode))
        end
        
        function set_verbosity(obj,v)
            global GVerbosity
            
            if nargin < 2 || isempty(v)
                v = getpref('MABRUniversal','verbosity',1);
            end
            
            GVerbosity = min(max(v,0),4);
            setpref('MABRUniversal','verbosity',GVerbosity);
        end

        
        function m = get.meta(obj)
            m.Author      = obj.Author;
            m.AuthorEmail = obj.AuthorEmail;
            m.Copyright   = 'Copyright to Daniel Stolzberg, 2022';
            m.VersionSoftware = obj.SoftwareVersion;
            m.GithubRepository = obj.GithubRepository;
            m.VersionData = obj.DataVersion;
            m.Checksum    = obj.hash;
            m.CommitDate  = obj.commitDate;
            m.CurrentTimestamp = datestr(now);
            m.HostComputerType = computer;
            [~,n] = dos('hostname');
            m.HostComputerName = n;
            m.MatlabToolboxes = ver;
            
            m = orderfields(m);
        end
        
        
        function s = get.availableSignals(obj)
            d = dir(obj.signalPath);
            s = {d.name};
            ind = startsWith(s,'@');
            s = cellfun(@(a) a(2:end),s(ind),'uni',0);
        end
        
        function p = get.iconPath(obj)
            p = fullfile(obj.root,'icons');
        end
        
            
        function p = get.gitPath(obj)
            p = fileparts(obj.root);
        end
        
        function hash = get.hash(obj)
            hash = nan;
            
            fid = fopen(fullfile(obj.gitPath,'.git','logs','HEAD'),'r');
            
            if fid < 3, return; end
            
            while ~feof(fid), g = fgetl(fid); end
            
            fclose(fid);
            
            a = find(g==' ');
            hash = g(a(1)+1:a(2)-1);
        end
        
        function sc = get.shortHash(obj)
            sc = obj.hash(1:7);
        end
        
        function c = get.commitDate(obj)
            fn = fullfile(obj.gitPath,'.git','logs','HEAD');
            d  = dir(fn);
            c  = d.date;
        end
        
        
        function tf = get.hasAllToolboxes(obj)
            v = ver;
            tf = false(size(obj.RequiredToolboxes,1),1);
            for i = 1:length(v)
                ind = ismember(obj.RequiredToolboxes(:,1),v(i).Name);
                if ~any(ind), continue; end
                tf(ind) = str2double(v(i).Version) >= obj.RequiredToolboxes{ind,2};
            end
            if sum(tf) ~= size(obj.RequiredToolboxes,1)
                rtstr = '';
                for i = 1:size(obj.RequiredToolboxes,1)
                    rtstr = sprintf('%s\t> %s, v%02.1f\n',rtstr,obj.RequiredToolboxes{i,1},obj.RequiredToolboxes{i,2});
                end
                error('The MABR toolbox requires the following toolboxes: \n%s',rtstr)
            end
        end
        
        function img = icon_img(obj,type)
            d = dir(obj.iconPath);
            d(ismember({d.name},{'.','..'})) = [];
            
            files = {d.name};
            files = cellfun(@(a) a(1:find(a=='.',1,'last')-1),files,'uni',0);
            mustBeMember(type,files)
            
            ffn = fullfile(obj.iconPath,type);
            y = dir([ffn '*']);
            ffn = fullfile(y(1).folder,y(1).name);
            [img,map] = imread(ffn);
            if isempty(map)
                img = im2double(img);
            else
                img = ind2rgb(img,map);
            end
            img(img == 0) = nan;
        end
        
        
    end
    
    
    methods (Static)
        
        
        function r = root
            r = fileparts(fileparts(which('abr.Universal')));
        end 
        
        function startup
            U = abr.Universal;
            U.banner;
            U.addpaths;
        end
        
        function addpaths
            r = fileparts(abr.Universal.root);
            addpath(fullfile(r,'helpers'));
            addpath(fullfile(r,'external'));
            addpath(fullfile(r,'advanceFcns'));
        end
        
        
        
        
        function j = get_documentation(obj)
            if nargin == 0
                obj = abr.Universal;
            end
            text = fileread(obj.DocumentationFile);
            j = jsondecode(text);
        end
        
        
        function d = get_doc_description(varargin)
            try
                d = getfield(abr.Universal.get_documentation,'documentation',varargin{:},'description');
            catch me
                d = ['* ' me.message ' *'];
            end
        end
        
        function v = get_doc_value(varargin)
            try
                v = getfield(abr.Universal.get_documentation,varargin{:},'value');
                if ischar(v), v = str2num(v); end %#ok<ST2NM>
            catch me
                v = nan;
            end
        end
        
        function docbox(varargin)
            fs = 12;
            if isnumeric(varargin{1})
                fs = varargin{1};
                varargin(1) = [];
            end
            msg = abr.Universal.get_doc_description(varargin{:});
            msg = sprintf('\\fontsize{%d}%s',fs,msg);
            msg = replace(msg,'char(176)',char(176));
            opt.WindowStyle = 'modal';
            opt.Interpreter = 'tex';
            h = msgbox(msg,'Info','help',opt);
            uiwait(h);
        end
        
        
    end
    
    
end
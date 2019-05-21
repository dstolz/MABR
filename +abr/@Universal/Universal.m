classdef Universal < handle
    % class contains general inormation for the ABR software
    
    properties
    end
    
    properties (SetAccess = private)
        iconPath
        hash
        shortHash
        commitDate
        meta
        
        helpFile
    end
    
    properties (Access = private)
        gitPath
    end
    
    properties (Constant)
        frameLength = 2048;
        
        SoftwareVersion = '0.1 beta';
        DataVersion     = '0.1 beta';    
        Author          = 'Daniel Stolzberg';
        AuthorEmail     = 'daniel.stolzberg@gmail.com';
                
        HelpFile = 'ABR_Help_File.xml'; % must be on Matlab's path
    end
    
    methods
        % Constructor
        function obj = Universal()
            
        end
        
        
        
        function startup(obj)
            banner = [ ...
                '    ___    ____  ____     '; ...
                '   /   |  / __ )/ __ \    '; ...
                '  / /| | / __  / /_/ /    '; ...
                ' / ___ |/ /_/ / _, _/     '; ...
                '/_/  |_/_____/_/ |_|      '];
            banner = cellstr(banner);
            
            banner{1} = sprintf('%s\t|\t<a href="mailto:daniel.stolzberg@gmail.com">Daniel Stolzberg, PhD</a>',banner{1});
            banner{2} = sprintf('%s\t|\t<a href="matlab: type ABRCopyright.txt">copyright 2019</a>',banner{2});
            banner{3} = sprintf('%s\t|\tSoftware = v%s',banner{3},obj.SoftwareVersion);
            banner{4} = sprintf('%s\t|\tData = v%s',banner{4},obj.DataVersion);
            banner{5} = sprintf('%s\t|\tgit hash = <a href="matlab: disp(''%s'')">%s</a>',banner{5},obj.hash,obj.shortHash);
            banner{end+1} = '';
            banner{end+1} = sprintf('\t-> <a href="matlab: abr.ControlPanel;">Control Panel</a>');
            banner{end+1} = sprintf('\t-> <a href="matlab: abr.Calibration;">Audio Calibration</a>');
            banner{end+1} = sprintf('\t-> <a href="matlab: abr.ScheduleDesign;">Stimulus Design</a>');
            
            disp(char(banner))
        end
        
        
        function m = get.meta(obj)
            m.Author      = obj.Author;
            m.AuthorEmail = obj.AuthorEmail;
            m.Copyright   = 'Copyright to Daniel Stolzberg, 2019';
            m.SoftwareVersion = obj.SoftwareVersion;
            m.DataVersion = obj.DataVersion;
            m.Checksum    = obj.hash;
            m.CommitDate  = obj.commitDate;
            m.SmileyFace  = ':)';
            m.CurrentTimestamp = datestr(now);
            
            m = orderfields(m);
        end
        
        function h = get.helpFile(obj)
            h = which(obj.HelpFile);
        end
        
        function p = get.iconPath(obj)
            p = fullfile(obj.root,'icons');
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
            r = which('abr.Universal');
            i = strfind(r,'\@');
            r = r(1:i-1);
        end
        
        
        function s = last_modified_str(datens)
            % s = last_modified_str(datens)
            %
            % Accepts filename, date string, or datenum and returns:
            % 'File last modifed on Sun, May 05, 2019 at 12:19 PM'
            
            narginchk(1,1);
            
            if ischar(datens)
                if exist(datens,'file') == 2
                    d = dir(datens);
                    datens = d(1).date;
                end
                datens = datenum(datens);
            end
                
            s = sprintf('File last modifed on %s at %s', ...
                datestr(datens,'ddd, mmm dd, yyyy'),datestr(datens,'HH:MM PM'));
        end
        
        function r = validate_filename(ffn)
            ffn = cellstr(ffn);
            r = false(size(ffn));
            for i = 1:numel(ffn)
                [~,fn,ext] = fileparts(ffn{i});
                fn = [fn ext]; %#ok<AGROW>
                r(i) = length(fn) <= 255 ...
                    && length(ffn{i}) <= 32000 ...
                    && isempty(regexp(ffn{i}, ['^(?!^(PRN|AUX|CLOCK\$|NUL|CON|COM\d|LPT\d|\..*)', ...
                    '(\..+)?$)[^\x00-\x1f\\?*:\"><|/]+$'], 'once'));
            end
        end
        
        function str = truncate_str(str,maxn,side)
            if nargin < 3 || isempty(side), side = 'left'; end
            mustBeMember(side,{'left' 'right'});
            str = cellstr(str);
            for i = 1:numel(str)
                if length(str{i}) < maxn
                    str{i} = str{i};
                elseif isequal(lower(side),'right')
                    str{i} = [str{i}(1:end-maxn) '...'];
                else
                    str{i} = ['...' str{i}(end-maxn+1:end)];
                end
            end
        end
        
        function keep_figure_on_top(hFig,state)
            % keep_figure_on_top(hFig,state)
            %
            % Maintain figure (figure handle = hFig) on top of all other windows if
            % state = true.
            %
            % No errors or warnings are thrown if for some reason this function is
            % unable to keep hFig on top.
                        
            narginchk(2,2);
            assert(ishandle(hFig),'The first input (hFig) must be a valid figure handle');
            assert(islogical(state)||isscalar(state),'The second input (state) must be true (1) or false (0)');
            
            
            drawnow expose
            
            try %#ok<TRYNC>
                warning('off','MATLAB:HandleGraphics:ObsoletedProperty:JavaFrame');
                J = get(hFig,'JavaFrame');
                if verLessThan('matlab','8.1')
                    J.fHG1Client.getWindow.setAlwaysOnTop(state);
                else
                    J.fHG2Client.getWindow.setAlwaysOnTop(state);
                end
                warning('on','MATLAB:HandleGraphics:ObsoletedProperty:JavaFrame');
            end
        end
        
    end
    
    
end
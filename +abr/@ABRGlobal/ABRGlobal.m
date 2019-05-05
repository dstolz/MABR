classdef ABRGlobal < handle
    % class contains general inormation for the ABR software
    
    properties (SetAccess = private)
        root
        iconPath
        chksum
        commitDate
        meta
    end
    
    properties (Constant)
        Version  = '0.1 beta';
        DataVersion = '0.1 beta';        
        Author = 'Daniel Stolzberg'
        
        
        HelpFile = 'ABR_Help_File.txt'; % must be on Matlab's path
    end
    
    methods
        % Constructor
        function obj = ABRGlobal()
            
        end
        
        function r = get.root(obj)
            r = which('abr.ABRGlobal');
            i = strfind(r,'+abr');
            r = r(1:i-1);
        end
        
        function m = get.meta(obj)
            m.Author      = obj.Author;
            m.Copyright   = 'Copyright to Daniel Stolzberg, 2019';
            m.Version     = obj.Version;
            m.DataVersion = obj.DataVersion;
            m.Checksum    = obj.chksum;
            m.commitDate  = obj.commitDate;
            m.CurrentTimestamp = datestr(now);
        end
        
        function p = get.iconPath(obj)
            p = fullfile(obj.root,'icons');
        end
        
            
        function chksum = get.chksum(obj)
                        
            chksum = nan;
            
            fid = fopen(fullfile(obj.root,'.git','logs','HEAD'),'r');
            
            if fid < 3, return; end
            
            while ~feof(fid), g = fgetl(fid); end
            
            fclose(fid);
            
            a = find(g==' ');
            chksum = g(a(1)+1:a(2)-1);
        end
        
        function c = get.commitDate(obj)
            fn = fullfile(obj.root,'.git','logs','HEAD');
            d  = dir(fn);
            c  = d.date;
        end
        
        function img = icon_img(obj,type)
            mustBeMember(type,{'file_new','file_open','file_save','helpicon'})
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
    end
    
    
end
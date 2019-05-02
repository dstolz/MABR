classdef ABRGlobal < handle
    % class contains general inormation for the ABR software
    
    properties (SetAccess = private)
        root
        iconPath
        chksum
    end
    
    properties (Constant)
        Version = 1.0;

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
    
    
end
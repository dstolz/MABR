classdef ABRGlobal < handle
    % class contains generally pertinent inormation for the ABR software
    
    properties (SetAccess = private)
        root
        chksum
    end
    
    properties (Constant)
        HelpFile = 'ABR_Help_File.txt'; % must be on Matlab's path
        
        version = 0.1;
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
        
            
        function chksum = get.chksum(obj)
                        
            chksum = nan;
            
            fid = fopen(fullfile(obj.root,'.git','logs','HEAD'),'r');
            
            if fid < 3, return; end
            
            while ~feof(fid)
                g = fgetl(fid);
            end
            fclose(fid);
            
            a = find(g==' ');
            chksum = g(a(1)+1:a(2)-1);
        end
        
    end
    
    
end
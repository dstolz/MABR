classdef Click < abr.sigdef.Signal
    % Daniel Stolzberg, PhD (c) 2019
    
    
    properties (Constant)
        type = 'Click';
    end
    
    methods
        
        % Constructor
        function obj = Click(duration)
            obj.ignoreProcessUpdate = true;
            
            if nargin < 1 || isempty(duration), duration = 0.01; end
            
            obj.duration.Value = duration;
            
            % deactivate some default parametes
            obj.windowFcn.Active = false;
            obj.windowOpts.Active = false;
            obj.windowRFTime.Active = false;
            
            obj.soundLevel.Value = '0:10:80';
            
            obj.SortProperty = 'duration';
            
            obj.informativeParams = {'duration'};
            
            obj.ignoreProcessUpdate = false;
        end
        
        function obj = update(obj)
            obj.data = ones(1,obj.N);
        end
    end
    
    
end